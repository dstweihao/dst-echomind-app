import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import 'wav_encoder.dart';

/// 抽象 24kHz PCM 流式音频播放器接口，便于单测注入 Fake 实现
abstract class StreamingAudioPlayer {
  bool get isPlaying;

  /// 开启一轮新的流式播报（会先打断上一轮残留播报）
  void beginSession({void Function()? onComplete});

  /// 喂入来自 DeepSeek TTS 的原始 24kHz 16-bit LE 单声道 PCM 字节
  void feedPcm16(Uint8List pcmBytes);

  /// 标记服务端音频流已全部送达，待剩余队列播放完成后触发 onComplete
  void markEndOfStream();

  /// 立即打断静音并清空所有队列
  void stop();

  void dispose();
}

/// 基于 `flutter_soloud` (C++ FFI + miniaudio) 的四端原生 24kHz 连续原始 PCM 流式播放器
///
/// 整段 AI 回复是一条不断裂的连续 24kHz 16-bit LE 单声道 PCM 音频流：
/// - 零文件切分、零字中硬切、0ms 段间切换间隙，丝滑度对齐豆包；
/// - `BufferingType.released` 自动回收已播内存，长语音无内存膨胀；
/// - `stop()` 直接调用底层 C++ 句柄停播，实现毫秒级打断。
class SoLoudStreamingAudioPlayer implements StreamingAudioPlayer {
  static const int _sampleRate = WavEncoder.ttsSampleRate; // 24000 Hz

  AudioSource? _source;
  SoundHandle? _handle;
  StreamSubscription<StreamSoundEvent>? _eventSub;

  final Queue<Uint8List> _preInitQueue = Queue<Uint8List>();
  int? _carryByte;
  int _sessionToken = 0;
  bool _playing = false;
  bool _sourceReady = false;
  bool _endOfStreamPending = false;
  bool _endMarked = false;
  void Function()? _onComplete;

  @override
  bool get isPlaying => _playing;

  @override
  void beginSession({void Function()? onComplete}) {
    stop();
    final token = ++_sessionToken;
    _onComplete = onComplete;
    _playing = true;
    _sourceReady = false;
    _endOfStreamPending = false;
    _endMarked = false;
    _carryByte = null;
    _preInitQueue.clear();

    unawaited(_initAndStart(token));
  }

  Future<void> _initAndStart(int token) async {
    try {
      final soloud = SoLoud.instance;
      if (!soloud.isInitialized) {
        await soloud.init(
          sampleRate: _sampleRate,
          channels: Channels.mono,
        );
      }
      if (!_playing || token != _sessionToken) return;

      final source = soloud.setBufferStream(
        maxBufferSizeBytes: 16 * 1024 * 1024,
        bufferingType: BufferingType.released,
        bufferingTimeNeeds: 0.25,
        sampleRate: _sampleRate,
        channels: Channels.mono,
        format: BufferType.s16le,
      );

      if (!_playing || token != _sessionToken) {
        unawaited(soloud.disposeSource(source).catchError((_) {}));
        return;
      }

      _source = source;
      _eventSub = source.soundEvents.listen((evt) {
        if (token != _sessionToken || !_playing) return;
        if (evt.event == SoundEventType.handleIsNoMoreValid ||
            evt.event == SoundEventType.soundDisposed) {
          _finishSession(token);
        }
      });

      final handle = soloud.play(source);
      if (!_playing || token != _sessionToken) {
        unawaited(soloud.stop(handle).catchError((_) {}));
        unawaited(soloud.disposeSource(source).catchError((_) {}));
        return;
      }

      _handle = handle;
      _sourceReady = true;

      // 将引擎初始化期间暂存的首批 PCM 立即灌入环形缓冲
      while (_preInitQueue.isNotEmpty) {
        final chunk = _preInitQueue.removeFirst();
        _pushAlignedToSoLoud(source, chunk);
      }

      if (_endOfStreamPending && !_endMarked) {
        _endMarked = true;
        soloud.setDataIsEnded(source);
      }
    } catch (e) {
      debugPrint('SoLoud init/start error: $e');
      if (token == _sessionToken && _playing) {
        _finishSession(token);
      }
    }
  }

  @override
  void feedPcm16(Uint8List pcmBytes) {
    if (!_playing || pcmBytes.isEmpty) return;

    // 奇数字节跨包对齐，确保每个 16-bit 样本完整无杂音
    Uint8List aligned;
    if (_carryByte != null) {
      aligned = Uint8List(pcmBytes.length + 1);
      aligned[0] = _carryByte!;
      aligned.setRange(1, aligned.length, pcmBytes);
      _carryByte = null;
    } else {
      aligned = pcmBytes;
    }

    var usable = aligned.length;
    if (usable.isOdd) {
      _carryByte = aligned[usable - 1];
      usable -= 1;
    }
    if (usable <= 0) return;

    final cleanBytes = usable == aligned.length
        ? aligned
        : Uint8List.fromList(Uint8List.sublistView(aligned, 0, usable));

    if (_sourceReady && _source != null) {
      _pushAlignedToSoLoud(_source!, cleanBytes);
    } else {
      _preInitQueue.add(cleanBytes);
    }
  }

  @override
  void markEndOfStream() {
    if (!_playing) return;
    _endOfStreamPending = true;
    final src = _source;
    if (_sourceReady && src != null && !_endMarked) {
      _endMarked = true;
      try {
        SoLoud.instance.setDataIsEnded(src);
      } catch (e) {
        debugPrint('SoLoud setDataIsEnded error: $e');
      }
    }
  }

  @override
  void stop() {
    _sessionToken++;
    _playing = false;
    _sourceReady = false;
    _endOfStreamPending = false;
    _endMarked = false;
    _onComplete = null;
    _carryByte = null;
    _preInitQueue.clear();

    final sub = _eventSub;
    _eventSub = null;
    if (sub != null) {
      unawaited(sub.cancel());
    }

    final handle = _handle;
    final src = _source;
    _handle = null;
    _source = null;

    final soloud = SoLoud.instance;
    if (soloud.isInitialized) {
      if (handle != null) {
        unawaited(soloud.stop(handle).catchError((_) {}));
      }
      if (src != null) {
        unawaited(soloud.disposeSource(src).catchError((_) {}));
      }
    }
  }

  @override
  void dispose() {
    stop();
  }

  void _pushAlignedToSoLoud(AudioSource source, Uint8List pcmBytes) {
    try {
      SoLoud.instance.addAudioDataStream(source, pcmBytes);
    } catch (e) {
      debugPrint('SoLoud addAudioDataStream error: $e');
    }
  }

  void _finishSession(int token) {
    if (token != _sessionToken || !_playing) return;
    final cb = _onComplete;
    final src = _source;
    _playing = false;
    _sourceReady = false;
    _onComplete = null;
    _handle = null;
    _source = null;

    final sub = _eventSub;
    _eventSub = null;
    if (sub != null) {
      unawaited(sub.cancel());
    }

    if (src != null && SoLoud.instance.isInitialized) {
      unawaited(SoLoud.instance.disposeSource(src).catchError((_) {}));
    }

    cb?.call();
  }
}
