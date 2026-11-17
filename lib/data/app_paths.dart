/// 数据路径常量（相对于存储根目录的逻辑路径）
class AppPaths {
  AppPaths._();

  /// 应用数据根目录 —— 首次运行时自动创建
  static const String appRoot = '/EchoMind';

  static const String configFile = '$appRoot/config.yaml';

  /// 单一长期学习会话的工作记忆（近期压缩摘要 + 活跃窗口对话）
  static const String conversationFile = '$appRoot/conversation.json';

  /// 总知识沉淀清单（类别索引 + 一句话核心 + 详情路径）
  static const String knowledgeIndexFile = '$appRoot/KNOWLEDGE.md';

  /// 分类别/专题知识沉淀详情目录（`docs/<category_slug>.md`）
  static const String knowledgeDocsDir = '$appRoot/docs';

  /// 指定类别专题文档的逻辑路径
  static String knowledgeDocFile(String slug) => '$knowledgeDocsDir/$slug.md';
}
