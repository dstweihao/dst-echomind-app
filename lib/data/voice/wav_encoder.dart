import 'dart:math' as math;
import 'dart:typed_data';

/// 纯 Dart PCM / WAV 编解码与流式文本分片工具
///
/// - 录音端：将 16kHz 单声道 16-bit LE PCM 字节封装为标准 44 字节 WAV，直接上传 DeepSeek ASR。
/// - 播报端：将 DeepSeek TTS 返回的 24kHz 单声道 16-bit LE PCM 转为 Float32（含奇数字节跨包处理）。
class WavEncoder {
  WavEncoder._();

  static const int asrSampleRate = 16000;
  static const int ttsSampleRate = 24000;

  /// 为原始 16-bit 有符号小端 PCM 字节流封装标准 44 字节 RIFF/WAVE 文件头
  static Uint8List encodePcm16ToWav(
    Uint8List pcmBytes, {
    int sampleRate = asrSampleRate,
    int channels = 1,
    int bitsPerSample = 16,
  }) {
    final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
    final blockAlign = channels * (bitsPerSample ~/ 8);
    final dataLength = pcmBytes.length;
    final totalLength = 44 + dataLength;

    final out = Uint8List(totalLength);
    final bd = ByteData.sublistView(out);

    // RIFF header
    out.setRange(0, 4, const [0x52, 0x49, 0x46, 0x46]); // "RIFF"
    bd.setUint32(4, 36 + dataLength, Endian.little);
    out.setRange(8, 12, const [0x57, 0x41, 0x56, 0x45]); // "WAVE"

    // fmt sub-chunk
    out.setRange(12, 16, const [0x66, 0x6D, 0x74, 0x20]); // "fmt "
    bd.setUint32(16, 16, Endian.little); // Subchunk1Size = 16 for PCM
    bd.setUint16(20, 1, Endian.little); // AudioFormat = 1 (PCM)
    bd.setUint16(22, channels, Endian.little);
    bd.setUint32(24, sampleRate, Endian.little);
    bd.setUint32(28, byteRate, Endian.little);
    bd.setUint16(32, blockAlign, Endian.little);
    bd.setUint16(34, bitsPerSample, Endian.little);

    // data sub-chunk
    out.setRange(36, 40, const [0x64, 0x61, 0x74, 0x61]); // "data"
    bd.setUint32(40, dataLength, Endian.little);
    out.setRange(44, totalLength, pcmBytes);

    return out;
  }

  /// 计算 16-bit LE PCM 块的归一化 RMS 音量（0.0 ~ 1.0），用于录音波形动效
  static double computeRmsLevel(Uint8List pcmBytes) {
    final sampleCount = pcmBytes.length ~/ 2;
    if (sampleCount == 0) return 0.0;

    final bd = ByteData.sublistView(pcmBytes);
    double sumSquares = 0.0;
    for (var i = 0; i < sampleCount; i++) {
      final sample = bd.getInt16(i * 2, Endian.little) / 32768.0;
      sumSquares += sample * sample;
    }
    final rms = math.sqrt(sumSquares / sampleCount);
    // 适当放大语音常见幅度并钳位，波形反馈更灵敏自然
    return (rms * 3.2).clamp(0.0, 1.0);
  }
}

/// 有状态的 16-bit LE PCM → Float32 转换器，正确处理 WebSocket/HTTP 分包导致的奇数字节残留
class Pcm16ToFloat32Converter {
  int? _carryByte;

  Float32List convert(Uint8List chunk) {
    if (chunk.isEmpty) return Float32List(0);

    Uint8List merged;
    if (_carryByte != null) {
      merged = Uint8List(chunk.length + 1);
      merged[0] = _carryByte!;
      merged.setRange(1, merged.length, chunk);
      _carryByte = null;
    } else {
      merged = chunk;
    }

    var usableBytes = merged.length;
    if (usableBytes.isOdd) {
      _carryByte = merged[usableBytes - 1];
      usableBytes -= 1;
    }

    final sampleCount = usableBytes ~/ 2;
    if (sampleCount == 0) return Float32List(0);

    final bd = ByteData.sublistView(merged, 0, usableBytes);
    final out = Float32List(sampleCount);
    for (var i = 0; i < sampleCount; i++) {
      out[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return out;
  }

  void reset() {
    _carryByte = null;
  }
}

/// 去除回复正文中的 `<think>...</think>` 内部思考段落，确保语音只朗读正文
String stripThinkTags(String text) {
  var cleaned = text.replaceAll(
    RegExp(r'<think>[\s\S]*?<\/think>', caseSensitive: false),
    '',
  );
  cleaned = cleaned.replaceAll(
    RegExp(r'<think>[\s\S]*$', caseSensitive: false),
    '',
  );
  return cleaned.trim();
}

/// 流式文本 → TTS 分片缓冲器
///
/// 在 LLM 逐 token 输出时：
/// 1. 自动跳过 `<think>...</think>` 内部思考文本；
/// 2. 遇到自然停顿标点（。！？；\n）或缓冲达到一定长度时输出适合语音合成的语义分片，
///    兼顾“首字最快出声”与“语音韵律连贯”。
class TtsTextChunker {
  static final RegExp _boundary = RegExp(r'[。！？!?;；\n]');
  static final RegExp _softBoundary = RegExp(r'[，,、：:]');

  final int minSoftChunkLength;
  final int maxChunkLength;

  final StringBuffer _rawPending = StringBuffer();
  final StringBuffer _speakPending = StringBuffer();
  bool _inThinkBlock = false;
  bool _emittedFirst = false;

  TtsTextChunker({
    this.minSoftChunkLength = 14,
    this.maxChunkLength = 36,
  });

  /// 输入增量 delta，返回本轮可立即送往 TTS 的分片列表
  List<String> addDelta(String delta) {
    if (delta.isEmpty) return const [];
    _rawPending.write(delta);
    _drainRawIntoSpeak();
    return _extractReadyChunks(force: false);
  }

  /// LLM 流结束时冲刷剩余所有待朗读文本
  List<String> flush() {
    if (!_inThinkBlock && _rawPending.isNotEmpty) {
      _speakPending.write(_rawPending.toString());
      _rawPending.clear();
    }
    return _extractReadyChunks(force: true);
  }

  void _drainRawIntoSpeak() {
    var buf = _rawPending.toString();
    _rawPending.clear();

    while (buf.isNotEmpty) {
      if (_inThinkBlock) {
        final endIdx = buf.toLowerCase().indexOf('</think>');
        if (endIdx == -1) {
          // 仅保留末尾可能截断的 `</think` 前缀
          final keep = math.min(buf.length, 8);
          _rawPending.write(buf.substring(buf.length - keep));
          return;
        }
        buf = buf.substring(endIdx + '</think>'.length);
        _inThinkBlock = false;
      } else {
        final startIdx = buf.toLowerCase().indexOf('<think>');
        if (startIdx == -1) {
          // 保留末尾可能尚未完整的 `<think` 前缀
          final ltIdx = buf.lastIndexOf('<');
          if (ltIdx != -1 && buf.length - ltIdx < '<think>'.length) {
            _speakPending.write(buf.substring(0, ltIdx));
            _rawPending.write(buf.substring(ltIdx));
          } else {
            _speakPending.write(buf);
          }
          return;
        }
        if (startIdx > 0) {
          _speakPending.write(buf.substring(0, startIdx));
        }
        buf = buf.substring(startIdx + '<think>'.length);
        _inThinkBlock = true;
      }
    }
  }

  List<String> _extractReadyChunks({required bool force}) {
    final chunks = <String>[];
    var text = _speakPending.toString();
    _speakPending.clear();

    while (text.isNotEmpty) {
      final hardMatch = _boundary.firstMatch(text);
      if (hardMatch != null) {
        final cut = hardMatch.end;
        final piece = text.substring(0, cut).trim();
        if (piece.isNotEmpty) {
          chunks.add(piece);
          _emittedFirst = true;
        }
        text = text.substring(cut);
        continue;
      }

      // 首句尽早在逗号处发出，降低首音等待时间
      final softThreshold = _emittedFirst ? minSoftChunkLength : 8;
      if (text.length >= softThreshold) {
        final softMatch = _softBoundary.firstMatch(text.substring(softThreshold - 1));
        if (softMatch != null) {
          final cut = (softThreshold - 1) + softMatch.end;
          final piece = text.substring(0, cut).trim();
          if (piece.isNotEmpty) {
            chunks.add(piece);
            _emittedFirst = true;
          }
          text = text.substring(cut);
          continue;
        }
      }

      if (text.length >= maxChunkLength) {
        final piece = text.substring(0, maxChunkLength).trim();
        if (piece.isNotEmpty) {
          chunks.add(piece);
          _emittedFirst = true;
        }
        text = text.substring(maxChunkLength);
        continue;
      }

      break;
    }

    if (force) {
      final rest = text.trim();
      if (rest.isNotEmpty) chunks.add(rest);
    } else if (text.isNotEmpty) {
      _speakPending.write(text);
    }

    return chunks;
  }
}
