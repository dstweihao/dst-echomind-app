import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'features/ai_settings/ai_settings_page.dart';
import 'features/learn/learn_page.dart';

/// 全局路由表：首屏直达学习主界面（`/learn`），右上角进入设置（`/settings/ai`）。
class AppRouter {
  AppRouter._();

  static const String learn = '/learn';
  static const String aiSettings = '/settings/ai';

  static final GlobalKey<NavigatorState> _rootKey =
      GlobalKey<NavigatorState>(debugLabel: 'root');

  static GoRouter build({String initialLocation = learn}) {
    return GoRouter(
      navigatorKey: _rootKey,
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: learn,
          builder: (context, state) => const LearnPage(),
        ),
        GoRoute(
          path: aiSettings,
          builder: (context, state) => const AiSettingsPage(),
        ),
      ],
      errorBuilder: (context, state) => Scaffold(
        appBar: AppBar(title: const Text('页面不存在')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('找不到该页面'),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => context.go(learn),
                child: const Text('回到学习'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
