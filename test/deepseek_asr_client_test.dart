import 'dart:convert';
import 'dart:typed_data';

import 'package:echomind_app/data/voice/deepseek_asr_client.dart';
import 'package:echomind_app/data/voice/wav_encoder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('DeepSeekAsrClient', () {
    test('正确上传 multipart WAV 并解析转写文本', () async {
      String? capturedAuth;
      Uri? capturedUri;

      final mockHttp = MockClient.streaming((request, bodyStream) async {
        capturedUri = request.url;
        capturedAuth = request.headers['Authorization'];
        await bodyStream.toBytes();
        final payload = utf8.encode(jsonEncode({
          'request_id': 'req-123',
          'text': '通货膨胀到底是什么意思？',
          'duration_ms': 2400,
        }));
        return http.StreamedResponse(Stream.value(payload), 200);
      });

      final client = DeepSeekAsrClient(
        endpoint: 'https://api.deepseek.com/v1/tools/asr',
        apiKey: 'sk-voice-test',
        httpClient: mockHttp,
      );

      final wav = WavEncoder.encodePcm16ToWav(Uint8List(3200));
      final result = await client.transcribeWav(wav);

      expect(capturedUri, Uri.parse('https://api.deepseek.com/v1/tools/asr'));
      expect(capturedAuth, 'Bearer sk-voice-test');
      expect(result.text, '通货膨胀到底是什么意思？');
      expect(result.durationMs, 2400);
      expect(result.requestId, 'req-123');
    });

    test('拦截空录音与超过 8MB 音频', () async {
      final client = DeepSeekAsrClient(
        endpoint: 'https://api.deepseek.com/v1/tools/asr',
        apiKey: 'sk-voice-test',
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );

      expect(
        () => client.transcribeWav(Uint8List(44)),
        throwsA(isA<AsrException>()),
      );
      expect(
        () => client.transcribeWav(Uint8List(8 * 1024 * 1024 + 1)),
        throwsA(isA<AsrException>()),
      );
    });

    test('映射 401 与 429 错误为可读中文提示', () async {
      final mock401 = MockClient.streaming((_, _) async {
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"error":{"message":"invalid key"}}')),
          401,
        );
      });
      final c1 = DeepSeekAsrClient(
        endpoint: 'https://api.deepseek.com/v1/tools/asr',
        apiKey: 'sk-bad',
        httpClient: mock401,
      );
      await expectLater(
        c1.transcribeWav(WavEncoder.encodePcm16ToWav(Uint8List(100))),
        throwsA(
          isA<AsrException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.message, 'message', contains('API Key')),
        ),
      );
    });
  });
}
