/// 版本更新的全部常量 —— 换仓库只改这一个文件
class UpdateConfig {
  UpdateConfig._();

  static const String gitHubOwner = 'dstweihao';
  static const String gitHubRepo = 'dst-echomind-app';

  static const String apiBase = 'https://api.github.com';

  static String get latestReleaseUrl =>
      '$apiBase/repos/$gitHubOwner/$gitHubRepo/releases/latest';

  /// 检查更新候选 API 端点列表（官方直连 + 国内镜像反代兜底）
  static List<String> get checkUpdateUrls => [
        latestReleaseUrl,
        'https://gh-proxy.com/$latestReleaseUrl',
      ];

  /// 国内 CDN 镜像加速前缀列表（按优先级尝试）
  /// 若首选镜像不可用或网络异常，按顺序自动回退至下一个镜像，最终回退至 GitHub 原地址。
  static const List<String> downloadMirrorPrefixes = [
    'https://gh-proxy.com/',
    'https://ghproxy.net/',
  ];

  /// 为下载链接生成候选下载地址（优先国内 CDN 镜像加速，按序回退至 GitHub 官方原地址）
  static List<String> getDownloadCandidateUrls(String originalUrl) {
    final trimmed = originalUrl.trim();
    if (trimmed.isEmpty) return const [];
    if (!trimmed.contains('github.com')) {
      return [trimmed];
    }
    return [
      for (final prefix in downloadMirrorPrefixes)
        '$prefix$trimmed',
      trimmed,
    ];
  }

  static const Duration checkTimeout = Duration(seconds: 10);
  static const Duration downloadTimeout = Duration(minutes: 20);

  /// 安装包扩展名优先级（小写；匹配时忽略大小写）。
  /// `.zip` 一律垫底 —— 它不是安装程序，只能打开压缩包。
  static const List<String> windowsAssetExts = ['.exe', '.msi', '.zip'];
  static const List<String> macosAssetExts = ['.dmg', '.pkg', '.zip'];
  static const List<String> androidAssetExts = ['.apk'];
  static const List<String> linuxAssetExts = [
    '.appimage',
    '.deb',
    '.rpm',
    '.tar.gz',
  ];

  /// Web 读不到版本、Windows debug 偶发陈旧 —— 用它兜底（与 pubspec 保持一致）
  static const String fallbackVersion = '1.0.9';
}
