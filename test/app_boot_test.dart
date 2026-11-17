import 'package:echomind_app/app.dart';
import 'package:echomind_app/data/storage/memory_file_store.dart';
import 'package:echomind_app/features/learn/learn_page.dart';
import 'package:echomind_app/providers.dart';
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
}
