import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'providers.dart';
import 'router.dart';

/// 应用根 Widget
class EchoMindApp extends ConsumerStatefulWidget {
  const EchoMindApp({super.key});

  @override
  ConsumerState<EchoMindApp> createState() => _EchoMindAppState();
}

class _EchoMindAppState extends ConsumerState<EchoMindApp> {
  late final GoRouter _router = AppRouter.build(initialLocation: AppRouter.learn);

  @override
  void initState() {
    super.initState();
    // 启动后静默查一次新版本：结果只进常驻 notifier，不弹窗、不阻断启动。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(updateStatusProvider.notifier).check();
    });
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(themeModeProvider);

    final brightness = switch (mode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => MediaQuery.platformBrightnessOf(context),
    };
    final dark = brightness == Brightness.dark;

    AppColors.current = dark ? AppPalette.dark : AppPalette.light;

    return MaterialApp.router(
      key: ValueKey(dark),
      title: AppIdentity.appName,
      debugShowCheckedModeBanner: false,
      scrollBehavior: const MaterialScrollBehavior().copyWith(scrollbars: false),
      theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
      routerConfig: _router,
    );
  }
}
