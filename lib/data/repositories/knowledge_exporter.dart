import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'knowledge_repository.dart';

enum KnowledgeExportOutcome { saved, shared, cancelled, empty, failed }

class KnowledgeExportResult {
  final KnowledgeExportOutcome outcome;
  final String? filePath;
  final int fileCount;
  final String message;

  const KnowledgeExportResult({
    required this.outcome,
    this.filePath,
    this.fileCount = 0,
    this.message = '',
  });

  bool get isSuccess =>
      outcome == KnowledgeExportOutcome.saved ||
      outcome == KnowledgeExportOutcome.shared;
}

class ExportBundle {
  final String fileName;
  final Uint8List bytes;
  final int fileCount;

  const ExportBundle({
    required this.fileName,
    required this.bytes,
    required this.fileCount,
  });
}

/// 平台文件交付接口，便于测试注入 Fake 实现
abstract class ExportDeliveryAdapter {
  Future<KnowledgeExportResult> deliver({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    required String extension,
    required String subject,
    required int fileCount,
    Rect? shareOrigin,
  });
}

class NativeExportDeliveryAdapter implements ExportDeliveryAdapter {
  const NativeExportDeliveryAdapter();

  bool get _isDesktop => Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  @override
  Future<KnowledgeExportResult> deliver({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    required String extension,
    required String subject,
    required int fileCount,
    Rect? shareOrigin,
  }) async {
    try {
      if (_isDesktop) {
        final location = await getSaveLocation(
          suggestedName: fileName,
          acceptedTypeGroups: [
            XTypeGroup(
              label: extension.toUpperCase(),
              extensions: [extension],
            ),
          ],
        );
        if (location == null) {
          return const KnowledgeExportResult(
            outcome: KnowledgeExportOutcome.cancelled,
          );
        }
        final outPath = location.path.toLowerCase().endsWith('.$extension')
            ? location.path
            : '${location.path}.$extension';
        await File(outPath).writeAsBytes(bytes, flush: true);
        return KnowledgeExportResult(
          outcome: KnowledgeExportOutcome.saved,
          filePath: outPath,
          fileCount: fileCount,
          message: '已保存到 $outPath',
        );
      }

      // Android / iOS：写入临时目录并调起系统原生分享面板（可保存到文件 / 发送 / 导入其他应用）
      final tempDir = await getTemporaryDirectory();
      final outPath = p.join(tempDir.path, fileName);
      await File(outPath).writeAsBytes(bytes, flush: true);

      final shareResult = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(outPath, mimeType: mimeType, name: fileName)],
          subject: subject,
          sharePositionOrigin: shareOrigin,
        ),
      );

      if (shareResult.status == ShareResultStatus.dismissed) {
        return const KnowledgeExportResult(
          outcome: KnowledgeExportOutcome.cancelled,
        );
      }

      return KnowledgeExportResult(
        outcome: KnowledgeExportOutcome.shared,
        filePath: outPath,
        fileCount: fileCount,
        message: '已调起导出',
      );
    } catch (e) {
      return KnowledgeExportResult(
        outcome: KnowledgeExportOutcome.failed,
        message: '导出失败：$e',
      );
    }
  }
}

/// 知识库导出器：将 `KNOWLEDGE.md` 与全部 `docs/*.md` 打包为标准 ZIP，或导出单篇 Markdown。
class KnowledgeExporter {
  final ExportDeliveryAdapter delivery;

  const KnowledgeExporter({
    this.delivery = const NativeExportDeliveryAdapter(),
  });

  /// 将整个知识库打包为标准 UTF-8 ZIP 字节流（包含 `KNOWLEDGE.md` + `docs/*.md`）
  Future<ExportBundle?> buildKnowledgeZip(
    KnowledgeRepository repo, {
    DateTime? now,
  }) async {
    final indexMd = await repo.readIndexMarkdown();
    final docs = await repo.listDocs();

    final entries = <String, List<int>>{};
    final ts = _formatDateStamp(now ?? DateTime.now());
    final rootDir = 'EchoMind-Knowledge-$ts';

    if (indexMd.trim().isNotEmpty) {
      entries['$rootDir/KNOWLEDGE.md'] = utf8.encode('$indexMd\n');
    }

    for (final doc in docs) {
      final content = await repo.readDocMarkdown(doc.slug);
      if (content.trim().isEmpty) continue;
      entries['$rootDir/docs/${doc.slug}.md'] = utf8.encode('$content\n');
    }

    if (entries.isEmpty) return null;

    final zipBytes = buildZipBytes(entries);
    return ExportBundle(
      fileName: '$rootDir.zip',
      bytes: zipBytes,
      fileCount: entries.length,
    );
  }

  /// 导出整个知识库为 ZIP 压缩包
  Future<KnowledgeExportResult> exportAll(
    KnowledgeRepository repo, {
    Rect? shareOrigin,
    DateTime? now,
  }) async {
    final bundle = await buildKnowledgeZip(repo, now: now);
    if (bundle == null) {
      return const KnowledgeExportResult(
        outcome: KnowledgeExportOutcome.empty,
        message: '暂无可导出的知识库内容',
      );
    }

    return delivery.deliver(
      fileName: bundle.fileName,
      bytes: bundle.bytes,
      mimeType: 'application/zip',
      extension: 'zip',
      subject: '回响知识库导出（${bundle.fileCount} 个文件）',
      fileCount: bundle.fileCount,
      shareOrigin: shareOrigin,
    );
  }

  /// 导出单篇 Markdown 文档（`KNOWLEDGE.md` 或 `docs/<slug>.md`）
  Future<KnowledgeExportResult> exportMarkdown({
    required String fileName,
    required String markdown,
    Rect? shareOrigin,
  }) async {
    final content = markdown.trim();
    if (content.isEmpty) {
      return const KnowledgeExportResult(
        outcome: KnowledgeExportOutcome.empty,
        message: '当前文档暂无内容',
      );
    }

    final safeName = fileName.toLowerCase().endsWith('.md')
        ? fileName
        : '$fileName.md';

    return delivery.deliver(
      fileName: safeName,
      bytes: Uint8List.fromList(utf8.encode('$content\n')),
      mimeType: 'text/markdown',
      extension: 'md',
      subject: '回响笔记：$safeName',
      fileCount: 1,
      shareOrigin: shareOrigin,
    );
  }

  static String _formatDateStamp(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  /// 纯 Dart 标准 ZIP 打包（Deflate 压缩 + IEEE CRC32 + UTF-8 文件名标志）
  static Uint8List buildZipBytes(Map<String, List<int>> files) {
    final out = BytesBuilder(copy: false);
    final centralDir = BytesBuilder(copy: false);
    final deflate = ZLibCodec(raw: true);
    var entryCount = 0;

    for (final entry in files.entries) {
      final nameBytes = utf8.encode(entry.key);
      final rawBytes = entry.value;
      final compressedBytes = deflate.encode(rawBytes);
      final crc = _crc32(rawBytes);
      final localHeaderOffset = out.length;

      // Local File Header (30 bytes + filename)
      final localHeader = ByteData(30)
        ..setUint32(0, 0x04034b50, Endian.little) // signature
        ..setUint16(4, 20, Endian.little) // version needed: 2.0
        ..setUint16(6, 0x0800, Endian.little) // UTF-8 filename flag
        ..setUint16(8, 8, Endian.little) // compression: Deflate
        ..setUint16(10, 0, Endian.little) // mod time
        ..setUint16(12, 0, Endian.little) // mod date
        ..setUint32(14, crc, Endian.little)
        ..setUint32(18, compressedBytes.length, Endian.little)
        ..setUint32(22, rawBytes.length, Endian.little)
        ..setUint16(26, nameBytes.length, Endian.little)
        ..setUint16(28, 0, Endian.little); // extra len

      out.add(localHeader.buffer.asUint8List());
      out.add(nameBytes);
      out.add(compressedBytes);

      // Central Directory Header (46 bytes + filename)
      final cdHeader = ByteData(46)
        ..setUint32(0, 0x02014b50, Endian.little) // signature
        ..setUint16(4, 20, Endian.little) // version made by
        ..setUint16(6, 20, Endian.little) // version needed
        ..setUint16(8, 0x0800, Endian.little) // UTF-8 flag
        ..setUint16(10, 8, Endian.little) // compression: Deflate
        ..setUint16(12, 0, Endian.little)
        ..setUint16(14, 0, Endian.little)
        ..setUint32(16, crc, Endian.little)
        ..setUint32(20, compressedBytes.length, Endian.little)
        ..setUint32(24, rawBytes.length, Endian.little)
        ..setUint16(28, nameBytes.length, Endian.little)
        ..setUint16(30, 0, Endian.little) // extra len
        ..setUint16(32, 0, Endian.little) // comment len
        ..setUint16(34, 0, Endian.little) // disk start
        ..setUint16(36, 0, Endian.little) // internal attrs
        ..setUint32(38, 0, Endian.little) // external attrs
        ..setUint32(42, localHeaderOffset, Endian.little);

      centralDir.add(cdHeader.buffer.asUint8List());
      centralDir.add(nameBytes);
      entryCount++;
    }

    final cdOffset = out.length;
    final cdBytes = centralDir.toBytes();
    out.add(cdBytes);

    // End of Central Directory Record (22 bytes)
    final eocd = ByteData(22)
      ..setUint32(0, 0x06054b50, Endian.little)
      ..setUint16(4, 0, Endian.little)
      ..setUint16(6, 0, Endian.little)
      ..setUint16(8, entryCount, Endian.little)
      ..setUint16(10, entryCount, Endian.little)
      ..setUint32(12, cdBytes.length, Endian.little)
      ..setUint32(16, cdOffset, Endian.little)
      ..setUint16(20, 0, Endian.little);

    out.add(eocd.buffer.asUint8List());
    return out.toBytes();
  }

  static final List<int> _crcTable = _buildCrcTable();

  static List<int> _buildCrcTable() {
    final table = List<int>.filled(256, 0);
    for (var i = 0; i < 256; i++) {
      var c = i;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
      }
      table[i] = c;
    }
    return table;
  }

  static int _crc32(List<int> data) {
    var crc = 0xffffffff;
    for (final b in data) {
      crc = _crcTable[(crc ^ b) & 0xff] ^ (crc >>> 8);
    }
    return (crc ^ 0xffffffff) & 0xffffffff;
  }
}
