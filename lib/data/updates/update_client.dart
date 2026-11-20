import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/update_info.dart';
import 'update_config.dart';

class UpdateException implements Exception {
  final String message;

  const UpdateException(this.message);

  @override
  String toString() => 'UpdateException($message)';
}

/// GitHub Releases 检查器
class UpdateClient {
  final http.Client _http;
  final bool _ownsClient;

  UpdateClient({http.Client? httpClient})
      : _http = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  /// 返回最新正式版；仓库还没有正式 release（只有预发布或不曾发布）时为 null。
  /// 内置多线路轮询（官方 API + 国内镜像反代兜底），在大陆网络环境下有效防超时。
  Future<ReleaseInfo?> checkLatest() async {
    final urls = UpdateConfig.checkUpdateUrls;
    Object? lastError;

    for (var i = 0; i < urls.length; i++) {
      final url = urls[i];
      final isLast = i == urls.length - 1;
      final uri = Uri.parse(url);

      http.Response response;
      try {
        response = await _http.get(
          uri,
          headers: const {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'EchoMind-App',
          },
        ).timeout(UpdateConfig.checkTimeout);
      } on TimeoutException catch (e) {
        lastError = e;
        if (isLast) {
          throw const UpdateException('连接 GitHub 超时，请检查网络');
        }
        continue;
      } on http.ClientException catch (e) {
        lastError = e;
        if (isLast) {
          throw const UpdateException('网络不可达，无法检查更新');
        }
        continue;
      } catch (e) {
        lastError = e;
        if (isLast) {
          throw UpdateException('检查更新失败：$e');
        }
        continue;
      }

      switch (response.statusCode) {
        case 200:
          return _parse(response.bodyBytes);
        // 尚无正式发布 —— 对用户而言等同于「已是最新」
        case 404:
          return null;
        case 403:
        case 429:
          if (isLast) {
            throw const UpdateException('检查过于频繁，请稍后再试');
          }
          continue;
        default:
          if (isLast) {
            throw UpdateException('检查失败（HTTP ${response.statusCode}）');
          }
          continue;
      }
    }

    if (lastError is UpdateException) throw lastError;
    throw const UpdateException('无法连接更新服务器，请稍后重试');
  }

  ReleaseInfo _parse(List<int> bodyBytes) {
    try {
      // 自己按 UTF-8 解 —— 发布说明是中文，不能指望响应头一定带 charset
      final map = jsonDecode(utf8.decode(bodyBytes)) as Map<String, dynamic>;
      final assets = (map['assets'] as List? ?? const [])
          .whereType<Map>()
          .map((a) => ReleaseAsset(
                name: (a['name'] ?? '') as String,
                browserDownloadUrl: (a['browser_download_url'] ?? '') as String,
                size: (a['size'] as num?)?.toInt() ?? 0,
              ))
          .where((a) => a.browserDownloadUrl.isNotEmpty)
          .toList();

      return ReleaseInfo(
        tagName: (map['tag_name'] ?? '') as String,
        name: (map['name'] ?? '') as String,
        notes: (map['body'] ?? '') as String,
        htmlUrl: (map['html_url'] ?? '') as String,
        isPrerelease: map['prerelease'] == true,
        assets: assets,
      );
    } catch (_) {
      throw const UpdateException('无法解析 GitHub 返回的内容');
    }
  }

  void close() {
    if (_ownsClient) _http.close();
  }
}
