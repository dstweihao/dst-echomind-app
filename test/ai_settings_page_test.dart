import 'package:echomind_app/data/credentials/credentials_store.dart';
import 'package:echomind_app/data/storage/memory_file_store.dart';
import 'package:echomind_app/domain/models/update_info.dart';
import 'package:echomind_app/features/ai_settings/ai_settings_page.dart';
import 'package:echomind_app/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'update_fakes.dart';

class _FakeSecretStore extends SecretStore {
  String? saved;

  @override
  Future<void> saveAiApiKey(String apiKey) async => saved = apiKey;

  @override
  Future<String?> loadAiApiKey() async => saved;
}

Future<void> _pump(
  WidgetTester tester, {
  required _FakeSecretStore secrets,
  String initialKey = 'sk-test',
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final store = MemoryFileStore();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        initialStorageRootProvider.overrideWithValue(''),
        fileStoreProvider.overrideWithValue(store),
        secretStoreProvider.overrideWithValue(secrets),
        aiApiKeyProvider.overrideWith((ref) async => initialKey),
      ],
      child: const MaterialApp(home: AiSettingsPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('渲染最新 deepseek-flash 模型、语音设置与作者 GitHub 信息，无冗余统计卡片', (tester) async {
    final secrets = _FakeSecretStore();
    await _pump(tester, secrets: secrets, initialKey: 'sk-existing-key');

    // 验证最新推荐模型与语音设置
    expect(find.text('deepseek-flash'), findsWidgets);
    expect(find.text('自动播报回复'), findsOneWidget);
    expect(find.text('海星 · 女声'), findsOneWidget);
    expect(find.text('暗潮 · 男声'), findsOneWidget);

    // 验证保留版本检查与作者个人主页信息
    expect(find.text('检查更新'), findsOneWidget);
    expect(find.text('github.com/dstweihao'), findsOneWidget);
    expect(find.text('https://dstweihao.cn'), findsOneWidget);
    expect(find.text('码上生长'), findsOneWidget);

    // 验证已移除非核心学习统计卡片
    expect(find.text('学习统计'), findsNothing);
    expect(find.text('C++ 38 关进阶路线'), findsNothing);
  });

  testWidgets('输入新 Key 后点击保存正常触发写入', (tester) async {
    final secrets = _FakeSecretStore();
    await _pump(tester, secrets: secrets, initialKey: '');

    final inputFinder = find.byType(TextField);
    expect(inputFinder, findsOneWidget);

    await tester.enterText(inputFinder, 'sk-new-valid-key');
    await tester.pumpAndSettle();

    final saveBtn = find.text('保存');
    await tester.tap(saveBtn);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(secrets.saved, equals('sk-new-valid-key'));
  });

  testWidgets('静默检查发现新版本时，关于卡片展示红点与版本号并可点击弹窗更新', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final secrets = _FakeSecretStore();
    final container = ProviderContainer(
      overrides: [
        initialStorageRootProvider.overrideWithValue(''),
        fileStoreProvider.overrideWithValue(MemoryFileStore()),
        secretStoreProvider.overrideWithValue(secrets),
        aiApiKeyProvider.overrideWith((ref) async => ''),
        appVersionProvider.overrideWith((ref) async => '1.0.1'),
        updateClientProvider.overrideWithValue(
          FakeUpdateClient(
            release: const ReleaseInfo(
              tagName: 'v1.0.2',
              notes: '修复若干边界问题',
              htmlUrl: 'https://github.com/dstweihao/dst-echomind-app/releases/tag/v1.0.2',
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(updateStatusProvider.notifier).check();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AiSettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings_update_badge_dot')), findsOneWidget);
    expect(find.text('发现 v1.0.2'), findsOneWidget);

    await tester.tap(find.text('发现 v1.0.2'));
    await tester.pumpAndSettle();

    expect(find.text('发现新版本 v1.0.2'), findsOneWidget);
    expect(find.text('修复若干边界问题'), findsOneWidget);
  });
}
