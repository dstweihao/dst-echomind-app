import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/models/update_info.dart';
import 'update_client.dart';
import 'update_config.dart';

const MethodChannel _androidUpdaterChannel =
    MethodChannel('com.dstweihao.echomind/updater');

/// 选出当前平台对应的安装包附件（桌面端与 Android 均可直接应用内下载）
ReleaseAsset? selectCurrentPlatformAsset(ReleaseInfo release) =>
    selectInstallerAsset(
      release,
      _platformAssetExts(),
      disallowedKeywords: _disallowedPlatformKeywords(),
    );

/// 应用内下载当前平台的安装包并直接拉起系统安装程序（Android / macOS / Windows）。
///
/// [onProgress] 收到 0..1；安装包没有 `Content-Length` 时收到 null（不确定进度）。
/// [onBytesProgress] 可选回调已下载字节数与总字节数，用于展示 MB 进度。
Future<InstallResult> installUpdate(
  ReleaseInfo release, {
  http.Client? httpClient,
  void Function(double? progress)? onProgress,
  void Function(int receivedBytes, int? totalBytes)? onBytesProgress,
}) async {
  final asset = selectInstallerAsset(
    release,
    _platformAssetExts(),
    disallowedKeywords: _disallowedPlatformKeywords(),
  );
  if (asset == null) return _openReleasePage(release.htmlUrl);

  final client = httpClient ?? http.Client();
  try {
    final path = await _downloadToTemp(
      client,
      asset,
      onProgress: onProgress,
      onBytesProgress: onBytesProgress,
    );

    // Android：通过原生 FileProvider + PackageInstaller 直接调起系统安装页
    if (Platform.isAndroid) {
      return await _installAndroidApk(path);
    }

    // AppImage 没有执行位就是一块死文件，launchUrl 会静默失败
    if (Platform.isLinux && asset.name.toLowerCase().endsWith('.appimage')) {
      await Process.run('chmod', ['+x', path]);
    }

    final launched = await launchUrl(
      Uri.file(path),
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      return const InstallResult(
        InstallOutcome.failed,
        message: '安装包已下载，但系统没能打开它',
      );
    }

    final hint = Platform.isMacOS
        ? '将「回响」拖入「应用程序」即可覆盖更新'
        : Platform.isWindows
            ? '解压并覆盖原目录即可完成更新'
            : '按提示安装完成后请重启应用';
    return InstallResult(InstallOutcome.launched, message: hint);
  } on UpdateException catch (e) {
    return InstallResult(InstallOutcome.failed, message: e.message);
  } on Object catch (e) {
    return InstallResult(InstallOutcome.failed, message: '更新失败：$e');
  } finally {
    if (httpClient == null) client.close();
  }
}

Future<InstallResult> _installAndroidApk(String path) async {
  try {
    final status = await _androidUpdaterChannel.invokeMethod<String>(
      'installApk',
      {'path': path},
    );
    if (status == 'needs_permission') {
      return const InstallResult(
        InstallOutcome.needsPermission,
        message: '安装包已下载完成。请在系统设置中开启「允许安装未知应用」，返回后点击「立即安装」即可',
      );
    }
    if (status == 'launched') {
      return const InstallResult(
        InstallOutcome.launched,
        message: '已调起系统安装页面，请按提示完成更新',
      );
    }
    return const InstallResult(
      InstallOutcome.failed,
      message: '安装包已下载，但系统没能打开它',
    );
  } on PlatformException catch (e) {
    return InstallResult(
      InstallOutcome.failed,
      message: e.message ?? '无法启动系统安装程序',
    );
  }
}

/// 直接把人送到下载链接或 Release 页（仅在应用内下载失败后的兜底选项使用）
Future<InstallResult> openReleasePage(String htmlUrl) async {
  if (htmlUrl.isEmpty) {
    return const InstallResult(
      InstallOutcome.failed,
      message: '这个版本没有提供下载页',
    );
  }
  final opened = await launchUrl(
    Uri.parse(htmlUrl),
    mode: LaunchMode.externalApplication,
  );
  return opened
      ? const InstallResult(InstallOutcome.openedInBrowser)
      : const InstallResult(
          InstallOutcome.failed,
          message: '无法打开下载页面',
        );
}

Future<InstallResult> _openReleasePage(String htmlUrl) async {
  final result = await openReleasePage(htmlUrl);
  return result.outcome == InstallOutcome.failed
      ? const InstallResult(
          InstallOutcome.failed,
          message: '这个版本没有提供安装包',
        )
      : result;
}

/// 按平台返回对应的安装包扩展名优先级。iOS 受系统限制走外部页，其余均支持应用内直下。
List<String> _platformAssetExts() {
  if (Platform.isAndroid) return UpdateConfig.androidAssetExts;
  if (Platform.isWindows) return UpdateConfig.windowsAssetExts;
  if (Platform.isMacOS) return UpdateConfig.macosAssetExts;
  if (Platform.isLinux) return UpdateConfig.linuxAssetExts;
  return const [];
}

/// 冲突平台关键词拦截，严防跨平台通用扩展名（如 `.zip`）误下其它平台的安装包。
List<String> _disallowedPlatformKeywords() {
  if (Platform.isMacOS) return const ['win', 'windows', 'linux', 'android'];
  if (Platform.isWindows) return const ['macos', 'darwin', 'mac', 'linux', 'android'];
  if (Platform.isLinux) return const ['win', 'windows', 'macos', 'darwin', 'mac', 'android'];
  if (Platform.isAndroid) return const ['win', 'windows', 'macos', 'darwin', 'mac', 'linux'];
  return const [];
}

Future<String> _downloadToTemp(
  http.Client client,
  ReleaseAsset asset, {
  void Function(double? progress)? onProgress,
  void Function(int receivedBytes, int? totalBytes)? onBytesProgress,
}) async {
  final dir = await getTemporaryDirectory();
  final finalFile = File(p.join(dir.path, p.basename(asset.name)));

  // 若完整安装包已缓存（如 Android 授权「允许未知来源」后返回点安装），直接复用避免重复下载
  if (asset.size > 0 &&
      finalFile.existsSync() &&
      finalFile.lengthSync() == asset.size) {
    onProgress?.call(1.0);
    onBytesProgress?.call(asset.size, asset.size);
    return finalFile.path;
  }

  // 必须流式写盘：安装包动辄几十 MB，整体缓冲会 OOM。
  // 同时 GitHub 的 download 链接是跨域 302，交给 client 自己跟。
  final request = http.Request('GET', Uri.parse(asset.browserDownloadUrl))
    ..followRedirects = true
    ..maxRedirects = 5;

  final http.StreamedResponse response;
  try {
    response = await client.send(request).timeout(UpdateConfig.downloadTimeout);
  } on TimeoutException {
    throw const UpdateException('下载超时，请检查网络后重试');
  } on http.ClientException {
    throw const UpdateException('网络中断，下载失败');
  }

  if (response.statusCode != 200) {
    await response.stream.drain<void>();
    throw UpdateException('下载失败（HTTP ${response.statusCode}）');
  }

  final partFile = File('${finalFile.path}.part');
  final sink = partFile.openWrite();
  final rawTotal = response.contentLength;
  final total = (rawTotal != null && rawTotal > 0)
      ? rawTotal
      : (asset.size > 0 ? asset.size : null);
  var received = 0;
  var completed = false;

  try {
    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      onProgress?.call(
        total == null ? null : (received / total).clamp(0.0, 1.0),
      );
      onBytesProgress?.call(received, total);
    }
    await sink.flush();
    completed = true;
  } on TimeoutException {
    throw const UpdateException('下载超时，请检查网络后重试');
  } on http.ClientException {
    throw const UpdateException('网络中断，下载失败');
  } finally {
    await sink.close();
    if (!completed && partFile.existsSync()) {
      try {
        await partFile.delete();
      } catch (_) {}
    }
  }

  if (finalFile.existsSync()) {
    await finalFile.delete();
  }
  await partFile.rename(finalFile.path);
  return finalFile.path;
}
