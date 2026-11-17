import 'package:echomind_app/app.dart';
import 'package:echomind_app/data/storage/memory_file_store.dart';
import 'package:echomind_app/domain/models/update_info.dart';
import 'package:echomind_app/features/learn/learn_page.dart';
import 'package:echomind_app/providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'update_fakes.dart';

void main() {
  testWidgets('启动后直接进入学习界面，无引导门槛', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialStorageRootProvider.overrideWithValue(''),
          fileStoreProvider.overrideWithValue(MemoryFileStore()),
          aiApiKeyProvider.overrideWith((ref) async => null),
          updateClientProvider.overrideWithValue(FakeUpdateClient()),
        ],
        child: const EchoMindApp(),
      ),
    );

    var booted = false;
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (tester.any(find.byType(LearnPage))) {
        booted = true;
        break;
      }
    }

    expect(booted, true, reason: '启动后应落在学习界面');
    expect(find.byType(LearnPage), findsOneWidget);
  });

  testWidgets('AI 未配置时给出提示但不阻断进入', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialStorageRootProvider.overrideWithValue(''),
          fileStoreProvider.overrideWithValue(MemoryFileStore()),
          aiApiKeyProvider.overrideWith((ref) async => null),
          updateClientProvider.overrideWithValue(FakeUpdateClient()),
        ],
        child: const EchoMindApp(),
      ),
    );

    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (tester.any(find.text('去配置'))) break;
    }

    expect(find.text('去配置'), findsOneWidget);
  });

  testWidgets('启动静默检查发现新版本时，首页设置图标展示红点提示', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialStorageRootProvider.overrideWithValue(''),
          fileStoreProvider.overrideWithValue(MemoryFileStore()),
          aiApiKeyProvider.overrideWith((ref) async => null),
          appVersionProvider.overrideWith((ref) async => '1.0.1'),
          updateClientProvider.overrideWithValue(
            FakeUpdateClient(
              release: const ReleaseInfo(
                tagName: 'v1.0.2',
                notes: '新增流式朗读与稳定性修复',
                htmlUrl: 'https://github.com/dstweihao/dst-echomind-app/releases/tag/v1.0.2',
              ),
            ),
          ),
        ],
        child: const EchoMindApp(),
      ),
    );

    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (tester.any(find.byKey(const Key('settings_update_dot')))) break;
    }

    expect(find.byKey(const Key('settings_update_dot')), findsOneWidget);
  });
}
