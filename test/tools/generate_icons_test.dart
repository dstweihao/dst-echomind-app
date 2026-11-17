import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('品牌图标母版文件存在且为合法 PNG', () {
    for (final path in const [
      'assets/icon/icon.png',
      'assets/icon/icon_foreground.png',
    ]) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '缺少图标母版：$path');
      final bytes = file.readAsBytesSync();
      expect(bytes.length, greaterThan(1024), reason: '图标母版内容异常：$path');
      // 验证 PNG 魔数 89 50 4E 47
      expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    }
  });
}
