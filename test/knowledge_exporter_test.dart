import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:echomind_app/data/repositories/knowledge_exporter.dart';
import 'package:echomind_app/data/repositories/knowledge_repository.dart';
import 'package:echomind_app/data/storage/memory_file_store.dart';
import 'package:echomind_app/domain/models/knowledge_models.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDeliveryAdapter implements ExportDeliveryAdapter {
  String? lastFileName;
  Uint8List? lastBytes;
  String? lastMimeType;
  int lastFileCount = 0;

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
    lastFileName = fileName;
    lastBytes = bytes;
    lastMimeType = mimeType;
    lastFileCount = fileCount;
    return KnowledgeExportResult(
      outcome: KnowledgeExportOutcome.saved,
      filePath: '/tmp/$fileName',
      fileCount: fileCount,
      message: 'ok',
    );
  }
}

/// 简易标准 ZIP 解析器（验证 Local File Header + Deflate 解压后原文无损）
Map<String, String> _decodeZipUtf8(Uint8List bytes) {
  final bd = ByteData.sublistView(bytes);
  final inflater = ZLibCodec(raw: true);
  final out = <String, String>{};
  var offset = 0;
  while (offset + 30 <= bytes.length) {
    final sig = bd.getUint32(offset, Endian.little);
    if (sig != 0x04034b50) break;
    final compSize = bd.getUint32(offset + 18, Endian.little);
    final nameLen = bd.getUint16(offset + 26, Endian.little);
    final extraLen = bd.getUint16(offset + 28, Endian.little);
    final nameStart = offset + 30;
    final name = utf8.decode(bytes.sublist(nameStart, nameStart + nameLen));
    final dataStart = nameStart + nameLen + extraLen;
    final compressed = bytes.sublist(dataStart, dataStart + compSize);
    final raw = inflater.decode(compressed);
    out[name] = utf8.decode(raw);
    offset = dataStart + compSize;
  }
  return out;
}

void main() {
  test('buildKnowledgeZip 打包 KNOWLEDGE.md 与 docs/*.md 为可解压的标准 ZIP', () async {
    final repo = KnowledgeRepository(MemoryFileStore());
    await repo.appendEntries([
      KnowledgeEntry(
        categorySlug: 'economics',
        categoryName: '经济学',
        topic: '通货膨胀',
        oneLiner: '币增货不变 → 购买力降',
        analogy: '10苹果配100元→配200元',
        misconception: '误: 单品涨价 → 实: 货币贬值',
        feynmanNote: '钱毛了',
        createdAt: DateTime(2026, 11, 18),
      ),
      KnowledgeEntry(
        categorySlug: 'programming',
        categoryName: '编程',
        topic: '递归',
        oneLiner: '自调用 + 基准出口 → 问题拆小',
        createdAt: DateTime(2026, 11, 18),
      ),
    ]);

    final delivery = _FakeDeliveryAdapter();
    final exporter = KnowledgeExporter(delivery: delivery);
    final res = await exporter.exportAll(repo, now: DateTime(2026, 11, 18));

    expect(res.outcome, KnowledgeExportOutcome.saved);
    expect(res.fileCount, 3);
    expect(delivery.lastFileName, 'EchoMind-Knowledge-20261118.zip');
    expect(delivery.lastMimeType, 'application/zip');

    final files = _decodeZipUtf8(delivery.lastBytes!);
    expect(
      files.keys,
      containsAll([
        'EchoMind-Knowledge-20261118/KNOWLEDGE.md',
        'EchoMind-Knowledge-20261118/docs/economics.md',
        'EchoMind-Knowledge-20261118/docs/programming.md',
      ]),
    );
    expect(
      files['EchoMind-Knowledge-20261118/docs/economics.md'],
      contains('通货膨胀'),
    );
    expect(
      files['EchoMind-Knowledge-20261118/KNOWLEDGE.md'],
      contains('经济学'),
    );
  });

  test('知识库为空时返回 empty，不触发交付', () async {
    final repo = KnowledgeRepository(MemoryFileStore());
    final delivery = _FakeDeliveryAdapter();
    final exporter = KnowledgeExporter(delivery: delivery);

    final res = await exporter.exportAll(repo);
    expect(res.outcome, KnowledgeExportOutcome.empty);
    expect(delivery.lastFileName, isNull);
  });

  test('exportMarkdown 支持单篇导出并补全 .md 后缀', () async {
    final delivery = _FakeDeliveryAdapter();
    final exporter = KnowledgeExporter(delivery: delivery);

    final res = await exporter.exportMarkdown(
      fileName: 'economics',
      markdown: '# 经济学\n\n## 通货膨胀',
    );
    expect(res.outcome, KnowledgeExportOutcome.saved);
    expect(delivery.lastFileName, 'economics.md');
    expect(utf8.decode(delivery.lastBytes!), contains('通货膨胀'));
  });
}
