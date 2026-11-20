import 'dart:async';
import 'dart:io';

import 'package:echomind_app/data/updates/update_client.dart';
import 'package:echomind_app/data/updates/update_config.dart';
import 'package:echomind_app/data/updates/update_installer_io.dart';
import 'package:echomind_app/domain/models/update_info.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// LinkDelegate 没被主库重新导出，单独引
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _MockHttpClient extends Mock implements http.Client {}

/// 临时目录是插件通道给的，测试里换成一颗真·临时目录
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);

  final String path;

  @override
  Future<String?> getTemporaryPath() async => path;
}

class _FakeUrlLauncher extends UrlLauncherPlatform {
  final List<String> launched = [];
  bool result = true;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return result;
  }
}

const _downloadUrl = 'https://example.com/download/asset';

/// 三个桌面平台的安装包都给全，这样断言与跑测试的机器无关
ReleaseInfo _desktopRelease() => const ReleaseInfo(
      tagName: 'v1.2.0',
      htmlUrl: 'https://example.com/releases/v1.2.0',
      assets: [
        ReleaseAsset(
            name: 'AbsoluteMoment-1.2.0.exe', browserDownloadUrl: _downloadUrl),
        ReleaseAsset(
            name: 'AbsoluteMoment-1.2.0.dmg', browserDownloadUrl: _downloadUrl),
        ReleaseAsset(
            name: 'AbsoluteMoment-1.2.0.AppImage',
            browserDownloadUrl: _downloadUrl),
      ],
    );

const _candidateNames = {
  'AbsoluteMoment-1.2.0.exe',
  'AbsoluteMoment-1.2.0.dmg',
  'AbsoluteMoment-1.2.0.AppImage',
};

void main() {
  late _MockHttpClient httpClient;
  late _FakeUrlLauncher launcher;
  late Directory tempDir;

  setUpAll(() {
    registerFallbackValue(http.Request('GET', Uri()));
    registerFallbackValue(Uri());
  });

  setUp(() {
    httpClient = _MockHttpClient();
    launcher = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = launcher;

    tempDir = Directory.systemTemp.createTempSync('am_update_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  void stubStream(
    int statusCode, {
    List<List<int>> chunks = const [],
    int? contentLength,
  }) {
    when(() => httpClient.send(any())).thenAnswer(
      (_) async => http.StreamedResponse(
        Stream.fromIterable(chunks),
        statusCode,
        contentLength: contentLength,
      ),
    );
  }

  List<File> writtenFiles() =>
      tempDir.listSync().whereType<File>().toList(growable: false);

  test('下载安装包：边收边写盘，进度一路涨到 100%', () async {
    stubStream(
      200,
      chunks: [
        List.filled(4, 0x41),
        List.filled(6, 0x42),
      ],
      contentLength: 10,
    );

    final progress = <double?>[];
    final bytesLog = <(int, int?)>[];
    final result = await installUpdate(
      _desktopRelease(),
      httpClient: httpClient,
      onProgress: progress.add,
      onBytesProgress: (r, t) => bytesLog.add((r, t)),
    );

    expect(result.outcome, InstallOutcome.launched);
    expect(result.isSuccess, true);
    expect(progress, [0.4, 1.0], reason: '进度按已收字节算，不是按块数');
    expect(bytesLog, [(4, 10), (10, 10)]);

    final files = writtenFiles();
    expect(files, hasLength(1));
    expect(_candidateNames, contains(files.single.uri.pathSegments.last),
        reason: '文件名取自附件名，且只留 basename');
    expect(files.single.lengthSync(), 10, reason: '字节数要和流一致');
  });

  test('安装包没有 Content-Length：进度给 null，不假装知道总量', () async {
    stubStream(200, chunks: [
      List.filled(3, 1),
    ]);

    final progress = <double?>[];
    await installUpdate(
      _desktopRelease(),
      httpClient: httpClient,
      onProgress: progress.add,
    );

    expect(progress, [null]);
  });

  test('下载不是 200：报错，不留下半截文件', () async {
    stubStream(404);

    final result = await installUpdate(
      _desktopRelease(),
      httpClient: httpClient,
    );

    expect(result.outcome, InstallOutcome.failed);
    expect(result.message, contains('404'));
    expect(writtenFiles(), isEmpty,
        reason: '状态码不对时连临时文件都不该创建');
  });

  test('下载超时与网络中断各自映射成可读提示', () async {
    when(() => httpClient.send(any())).thenThrow(TimeoutException('slow'));
    var result =
        await installUpdate(_desktopRelease(), httpClient: httpClient);
    expect(result.message, contains('下载超时'));

    when(() => httpClient.send(any()))
        .thenThrow(http.ClientException('boom'));
    result = await installUpdate(_desktopRelease(), httpClient: httpClient);
    expect(result.message, contains('网络中断'));
  });

  test('系统打不开下载好的安装包：算失败并说清楚', () async {
    stubStream(200, chunks: [
      List.filled(1, 0),
    ], contentLength: 1);
    launcher.result = false;

    final result =
        await installUpdate(_desktopRelease(), httpClient: httpClient);

    expect(result.outcome, InstallOutcome.failed);
    expect(result.message, contains('没能打开'));
  });

  test('这个版本没有本平台的安装包：退回到 Release 页', () async {
    const release = ReleaseInfo(
      tagName: 'v1.2.0',
      htmlUrl: 'https://example.com/releases/v1.2.0',
      assets: [
        ReleaseAsset(
            name: 'readme.txt', browserDownloadUrl: 'https://example.com/a.txt'),
      ],
    );

    final result = await installUpdate(release, httpClient: httpClient);

    expect(result.outcome, InstallOutcome.openedInBrowser);
    expect(launcher.launched, [release.htmlUrl]);
    expect(writtenFiles(), isEmpty);
    verifyNever(() => httpClient.send(any()));
  });

  test('Release 仅提供 Windows 的 .zip 附件时，非 Windows 平台绝不误下，安全退回到 Release 页', () async {
    const windowsOnlyRelease = ReleaseInfo(
      tagName: 'v1.0.6',
      htmlUrl: 'https://example.com/releases/v1.0.6',
      assets: [
        ReleaseAsset(
          name: 'EchoMind-v1.0.6-windows-x64.zip',
          browserDownloadUrl: 'https://example.com/download/EchoMind-v1.0.6-windows-x64.zip',
        ),
      ],
    );

    if (!Platform.isWindows) {
      final result = await installUpdate(windowsOnlyRelease, httpClient: httpClient);
      expect(result.outcome, InstallOutcome.openedInBrowser);
      expect(launcher.launched, [windowsOnlyRelease.htmlUrl]);
      expect(writtenFiles(), isEmpty);
      verifyNever(() => httpClient.send(any()));
    }
  });

  group('openReleasePage', () {
    test('成功时报告已送到浏览器，且用外部程序打开', () async {
      final result = await openReleasePage('https://example.com/releases');

      expect(result.outcome, InstallOutcome.openedInBrowser);
      expect(launcher.launched, ['https://example.com/releases']);
    });

    test('没有下载页链接时不当成「已打开」', () async {
      final result = await openReleasePage('');

      expect(result.outcome, InstallOutcome.failed);
      expect(launcher.launched, isEmpty);
    });

    test('浏览器拒绝打开：算失败', () async {
      launcher.result = false;

      final result = await openReleasePage('https://example.com/releases');

      expect(result.outcome, InstallOutcome.failed);
      expect(result.message, contains('无法打开'));
    });
  });

  test('Android 平台规则能正确匹配 .apk 附件，且已有同大小缓存文件时不重复下载', () async {
    const apkRelease = ReleaseInfo(
      tagName: 'v1.0.3',
      assets: [
        ReleaseAsset(
          name: 'EchoMind-v1.0.3-macos.dmg',
          browserDownloadUrl: _downloadUrl,
          size: 100,
        ),
        ReleaseAsset(
          name: 'EchoMind-v1.0.3-android.apk',
          browserDownloadUrl: _downloadUrl,
          size: 200,
        ),
      ],
    );
    final picked = selectInstallerAsset(apkRelease, UpdateConfig.androidAssetExts);
    expect(picked?.name, 'EchoMind-v1.0.3-android.apk');

    // 验证桌面端命中缓存时直接复用文件，不再发起 HTTP 请求
    final cachedRelease = ReleaseInfo(
      tagName: 'v1.2.0',
      assets: [
        ReleaseAsset(
          name: 'AbsoluteMoment-1.2.0.dmg',
          browserDownloadUrl: _downloadUrl,
          size: 8,
        ),
        ReleaseAsset(
          name: 'AbsoluteMoment-1.2.0.exe',
          browserDownloadUrl: _downloadUrl,
          size: 8,
        ),
        ReleaseAsset(
          name: 'AbsoluteMoment-1.2.0.AppImage',
          browserDownloadUrl: _downloadUrl,
          size: 8,
        ),
      ],
    );
    final targetName = Platform.isMacOS
        ? 'AbsoluteMoment-1.2.0.dmg'
        : Platform.isWindows
            ? 'AbsoluteMoment-1.2.0.exe'
            : 'AbsoluteMoment-1.2.0.AppImage';
    File('${tempDir.path}/$targetName').writeAsBytesSync(List.filled(8, 0x55));

    final progress = <double?>[];
    final result = await installUpdate(
      cachedRelease,
      httpClient: httpClient,
      onProgress: progress.add,
    );
    expect(result.outcome, InstallOutcome.launched);
    expect(progress, [1.0]);
    verifyNever(() => httpClient.send(any()));
  });

  test('UpdateConfig.getDownloadCandidateUrls 为 GitHub 链接自动注入国内 CDN 镜像加速前缀', () {
    const rawGithubUrl =
        'https://github.com/dstweihao/dst-echomind-app/releases/download/v1.0.7/EchoMind-v1.0.7-macos.dmg';
    final candidates = UpdateConfig.getDownloadCandidateUrls(rawGithubUrl);

    expect(candidates, hasLength(UpdateConfig.downloadMirrorPrefixes.length + 1));
    expect(candidates.first, 'https://gh-proxy.com/$rawGithubUrl');
    expect(candidates[1], 'https://ghproxy.net/$rawGithubUrl');
    expect(candidates.last, rawGithubUrl);

    // 非 GitHub 链接原样返回，不增加镜像前缀
    const otherUrl = 'https://my-bucket.cos.ap-beijing.myqcloud.com/app.dmg';
    expect(UpdateConfig.getDownloadCandidateUrls(otherUrl), [otherUrl]);
    expect(UpdateConfig.getDownloadCandidateUrls(''), isEmpty);
  });

  test('下载安装包：首选镜像失败（502）时无缝自动回退到备用镜像并成功完成下载', () async {
    const githubUrl =
        'https://github.com/dstweihao/dst-echomind-app/releases/download/v1.2.0/AbsoluteMoment-1.2.0.dmg';
    final releaseWithGithubUrl = ReleaseInfo(
      tagName: 'v1.2.0',
      htmlUrl: 'https://github.com/dstweihao/dst-echomind-app/releases/tag/v1.2.0',
      assets: [
        ReleaseAsset(
          name: Platform.isMacOS
              ? 'AbsoluteMoment-1.2.0.dmg'
              : Platform.isWindows
                  ? 'AbsoluteMoment-1.2.0.exe'
                  : 'AbsoluteMoment-1.2.0.AppImage',
          browserDownloadUrl: githubUrl,
          size: 6,
        ),
      ],
    );

    // 第一次调用（gh-proxy.com 镜像）：返回 502
    // 第二次调用（ghproxy.net 镜像）：返回 200 并传输 6 字节数据
    var callCount = 0;
    when(() => httpClient.send(any())).thenAnswer((invocation) async {
      callCount++;
      final req = invocation.positionalArguments.first as http.BaseRequest;
      if (callCount == 1) {
        expect(req.url.toString(), contains('gh-proxy.com'));
        return http.StreamedResponse(const Stream.empty(), 502);
      }
      expect(req.url.toString(), contains('ghproxy.net'));
      return http.StreamedResponse(
        Stream.fromIterable([
          [1, 2, 3],
          [4, 5, 6],
        ]),
        200,
        contentLength: 6,
      );
    });

    final progress = <double?>[];
    final result = await installUpdate(
      releaseWithGithubUrl,
      httpClient: httpClient,
      onProgress: progress.add,
    );

    expect(result.outcome, InstallOutcome.launched);
    expect(result.isSuccess, true);
    expect(callCount, 2, reason: '第一路镜像挂掉后自动无缝切换到第二路镜像');
    expect(progress, [0.5, 1.0]);
  });

  test('UpdateClient 检查更新：官方 API 超时时无缝回退到国内镜像 API 完成解析', () async {
    final client = UpdateClient(httpClient: httpClient);

    var callCount = 0;
    when(() => httpClient.get(any(), headers: any(named: 'headers')))
        .thenAnswer((invocation) async {
      callCount++;
      final url = invocation.positionalArguments.first.toString();
      if (callCount == 1) {
        // 第一路官方端点模拟超时
        expect(url, UpdateConfig.latestReleaseUrl);
        throw TimeoutException('api.github.com timeout');
      }
      // 第二路镜像端点模拟成功响应
      expect(url, contains('gh-proxy.com'));
      return http.Response(
        '{"tag_name": "v1.0.8", "name": "v1.0.8", "body": "fix", "html_url": "https://github.com/dstweihao/dst-echomind-app/releases/tag/v1.0.8", "assets": []}',
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    final release = await client.checkLatest();
    expect(release, isNotNull);
    expect(release!.tagName, 'v1.0.8');
    expect(callCount, 2, reason: '官方 API 超时后触发镜像反代轮询');
  });
}
