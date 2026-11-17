import 'dart:typed_data';

import 'package:echomind_app/data/voice/wav_encoder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WavEncoder', () {
    test('生成合法 44 字节 RIFF/WAVE 头与 PCM 数据体', () {
      final pcm = Uint8List.fromList([0x00, 0x00, 0xFF, 0x7F, 0x00, 0x80]);
      final wav = WavEncoder.encodePcm16ToWav(pcm, sampleRate: 16000, channels: 1);

      expect(wav.length, 44 + pcm.length);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(wav.sublist(12, 16)), 'fmt ');
      expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');

      final bd = ByteData.sublistView(wav);
      expect(bd.getUint32(4, Endian.little), 36 + pcm.length);
      expect(bd.getUint16(20, Endian.little), 1); // PCM
      expect(bd.getUint16(22, Endian.little), 1); // mono
      expect(bd.getUint32(24, Endian.little), 16000);
      expect(bd.getUint32(28, Endian.little), 32000); // byteRate
      expect(bd.getUint16(34, Endian.little), 16); // bitsPerSample
      expect(bd.getUint32(40, Endian.little), pcm.length);
      expect(wav.sublist(44), pcm);
    });

    test('computeRmsLevel 静音为 0，大音量接近 1', () {
      final silence = Uint8List(64);
      expect(WavEncoder.computeRmsLevel(silence), 0.0);

      final loud = Uint8List(64);
      final bd = ByteData.sublistView(loud);
      for (var i = 0; i < 32; i++) {
        bd.setInt16(i * 2, 20000, Endian.little);
      }
      expect(WavEncoder.computeRmsLevel(loud), greaterThan(0.9));
    });
  });

  group('Pcm16ToFloat32Converter', () {
    test('跨帧奇数字节残留不错位', () {
      final converter = Pcm16ToFloat32Converter();
      // 两个样本：16384 (0x00, 0x40) 和 -16384 (0x00, 0xC0)，故意按 3 + 1 字节拆包
      final first = converter.convert(Uint8List.fromList([0x00, 0x40, 0x00]));
      expect(first.length, 1);
      expect(first[0], closeTo(0.5, 0.001));

      final second = converter.convert(Uint8List.fromList([0xC0]));
      expect(second.length, 1);
      expect(second[0], closeTo(-0.5, 0.001));
    });
  });

  group('TtsTextChunker & stripThinkTags', () {
    test('过滤 think 块且只输出正文语义分片', () {
      final chunker = TtsTextChunker();
      final out = <String>[];

      out.addAll(chunker.addDelta('<thi'));
      out.addAll(chunker.addDelta('nk>内部推理过程不应该被朗读</think>'));
      out.addAll(chunker.addDelta('通货膨胀就像小岛上的钱变多了。'));
      out.addAll(chunker.addDelta('你猜苹果会涨价吗？'));
      out.addAll(chunker.flush());

      expect(out, [
        '通货膨胀就像小岛上的钱变多了。',
        '你猜苹果会涨价吗？',
      ]);
      expect(out.join(), isNot(contains('内部推理')));
    });

    test('stripThinkTags 清除完整与未闭合 think 块', () {
      expect(
        stripThinkTags('<think>草稿</think>正文回答'),
        '正文回答',
      );
      expect(
        stripThinkTags('开头<think>尚未闭合的思考'),
        '开头',
      );
    });
  });
}
