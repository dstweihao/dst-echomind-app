import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'file_store.dart';
import 'local_file_store.dart';

/// 桌面 / 移动端：支持用户自选文件夹
const bool supportsCustomFolder = true;

/// 按根目录同步创建本地存储
FileStore createFileStore(String rootPath) => LocalFileStore(rootPath);

/// 默认数据文件夹：「文档/EchoMind」
Future<String> defaultRootPath() async {
  final docs = await getApplicationDocumentsDirectory();
  return p.join(docs.path, 'EchoMind');
}
