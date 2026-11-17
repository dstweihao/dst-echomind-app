import 'package:flutter/material.dart';

/// 「回响 (EchoMind)」品牌图标 —— 叠层光焰（Layered Knowledge Spark）
///
/// 优先渲染高清位图母版 `assets/icon/icon.png`，并裁切为 Apple HIG 圆角方块；
/// 在无资源环境的极简测试中自动降级为柔和矢量渐变占位。
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.size = 96,
    this.background = false,
    this.glyphScale = 1.0,
  });

  /// 画布边长
  final double size;

  /// 是否铺满方形底色（保留兼容参数）
  final bool background;

  /// 缩放比例（保留兼容参数）
  final double glyphScale;

  @override
  Widget build(BuildContext context) {
    final radius = background ? 0.0 : size * 0.22;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.asset(
        'assets/icon/icon.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, _, _) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2563EB), Color(0xFF4F46E5)],
            ),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.layers_rounded,
            size: size * 0.54,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
