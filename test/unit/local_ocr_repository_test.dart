import 'package:flutter_test/flutter_test.dart';
import 'package:memo_mind/core/database/memo_mind_database.dart';
import 'package:memo_mind/features/document_import/domain/document_import_models.dart';
import 'package:memo_mind/features/document_import/domain/document_import_repository.dart';
import 'package:memo_mind/features/ocr_editor/data/local_ocr_repository.dart';
import 'package:memo_mind/features/ocr_editor/domain/ocr_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeDocumentImportRepository implements DocumentImportRepository {
  _FakeDocumentImportRepository(this.document);

  ImportedDocument document;

  @override
  Future<ImportedDocument> getDocument(String documentId) async => document;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(sqfliteFfiInit);

  group('LocalOcrRepository', () {
    late Database db;
    late MemoMindDatabase database;
    late _FakeDocumentImportRepository docRepo;
    late LocalOcrRepository ocrRepo;

    final testDoc = ImportedDocument(
      documentId: 'doc-1',
      title: 'Đề kiểm tra',
      status: ImportedDocumentStatus.pendingOcr,
      privacy: DocumentPrivacy.private,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
      pages: [
        SourcePage(
          pageId: 'page-1',
          documentId: 'doc-1',
          pageNumber: 1,
          originalPageNumber: 1,
          source: DocumentPageSource.gallery,
          dataRelativePath: 'doc-1/page-1.jpg',
          absolutePath: '/storage/doc-1/page-1.jpg',
          mimeType: 'image/jpeg',
          fileSizeBytes: 1024,
          width: 800,
          height: 1200,
          sha256: 'sha-page-1',
          qualityCode: 'ok',
          qualityWarningAccepted: false,
          createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
        ),
      ],
    );

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute('PRAGMA foreign_keys = ON');
      await MemoMindDatabase.createV4(db);

      // Insert test document
      await db.insert('documents', {
        'document_id': 'doc-1',
        'title': 'Đề kiểm tra',
        'status': 'pending_ocr',
        'privacy': 'private',
        'page_count': 1,
        'created_at': 1000,
        'updated_at': 1000,
      });

      await db.insert('source_pages', {
        'page_id': 'page-1',
        'document_id': 'doc-1',
        'page_number': 1,
        'original_page_number': 1,
        'source': 'gallery',
        'data_relative_path': 'doc-1/page-1.jpg',
        'mime_type': 'image/jpeg',
        'file_size_bytes': 1024,
        'width': 800,
        'height': 1200,
        'sha256': 'sha-page-1',
        'quality_code': 'ok',
        'quality_warning_accepted': 0,
        'created_at': 1000,
        'normalization_status': 'ready',
      });

      database = MemoMindDatabase.forTesting(db);
      docRepo = _FakeDocumentImportRepository(testDoc);
      ocrRepo = LocalOcrRepository(
        documentRepository: docRepo,
        database: database,
        clock: () => DateTime.fromMillisecondsSinceEpoch(2000),
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('savePageOcrDraft saves blocks and updates document status', () async {
      final block1 = SourceBlock(
        blockId: 'b-1',
        documentId: 'doc-1',
        pageId: 'page-1',
        pageNumber: 1,
        orderIndex: 0,
        rawText: 'Câu 1: Giải phương trình',
        normalizedText: 'Câu 1: Giải phương trình',
        boundingBox: const NormalizedBoundingBox(
          left: 0.1,
          top: 0.1,
          width: 0.8,
          height: 0.05,
        ),
        hasValidBox: true,
        confidence: 0.95,
        confidenceSource: ConfidenceSource.mlkit,
        status: BlockStatus.draft,
        createdAt: DateTime.fromMillisecondsSinceEpoch(2000),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
      );

      await ocrRepo.savePageOcrDraft(
        documentId: 'doc-1',
        pageId: 'page-1',
        pageNumber: 1,
        blocks: [block1],
        rawFullText: 'Câu 1: Giải phương trình',
        language: 'vi',
      );

      final blocks = await ocrRepo.getPageBlocks('page-1');
      expect(blocks.length, 1);
      expect(blocks.first.rawText, 'Câu 1: Giải phương trình');
      expect(blocks.first.normalizedText, 'Câu 1: Giải phương trình');
      expect(blocks.first.confidence, 0.95);

      // Check document status updated in database
      final docRow = (await db.query('documents', where: 'document_id = ?', whereArgs: ['doc-1'])).single;
      expect(docRow['status'], 'pending_ocr_review');
    });

    test('re-running OCR preserves user edited and added blocks (BR04-07)', () async {
      final block1 = SourceBlock(
        blockId: 'b-1',
        documentId: 'doc-1',
        pageId: 'page-1',
        pageNumber: 1,
        orderIndex: 0,
        rawText: 'Nội dung cũ',
        normalizedText: 'Nội dung cũ',
        status: BlockStatus.draft,
        createdAt: DateTime.fromMillisecondsSinceEpoch(2000),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
      );

      await ocrRepo.savePageOcrDraft(
        documentId: 'doc-1',
        pageId: 'page-1',
        pageNumber: 1,
        blocks: [block1],
        rawFullText: 'Nội dung cũ',
      );

      // User modifies block 1
      await ocrRepo.updateSourceBlock(
        block1.copyWith(normalizedText: 'Nội dung đã chỉnh sửa'),
      );

      // Re-run OCR with new block
      final newBlock = SourceBlock(
        blockId: 'b-2',
        documentId: 'doc-1',
        pageId: 'page-1',
        pageNumber: 1,
        orderIndex: 0,
        rawText: 'Nội dung quét mới',
        normalizedText: 'Nội dung quét mới',
        status: BlockStatus.draft,
        createdAt: DateTime.fromMillisecondsSinceEpoch(3000),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(3000),
      );

      await ocrRepo.savePageOcrDraft(
        documentId: 'doc-1',
        pageId: 'page-1',
        pageNumber: 1,
        blocks: [newBlock],
        rawFullText: 'Nội dung quét mới',
      );

      final blocks = await ocrRepo.getPageBlocks('page-1');
      expect(blocks.length, 2);
      expect(
        blocks.any((b) => b.normalizedText == 'Nội dung đã chỉnh sửa'),
        isTrue,
      );
      expect(
        blocks.any((b) => b.rawText == 'Nội dung quét mới'),
        isTrue,
      );
    });

    test('restoreSourceBlock resets normalized text to raw text', () async {
      final block1 = SourceBlock(
        blockId: 'b-1',
        documentId: 'doc-1',
        pageId: 'page-1',
        pageNumber: 1,
        orderIndex: 0,
        rawText: 'Văn bản gốc',
        normalizedText: 'Văn bản sửa sai',
        confidence: 0.9,
        status: BlockStatus.draft,
        createdAt: DateTime.fromMillisecondsSinceEpoch(2000),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
      );

      await ocrRepo.savePageOcrDraft(
        documentId: 'doc-1',
        pageId: 'page-1',
        pageNumber: 1,
        blocks: [block1],
        rawFullText: 'Văn bản gốc',
      );

      await ocrRepo.restoreSourceBlock('b-1');

      final blocks = await ocrRepo.getPageBlocks('page-1');
      expect(blocks.first.normalizedText, 'Văn bản gốc');
    });

    test('confirmOcrReview marks blocks verified and document readyForGeneration', () async {
      final block1 = SourceBlock(
        blockId: 'b-1',
        documentId: 'doc-1',
        pageId: 'page-1',
        pageNumber: 1,
        orderIndex: 0,
        rawText: 'Đoạn 1',
        normalizedText: 'Đoạn 1',
        status: BlockStatus.needsReview,
        createdAt: DateTime.fromMillisecondsSinceEpoch(2000),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
      );

      await ocrRepo.savePageOcrDraft(
        documentId: 'doc-1',
        pageId: 'page-1',
        pageNumber: 1,
        blocks: [block1],
        rawFullText: 'Đoạn 1',
      );

      await ocrRepo.confirmOcrReview('doc-1');

      final blocks = await ocrRepo.getPageBlocks('page-1');
      expect(blocks.first.status, BlockStatus.verified);

      final docRow = (await db.query('documents', where: 'document_id = ?', whereArgs: ['doc-1'])).single;
      expect(docRow['status'], 'ready_for_generation');
    });
  });
}
