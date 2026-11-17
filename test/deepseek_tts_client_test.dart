import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:echomind_app/data/voice/deepseek_tts_client.dart';
import 'package:echomind_app/domain/models/ai_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeSocketChannel implements TtsSocketChannel {
  final StreamController<dynamic> incoming = StreamController<dynamic>();
  final List<String> sentFrames = [];
  bool closed = false;

  @override
  Stream<dynamic> get stream => incoming.stream;

  @override
  void sendTextFrame(String text) {
    sentFrames.add(text);
  }

  @override
  Future<void> close() async {
    closed = true;
    if (!incoming.isClosed) {
      await incoming.close();
    }
  }
}

void main() {
  group('DeepSeekTtsClient WebSocket 流式协议', () {
    test('按官方协议发送 text 与 finish_text，并接收二进制 PCM 与 finish 事件', () async {
      final fakeSocket = _FakeSocketChannel();
      Uri? connectedUri;
      Map<String, dynamic>? connectedHeaders;

      final client = DeepSeekTtsClient(
        settings: const AiSettings(
          baseUrl: 'https://api.deepseek.com',
          ttsVoiceId: 'tide',
        ),
        apiKey: 'sk-tts-key',
        socketConnector: (uri, {required headers}) async {
          connectedUri = uri;
          connectedHeaders = headers;
          return fakeSocket;
        },
      );

      final session = await client.openStreamSession();
      expect(
        connectedUri.toString(),
        'wss://api.deepseek.com/v1/tools/tts?voice_id=tide&format=pcm&filter_markdown=true',
      );
      expect(connectedHeaders?['Authorization'], 'Bearer sk-tts-key');

      final receivedAudio = <Uint8List>[];
      final sub = session.audioChunks.listen(receivedAudio.add);

      session.sendText('第一句通俗类比。');
      session.finishText();

      fakeSocket.incoming.add(Uint8List.fromList([1, 2, 3, 4]));
      fakeSocket.incoming.add(Uint8List.fromList([5, 6, 7, 8]));
      fakeSocket.incoming.add(jsonEncode({
        'event': 'finish',
        'code': 'success',
        'message': '',
      }));

      await session.done;
      await sub.cancel();

      expect(fakeSocket.sentFrames.length, 2);
      expect(
        jsonDecode(fakeSocket.sentFrames[0]),
        {'event': 'text', 'text': '第一句通俗类比。'},
      );
      expect(
        jsonDecode(fakeSocket.sentFrames[1]),
        {'event': 'finish_text'},
      );
      expect(receivedAudio.length, 2);
      expect(receivedAudio[0], [1, 2, 3, 4]);
      expect(fakeSocket.closed, true);
    });
  });

  group('DeepSeekTtsClient HTTP 流式重播', () {
    test('过滤 think 标签并流式返回 PCM 字节', () async {
      Map<String, dynamic>? sentBody;
      final mockHttp = MockClient.streaming((request, bodyStream) async {
        final raw = utf8.decode(await bodyStream.toBytes());
        sentBody = jsonDecode(raw) as Map<String, dynamic>;
        return http.StreamedResponse(
          Stream.fromIterable([
            Uint8List.fromList([10, 20]),
            Uint8List.fromList([30, 40]),
          ]),
          200,
        );
      });

      final client = DeepSeekTtsClient(
        settings: const AiSettings(baseUrl: 'https://api.deepseek.com'),
        apiKey: 'sk-tts-key',
        httpClient: mockHttp,
      );

      final chunks = await client
          .synthesizeStream('<think>草稿</think>你好，咱们开始吧', voiceId: 'stella')
          .toList();

      expect(sentBody?['text'], '你好，咱们开始吧');
      expect(sentBody?['voice_id'], 'stella');
      expect(sentBody?['format'], 'pcm');
      expect(sentBody?['filter_markdown'], true);
      expect(chunks.expand((e) => e).toList(), [10, 20, 30, 40]);
    });
  });
}
