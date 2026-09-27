import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:memo_mind/features/document_import/domain/document_import_models.dart';
import 'package:memo_mind/features/ocr_editor/application/ocr_orchestrator.dart';
import 'package:memo_mind/features/ocr_editor/domain/ocr_engine.dart';
import 'package:memo_mind/features/ocr_editor/domain/ocr_models.dart';
import 'package:memo_mind/features/ocr_editor/domain/ocr_repository.dart';

class _FakeOcrRepository implements OcrRepository {
  final Map<String, List<SourceBlock>> savedBlocksByPage = {};
  final List<String> failedPageIds = [];
  bool draftSaved = false;

  @override
  Future<void> savePageOcrDraft({
    required String documentId,
    required String pageId,
    required int pageNumber,
    required List<SourceBlock> blocks,
    required String rawFullText,
    String? language,
  }) async {
    savedBlocksByPage[pageId] = blocks;
  }

  @override
  Future<void> recordPageOcrFailure({
    required String documentId,
    required String pageId,
    required String errorMessage,
  }) async {
    failedPageIds.add(pageId);
  }

  @override
  Future<void> saveDraft(String documentId) async {
    draftSaved = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeOcrEngine implements OcrEngine {
  _FakeOcrEngine({required this.results});

  final Map<String, ExtractedPageOcr> results;
  final Set<String> throwOnPaths = {};

  @override
  Future<ExtractedPageOcr> recognizeText({
    required String imagePath,
    required Size imageSize,
  }) async {
    if (throwOnPaths.contains(imagePath)) {
      throw Exception('Lỗi nhận dạng ảnh giả lập');
    }
    return results[imagePath] ??
        const ExtractedPageOcr(rawFullText: '', blocks: []);
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  group('OcrOrchestrator', () {
    late _FakeOcrRepository fakeRepo;
    late _FakeOcrEngine fakeEngine;
    late OcrOrchestrator orchestrator;

    final doc = ImportedDocument(
      documentId: 'doc-test',
      title: 'Tài liệu test',
      status: ImportedDocumentStatus.pendingOcr,
      privacy: DocumentPrivacy.private,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      pages: [
        SourcePage(
          pageId: 'p-1',
          documentId: 'doc-test',
          pageNumber: 1,
          originalPageNumber: 1,
          source: DocumentPageSource.gallery,
          dataRelativePath: 'p1.jpg',
          absolutePath: '/images/p1.jpg',
          mimeType: 'image/jpeg',
          fileSizeBytes: 100,
          width: 1000,
          height: 2000,
          sha256: 'h1',
          qualityCode: 'ok',
          qualityWarningAccepted: false,
          createdAt: DateTime.now(),
        ),
        SourcePage(
          pageId: 'p-2',
          documentId: 'doc-test',
          pageNumber: 2,
          originalPageNumber: 2,
          source: DocumentPageSource.gallery,
          dataRelativePath: 'p2.jpg',
          absolutePath: '/images/p2.jpg',
          mimeType: 'image/jpeg',
          fileSizeBytes: 100,
          width: 1000,
          height: 2000,
          sha256: 'h2',
          qualityCode: 'ok',
          qualityWarningAccepted: false,
          createdAt: DateTime.now(),
        ),
      ],
    );

    setUp(() {
      fakeRepo = _FakeOcrRepository();
      fakeEngine = _FakeOcrEngine(
        results: {
          '/images/p1.jpg': const ExtractedPageOcr(
            rawFullText: 'Dòng 1 câu hỏi\nDòng 2 độ tin cậy thấp',
            blocks: [
              ExtractedBlock(
                text: 'Dòng 1 câu hỏi',
                boundingBox: Rect.fromLTWH(100, 200, 800, 100),
                confidence: 0.95,
              ),
              ExtractedBlock(
                text: 'Dòng 2 độ tin cậy thấp',
                boundingBox: Rect.fromLTWH(100, 400, 800, 100),
                confidence: 0.60,
              ),
            ],
            detectedLanguage: 'vi',
          ),
          '/images/p2.jpg': const ExtractedPageOcr(
            rawFullText: 'Trang 2 hoàn tất',
            blocks: [
              ExtractedBlock(
                text: 'Trang 2 hoàn tất',
                boundingBox: Rect.fromLTWH(50, 100, 900, 200),
                confidence: 0.98,
              ),
            ],
          ),
        },
      );

      orchestrator = OcrOrchestrator(
        ocrRepository: fakeRepo,
        ocrEngine: fakeEngine,
      );
    });

    test('processes multiple pages and reports progress events', () async {
      final progressEvents = <OcrBatchProgress>[];

      await for (final event in orchestrator.processPages(
        document: doc,
        selectedPages: doc.pages,
      )) {
        progressEvents.add(event);
      }

      expect(progressEvents.isNotEmpty, isTrue);
      expect(progressEvents.last.isDone, isTrue);
      expect(progressEvents.last.successfulPages.length, 2);
      expect(progressEvents.last.failedPages, isEmpty);
      expect(fakeRepo.draftSaved, isTrue);

      final p1Blocks = fakeRepo.savedBlocksByPage['p-1']!;
      expect(p1Blocks.length, 2);
      // High confidence block should be draft
      expect(p1Blocks[0].status, BlockStatus.draft);
      expect(p1Blocks[0].boundingBox?.left, 0.1); // 100 / 1000
      expect(p1Blocks[0].boundingBox?.top, 0.1);  // 200 / 2000

      // Low confidence block (< 0.75) should be needsReview
      expect(p1Blocks[1].status, BlockStatus.needsReview);
    });

    test('handles partial page failure gracefully (Luồng 13a)', () async {
      // Simulate failure on page 2
      fakeEngine.throwOnPaths.add('/images/p2.jpg');

      final progressEvents = <OcrBatchProgress>[];
      await for (final event in orchestrator.processPages(
        document: doc,
        selectedPages: doc.pages,
      )) {
        progressEvents.add(event);
      }

      final last = progressEvents.last;
      expect(last.isDone, isTrue);
      expect(last.successfulPages.length, 1);
      expect(last.failedPages.length, 1);
      expect(last.failedPages.first.pageId, 'p-2');
      expect(fakeRepo.failedPageIds, contains('p-2'));
      expect(fakeRepo.savedBlocksByPage.containsKey('p-1'), isTrue);
      expect(fakeRepo.draftSaved, isTrue);
    });
  });
}
