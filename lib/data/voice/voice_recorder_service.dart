import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:record/record.dart';

import 'wav_encoder.dart';

/// 录音结果（16kHz 单声道 16-bit WAV 字节流）
class RecordedAudio {
  final Uint8List wavBytes;
  final Duration duration;

  const RecordedAudio({
    required this.wavBytes,
    required this.duration,
  });
}

/// 抽象语音录制接口，便于在单测中注入 Fake 实现
abstract class VoiceRecorderService {
  Stream<double> get amplitudeStream;
  Stream<Duration> get durationStream;
  bool get isRecording;

  Future<bool> hasPermission();
  Future<void> start({void Function()? onMaxDurationReached});
  Future<RecordedAudio?> stop();
  Future<void> cancel();
  Future<void> dispose();
}

/// 基于 `record` 的四端原生（Android / iOS / macOS / Windows）录音服务
///
/// 采用 16kHz 单声道 16-bit PCM 流式采集并在内存中封包为标准 WAV，
/// 无需读写临时文件，且自动保证单次时长 ≤ 120 秒（DeepSeek ASR 上限）。
class RecordVoiceRecorderService implements VoiceRecorderService {
  static const Duration maxDuration = Duration(seconds: 120);

  final AudioRecorder _recorder = AudioRecorder();
  final StreamController<double> _amplitudeCtrl =
      StreamController<double>.broadcast();
  final StreamController<Duration> _durationCtrl =
      StreamController<Duration>.broadcast();

  BytesBuilder? _pcmBuffer;
  StreamSubscription<Uint8List>? _pcmSub;
  Timer? _tickTimer;
  DateTime? _startedAt;
  bool _recording = false;

  @override
  Stream<double> get amplitudeStream => _amplitudeCtrl.stream;

  @override
  Stream<Duration> get durationStream => _durationCtrl.stream;

  @override
  bool get isRecording => _recording;

  @override
  Future<bool> hasPermission() async {
    try {
      return await _recorder.hasPermission();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> start({void Function()? onMaxDurationReached}) async {
    if (_recording) return;

    final granted = await hasPermission();
    if (!granted) {
      throw StateError('未获得麦克风权限，请在系统设置中允许「回响」访问麦克风');
    }

    // iOS 录音与扬声器外放共存配置，确保后续 TTS 从外放扬声器清晰播放
    if (Platform.isIOS) {
      try {
        await _recorder.ios?.setAudioSessionCategory(
          category: IosAudioCategory.playAndRecord,
          options: const [
            IosAudioCategoryOptions.defaultToSpeaker,
            IosAudioCategoryOptions.allowBluetooth,
            IosAudioCategoryOptions.allowBluetoothA2DP,
          ],
        );
      } catch (_) {}
    }

    _pcmBuffer = BytesBuilder(copy: false);
    _startedAt = DateTime.now();
    _recording = true;
    _durationCtrl.add(Duration.zero);
    _amplitudeCtrl.add(0.0);

    const config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: WavEncoder.asrSampleRate,
      numChannels: 1,
    );

    final stream = await _recorder.startStream(config);
    _pcmSub = stream.listen(
      (chunk) {
        if (!_recording || chunk.isEmpty) return;
        _pcmBuffer?.add(chunk);
        _amplitudeCtrl.add(WavEncoder.computeRmsLevel(chunk));
      },
      onError: (_) {},
    );

    _tickTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!_recording || _startedAt == null) return;
      final elapsed = DateTime.now().difference(_startedAt!);
      _durationCtrl.add(elapsed);
      if (elapsed >= maxDuration) {
        onMaxDurationReached?.call();
      }
    });
  }

  @override
  Future<RecordedAudio?> stop() async {
    if (!_recording) return null;
    _recording = false;
    _tickTimer?.cancel();
    _tickTimer = null;

    final elapsed = _startedAt != null
        ? DateTime.now().difference(_startedAt!)
        : Duration.zero;
    _startedAt = null;

    try {
      await _recorder.stop();
    } catch (_) {}
    await _pcmSub?.cancel();
    _pcmSub = null;
    _amplitudeCtrl.add(0.0);

    final pcmBytes = _pcmBuffer?.takeBytes() ?? Uint8List(0);
    _pcmBuffer = null;

    if (pcmBytes.isEmpty) return null;

    final wavBytes = WavEncoder.encodePcm16ToWav(
      pcmBytes,
      sampleRate: WavEncoder.asrSampleRate,
      channels: 1,
    );
    return RecordedAudio(wavBytes: wavBytes, duration: elapsed);
  }

  @override
  Future<void> cancel() async {
    _recording = false;
    _tickTimer?.cancel();
    _tickTimer = null;
    _startedAt = null;
    _pcmBuffer = null;

    try {
      await _recorder.cancel();
    } catch (_) {}
    await _pcmSub?.cancel();
    _pcmSub = null;
    _amplitudeCtrl.add(0.0);
    _durationCtrl.add(Duration.zero);
  }

  @override
  Future<void> dispose() async {
    await cancel();
    await _recorder.dispose();
    await _amplitudeCtrl.close();
    await _durationCtrl.close();
  }
}
