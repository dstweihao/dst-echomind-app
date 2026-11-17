import 'package:echomind_app/features/learn/study_chat_controller.dart';
import 'package:echomind_app/features/learn/widgets/voice_input_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('支持打字/语音模式切换、按住说话松手发送、上滑取消', (tester) async {
    final textCtrl = TextEditingController();
    addTearDown(textCtrl.dispose);

    var started = 0;
    var stopped = 0;
    var canceled = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: VoiceInputBar(
              controller: textCtrl,
              isGenerating: false,
              voicePhase: VoiceInputPhase.idle,
              recordingAmplitude: 0.4,
              recordingDuration: const Duration(seconds: 3),
              onSendText: () {},
              onCancelGeneration: () {},
              onStartRecording: () => started++,
              onStopRecording: () => stopped++,
              onCancelRecording: () => canceled++,
              onTextChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    // 1. 初始为打字模式，点左侧麦克风切到语音模式
    expect(find.byType(TextField), findsOneWidget);
    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pumpAndSettle();
    expect(find.text('按住 说话'), findsOneWidget);

    // 2. 按住不放 → 正常位置松手 → 触发发送
    final holdCenter = tester.getCenter(find.text('按住 说话'));
    final g1 = await tester.startGesture(holdCenter);
    await tester.pump();
    expect(started, 1);
    expect(find.text('松开发送，上滑取消'), findsOneWidget);

    await g1.up();
    await tester.pump();
    expect(stopped, 1);
    expect(canceled, 0);

    // 3. 按住不放 → 上滑超过 56px → 提示取消 → 松手触发取消
    final g2 = await tester.startGesture(holdCenter);
    await tester.pump();
    expect(started, 2);

    await g2.moveBy(const Offset(0, -80));
    await tester.pump();
    expect(find.text('松开手指，取消发送'), findsOneWidget);

    await g2.up();
    await tester.pump();
    expect(canceled, 1);
    expect(stopped, 1);

    // 4. 点左侧键盘图标切回打字模式
    await tester.tap(find.byIcon(Icons.keyboard_alt_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
  });
}
