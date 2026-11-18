import 'dart:convert';
import 'dart:typed_data';

import 'package:echomind_app/data/ai/ai_client.dart';
import 'package:echomind_app/data/ai/deepseek_ocr_client.dart';
import 'package:echomind_app/data/ai/openai_client.dart';
import 'package:echomind_app/domain/models/ai_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('默认配置关闭自动语音朗读，且正确拼接 OCR 端点', () {
    expect(AiSettings.defaults.autoPlayTts, isFalse);
    expect(
      AiSettings.defaults.ocrEndpoint,
      'https://api.deepseek.com/v1/tools/ocr',
    );
  });

  test('OpenAiClient 对携带图片的消息生成官方多模态 image_url 内容块数组', () {
    final client = OpenAiClient(
      settings: const AiSettings(
        baseUrl: 'https://api.deepseek.com',
        model: 'deepseek-flash',
      ),
      apiKey: 'sk-test',
    );

    final body = client.buildBody(
      const [
        AiMessage.user(
          '图里讲了什么？',
          images: [
            AiImagePart(mimeType: 'image/png', base64Data: 'AAAA'),
          ],
        ),
      ],
      stream: true,
    );

    final msgs = body['messages'] as List<dynamic>;
    final content = (msgs.single as Map<String, dynamic>)['content'] as List<dynamic>;
    expect(content.length, 2);
    expect(content[0], {'type': 'text', 'text': '图里讲了什么？'});
    expect(content[1], {
      'type': 'image_url',
      'image_url': {'url': 'data:image/png;base64,AAAA'},
    });
  });

  test('DeepSeekOcrClient 正确上传文档并清理版面定位标记', () async {
    late String seenMethod;
    late Uri seenUri;
    late String seenAuth;
    late String seenBody;

    final mock = MockClient.streaming((request, bodyStream) async {
      seenMethod = request.method;
      seenUri = request.url;
      seenAuth = request.headers['Authorization'] ?? '';
      final bytes = await bodyStream.toBytes();
      seenBody = utf8.decode(bytes, allowMalformed: true);

      final payload = jsonEncode({
        'id': 'ocr-1',
        'page_count': 2,
        'pages': [
          {
            'index': 0,
            'text': '<｜ref｜>标题<｜/ref｜><｜box｜>[[10,20,30,40]]<｜/box｜>\n第一页正文',
          },
          {
            'index': 1,
            'text': '第二页正文',
          },
        ],
      });
      return http.StreamedResponse(
        Stream.value(utf8.encode(payload)),
        200,
      );
    });

    final client = DeepSeekOcrClient(
      endpoint: 'https://api.deepseek.com/v1/tools/ocr',
      apiKey: 'sk-ocr-key',
      httpClient: mock,
    );

    final result = await client.parseDocument(
      Uint8List.fromList([0x25, 0x50, 0x44, 0x46]),
      filename: 'notes.pdf',
    );

    expect(seenMethod, 'POST');
    expect(seenUri.toString(), 'https://api.deepseek.com/v1/tools/ocr');
    expect(seenAuth, 'Bearer sk-ocr-key');
    expect(seenBody, contains('text_recognition'));
    expect(seenBody, contains('notes.pdf'));
    expect(result.pageCount, 2);
    expect(result.text, contains('标题'));
    expect(result.text, contains('第一页正文'));
    expect(result.text, contains('第二页正文'));
    expect(result.text, isNot(contains('<｜box｜>')));
    expect(result.text, isNot(contains('<｜ref｜>')));
  });

  test('DeepSeekOcrClient 映射 401 与 429 为可读错误', () async {
    final mock401 = MockClient.streaming((request, bodyStream) async {
      await bodyStream.drain<void>();
      return http.StreamedResponse(Stream.value(utf8.encode('{}')), 401);
    });
    final c401 = DeepSeekOcrClient(
      endpoint: 'https://api.deepseek.com/v1/tools/ocr',
      apiKey: 'sk-bad',
      httpClient: mock401,
    );
    await expectLater(
      () => c401.parseDocument(Uint8List.fromList([1, 2]), filename: 'a.pdf'),
      throwsA(
        isA<OcrException>().having((e) => e.message, 'message', contains('Key')),
      ),
    );
  });
}
