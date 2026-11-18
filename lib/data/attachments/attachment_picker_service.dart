import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/knowledge_models.dart';
import '../ai/deepseek_ocr_client.dart';

/// 四端附件采集服务接口（拍照 / 相册选择 / 添加文件），便于测试注入 Fake 实现
abstract class AttachmentPickerService {
  bool get supportsCamera;

  Future<StudyAttachment?> pickFromCamera();
  Future<List<StudyAttachment>> pickFromGallery();
  Future<List<StudyAttachment>> pickFiles();
}

class NativeAttachmentPickerService implements AttachmentPickerService {
  static const int maxPlainTextChars = 24000;
  static const int maxImageBytes = 20 * 1024 * 1024;

  static const Set<String> imageExts = {
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.webp',
  };

  static const Set<String> plainTextExts = {
    '.txt',
    '.md',
    '.markdown',
    '.json',
    '.yaml',
    '.yml',
    '.csv',
    '.xml',
    '.html',
    '.htm',
    '.css',
    '.js',
    '.ts',
    '.tsx',
    '.jsx',
    '.dart',
    '.py',
    '.c',
    '.cc',
    '.cpp',
    '.h',
    '.hpp',
    '.java',
    '.kt',
    '.swift',
    '.go',
    '.rs',
    '.sql',
    '.sh',
    '.log',
    '.ini',
    '.toml',
  };

  static const Set<String> ocrDocumentExts = {
    '.pdf',
    '.doc',
    '.docx',
    '.ppt',
    '.pptx',
  };

  final ImagePicker _imagePicker;
  final Uuid _uuid;

  NativeAttachmentPickerService({
    ImagePicker? imagePicker,
    Uuid? uuid,
  })  : _imagePicker = imagePicker ?? ImagePicker(),
        _uuid = uuid ?? const Uuid();

  @override
  bool get supportsCamera => Platform.isAndroid || Platform.isIOS;

  @override
  Future<StudyAttachment?> pickFromCamera() async {
    if (!supportsCamera) return null;
    final picked = await _imagePicker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (picked == null) return null;
    return _persistPickedFile(picked, forceImage: true);
  }

  @override
  Future<List<StudyAttachment>> pickFromGallery() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final picked = await _imagePicker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (picked.isEmpty) return const [];
      final out = <StudyAttachment>[];
      for (final item in picked) {
        out.add(await _persistPickedFile(item, forceImage: true));
      }
      return out;
    }

    // 桌面端（macOS / Windows）：通过系统文件选择器挑选图片
    final files = await openFiles(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: '图片',
          extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'],
        ),
      ],
    );
    if (files.isEmpty) return const [];
    final out = <StudyAttachment>[];
    for (final f in files) {
      out.add(await _persistPickedFile(f, forceImage: true));
    }
    return out;
  }

  @override
  Future<List<StudyAttachment>> pickFiles() async {
    final files = await openFiles(
      acceptedTypeGroups: [
        XTypeGroup(
          label: '文档与代码',
          extensions: [
            'pdf',
            'doc',
            'docx',
            'ppt',
            'pptx',
            'txt',
            'md',
            'json',
            'yaml',
            'yml',
            'csv',
            'dart',
            'py',
            'cpp',
            'c',
            'h',
            'java',
            'js',
            'ts',
            'html',
            'css',
            'xml',
            'log',
            'jpg',
            'jpeg',
            'png',
            'webp',
          ],
        ),
      ],
    );
    if (files.isEmpty) return const [];

    final out = <StudyAttachment>[];
    for (final f in files) {
      out.add(await _persistPickedFile(f));
    }
    return out;
  }

  Future<StudyAttachment> _persistPickedFile(
    XFile source, {
    bool forceImage = false,
  }) async {
    final id = _uuid.v4();
    final rawName = source.name.trim().isNotEmpty
        ? source.name.trim()
        : p.basename(source.path);
    final ext = p.extension(rawName).toLowerCase();
    final isImage = forceImage || imageExts.contains(ext);
    final bytes = await source.readAsBytes();

    if (isImage && bytes.length > maxImageBytes) {
      throw StateError('图片「$rawName」超过 20MB 上限');
    }
    if (!isImage && bytes.length > DeepSeekOcrClient.maxFileSizeBytes) {
      throw StateError('文件「$rawName」超过 100MB 上限');
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final attachDir = Directory(p.join(docsDir.path, 'EchoMind', 'attachments'));
    if (!attachDir.existsSync()) {
      await attachDir.create(recursive: true);
    }

    final safeName = rawName.replaceAll(RegExp(r'[^\w.\-\u4e00-\u9fa5]'), '_');
    final targetPath = p.join(attachDir.path, '${id}_$safeName');
    await File(targetPath).writeAsBytes(bytes, flush: true);

    String? extractedText;
    if (!isImage && plainTextExts.contains(ext)) {
      var decoded = utf8.decode(bytes, allowMalformed: true).trim();
      if (decoded.length > maxPlainTextChars) {
        decoded =
            '${decoded.substring(0, maxPlainTextChars)}\n…（文件较长，已截断前 $maxPlainTextChars 字）';
      }
      extractedText = decoded;
    }

    return StudyAttachment(
      id: id,
      kind: isImage ? StudyAttachmentKind.image : StudyAttachmentKind.file,
      name: rawName,
      localPath: targetPath,
      mimeType: _mimeForExt(ext, isImage: isImage),
      sizeBytes: bytes.length,
      extractedText: extractedText,
    );
  }

  static bool needsOcr(StudyAttachment attachment) {
    if (attachment.isImage) return false;
    if (attachment.extractedText != null &&
        attachment.extractedText!.trim().isNotEmpty) {
      return false;
    }
    final ext = p.extension(attachment.name).toLowerCase();
    return ocrDocumentExts.contains(ext) || !plainTextExts.contains(ext);
  }

  static String _mimeForExt(String ext, {required bool isImage}) {
    return switch (ext) {
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.png' => 'image/png',
      '.gif' => 'image/gif',
      '.webp' => 'image/webp',
      '.pdf' => 'application/pdf',
      '.doc' => 'application/msword',
      '.docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      '.ppt' => 'application/vnd.ms-powerpoint',
      '.pptx' =>
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      '.md' || '.markdown' => 'text/markdown',
      '.json' => 'application/json',
      '.csv' => 'text/csv',
      '.txt' => 'text/plain',
      _ => isImage ? 'image/jpeg' : 'application/octet-stream',
    };
  }
}
