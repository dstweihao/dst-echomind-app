import 'package:echomind_app/domain/models/knowledge_models.dart';
import 'package:echomind_app/features/learn/study_chat_controller.dart';
import 'package:echomind_app/features/learn/widgets/voice_input_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets('支持点击 + 弹出拍照/相册/文件选项，且仅附带附件时可直接发送', (tester) async {
    final textCtrl = TextEditingController();
    addTearDown(textCtrl.dispose);

    var cameraTapped = 0;
    var galleryTapped = 0;
    var filesTapped = 0;
    var sent = 0;
    String? removedId;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: VoiceInputBar(
              controller: textCtrl,
              isGenerating: false,
              voicePhase: VoiceInputPhase.idle,
              recordingAmplitude: 0.0,
              recordingDuration: Duration.zero,
              supportsCamera: true,
              pendingAttachments: const [
                StudyAttachment(
                  id: 'att-1',
                  kind: StudyAttachmentKind.file,
                  name: 'lecture.pdf',
                  localPath: '',
                  mimeType: 'application/pdf',
                  sizeBytes: 2048,
                ),
              ],
              onSendText: () => sent++,
              onCancelGeneration: () {},
              onStartRecording: () {},
              onStopRecording: () {},
              onCancelRecording: () {},
              onTextChanged: (_) {},
              onPickCamera: () => cameraTapped++,
              onPickGallery: () => galleryTapped++,
              onPickFiles: () => filesTapped++,
              onRemoveAttachment: (id) => removedId = id,
            ),
          ),
        ),
      ),
    );

    // 1. 待发送附件条渲染文件名与大小，且无文字也可发送
    expect(find.text('lecture.pdf'), findsOneWidget);
    expect(find.text('2.0 KB'), findsOneWidget);
    await tester.tap(find.byKey(const Key('send_message_btn')));
    await tester.pump();
    expect(sent, 1);

    // 2. 点击 + 弹出拍照 / 相册 / 文件面板
    await tester.tap(find.byKey(const Key('add_attachment_btn')));
    await tester.pumpAndSettle();
    expect(find.text('拍照'), findsOneWidget);
    expect(find.text('相册'), findsOneWidget);
    expect(find.text('文件'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pick_camera_btn')));
    await tester.pumpAndSettle();
    expect(cameraTapped, 1);

    await tester.tap(find.byKey(const Key('add_attachment_btn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick_gallery_btn')));
    await tester.pumpAndSettle();
    expect(galleryTapped, 1);

    await tester.tap(find.byKey(const Key('add_attachment_btn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick_files_btn')));
    await tester.pumpAndSettle();
    expect(filesTapped, 1);

    // 3. 点击附件上的删除按钮
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(removedId, 'att-1');
  });

  testWidgets(
    'macOS 按 Cmd+V 优先粘贴剪贴板图片，无图片时无缝回落粘贴纯文本',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    (tester) async {
      final textCtrl = TextEditingController();
      addTearDown(textCtrl.dispose);

    var pasteCalls = 0;
    var hasImageInClipboard = true;
    String? lastChanged;

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          return {'text': '纯文本剪贴板内容'};
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: VoiceInputBar(
              controller: textCtrl,
              isGenerating: false,
              voicePhase: VoiceInputPhase.idle,
              recordingAmplitude: 0.0,
              recordingDuration: Duration.zero,
              onSendText: () {},
              onCancelGeneration: () {},
              onStartRecording: () {},
              onStopRecording: () {},
              onCancelRecording: () {},
              onTextChanged: (v) => lastChanged = v,
              onPasteFromClipboard: () async {
                pasteCalls++;
                return hasImageInClipboard;
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();

    // 1. 剪贴板有图片：命中图片粘贴，不写入纯文本
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    expect(pasteCalls, 1);
    expect(textCtrl.text, isEmpty);

    // 2. 剪贴板无图片：回落粘贴纯文本
    hasImageInClipboard = false;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    expect(pasteCalls, 2);
    expect(textCtrl.text, '纯文本剪贴板内容');
    expect(lastChanged, '纯文本剪贴板内容');
  });

  testWidgets(
    'Windows 按 Ctrl+V 触发剪贴板图片粘贴',
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    (tester) async {
      final textCtrl = TextEditingController();
      addTearDown(textCtrl.dispose);

    var pasteCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: VoiceInputBar(
              controller: textCtrl,
              isGenerating: false,
              voicePhase: VoiceInputPhase.idle,
              recordingAmplitude: 0.0,
              recordingDuration: Duration.zero,
              onSendText: () {},
              onCancelGeneration: () {},
              onStartRecording: () {},
              onStopRecording: () {},
              onCancelRecording: () {},
              onTextChanged: (_) {},
              onPasteFromClipboard: () async {
                pasteCalls++;
                return true;
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(pasteCalls, 1);
  });
}
