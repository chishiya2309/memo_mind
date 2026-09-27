import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class MemoMindDatabase {
  MemoMindDatabase._();

  MemoMindDatabase.forTesting(Database database) : _database = database;

  static final MemoMindDatabase instance = MemoMindDatabase._();

  Database? _database;

  Future<Database> get database async => _database ??= await _open();

  Future<Database> _open() async {
    final root = await getDatabasesPath();
    return openDatabase(
      p.join(root, 'memo_mind.db'),
      version: 4,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) => createV4(db),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await migrateV1ToV2(db);
        if (oldVersion < 3) await migrateV2ToV3(db);
        if (oldVersion < 4) await migrateV3ToV4(db);
      },
    );
  }

  static Future<void> createV2(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE documents (
        document_id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        status TEXT NOT NULL
          CHECK(status IN ('pending_processing', 'pending_ocr')),
        privacy TEXT NOT NULL DEFAULT 'private' CHECK(privacy = 'private'),
        page_count INTEGER NOT NULL DEFAULT 0 CHECK(page_count >= 0),
        original_file_name TEXT,
        original_file_relative_path TEXT UNIQUE,
        original_file_mime_type TEXT,
        original_file_size_bytes INTEGER,
        original_file_sha256 TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        CHECK(
          (original_file_relative_path IS NULL
            AND original_file_name IS NULL
            AND original_file_mime_type IS NULL
            AND original_file_size_bytes IS NULL
            AND original_file_sha256 IS NULL)
          OR
          (original_file_relative_path IS NOT NULL
            AND original_file_name IS NOT NULL
            AND original_file_mime_type = 'application/pdf'
            AND original_file_size_bytes > 0
            AND original_file_sha256 IS NOT NULL)
        )
      )
    ''');
    await db.execute('''
      CREATE TABLE source_pages (
        page_id TEXT PRIMARY KEY,
        document_id TEXT NOT NULL,
        page_number INTEGER NOT NULL CHECK(page_number > 0),
        original_page_number INTEGER NOT NULL CHECK(original_page_number > 0),
        source TEXT NOT NULL CHECK(source IN ('camera', 'gallery', 'pdf')),
        data_relative_path TEXT NOT NULL UNIQUE,
        mime_type TEXT NOT NULL CHECK(mime_type IN ('image/jpeg', 'image/png')),
        file_size_bytes INTEGER NOT NULL CHECK(file_size_bytes > 0),
        width INTEGER NOT NULL CHECK(width > 0),
        height INTEGER NOT NULL CHECK(height > 0),
        sha256 TEXT NOT NULL,
        quality_code TEXT NOT NULL,
        quality_warning_accepted INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        FOREIGN KEY(document_id) REFERENCES documents(document_id) ON DELETE CASCADE,
        UNIQUE(document_id, page_number),
        UNIQUE(document_id, original_page_number)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_source_pages_document_id '
      'ON source_pages(document_id)',
    );
  }

  static Future<void> migrateV1ToV2(Database db) async {
    await db.execute('ALTER TABLE source_pages RENAME TO source_pages_v1');
    await db.execute('ALTER TABLE documents RENAME TO documents_v1');
    await db.execute('DROP INDEX idx_source_pages_document_id');
    await createV2(db);
    await db.execute('''
      INSERT INTO documents (
        document_id, title, status, privacy, page_count,
        created_at, updated_at
      )
      SELECT
        document_id, title, status, privacy, page_count,
        created_at, updated_at
      FROM documents_v1
    ''');
    await db.execute('''
      INSERT INTO source_pages (
        page_id, document_id, page_number, original_page_number, source,
        data_relative_path, mime_type, file_size_bytes, width, height, sha256,
        quality_code, quality_warning_accepted, created_at
      )
      SELECT
        page_id, document_id, page_number, page_number, source,
        original_relative_path, mime_type, file_size_bytes, width, height,
        sha256, quality_code, quality_warning_accepted, created_at
      FROM source_pages_v1
    ''');
    await db.execute('DROP TABLE source_pages_v1');
    await db.execute('DROP TABLE documents_v1');
  }

  static Future<void> createV3(DatabaseExecutor db) async {
    await createV2(db);
    await _addNormalizationSchema(db);
  }

  static Future<void> migrateV2ToV3(Database db) async {
    await _addNormalizationSchema(db);
  }

  static Future<void> _addNormalizationSchema(DatabaseExecutor db) async {
    await db.execute('''
      ALTER TABLE source_pages ADD COLUMN normalization_status TEXT NOT NULL
      DEFAULT 'pending'
      CHECK(normalization_status IN ('pending', 'ready', 'source_ready'))
    ''');
    await db.execute('''
      UPDATE source_pages
      SET normalization_status = CASE
        WHEN source = 'pdf' THEN 'source_ready'
        ELSE 'pending'
      END
    ''');
    await db.execute('''
      CREATE TABLE page_normalizations (
        page_id TEXT PRIMARY KEY,
        revision INTEGER NOT NULL CHECK(revision > 0),
        normalized_relative_path TEXT NOT NULL UNIQUE,
        mime_type TEXT NOT NULL CHECK(mime_type = 'image/png'),
        file_size_bytes INTEGER NOT NULL CHECK(file_size_bytes > 0),
        width INTEGER NOT NULL CHECK(width > 0),
        height INTEGER NOT NULL CHECK(height > 0),
        sha256 TEXT NOT NULL,
        top_left_x REAL NOT NULL CHECK(top_left_x BETWEEN 0 AND 1),
        top_left_y REAL NOT NULL CHECK(top_left_y BETWEEN 0 AND 1),
        top_right_x REAL NOT NULL CHECK(top_right_x BETWEEN 0 AND 1),
        top_right_y REAL NOT NULL CHECK(top_right_y BETWEEN 0 AND 1),
        bottom_right_x REAL NOT NULL CHECK(bottom_right_x BETWEEN 0 AND 1),
        bottom_right_y REAL NOT NULL CHECK(bottom_right_y BETWEEN 0 AND 1),
        bottom_left_x REAL NOT NULL CHECK(bottom_left_x BETWEEN 0 AND 1),
        bottom_left_y REAL NOT NULL CHECK(bottom_left_y BETWEEN 0 AND 1),
        rotation_degrees INTEGER NOT NULL
          CHECK(rotation_degrees IN (0, 90, 180, 270)),
        contrast REAL NOT NULL CHECK(contrast BETWEEN -0.5 AND 0.5),
        updated_at INTEGER NOT NULL,
        FOREIGN KEY(page_id) REFERENCES source_pages(page_id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_page_normalizations_path '
      'ON page_normalizations(normalized_relative_path)',
    );
  }

  static Future<void> createV4(DatabaseExecutor db) async {
    await _createDocumentsTable(db);
    await db.execute('''
      CREATE TABLE source_pages (
        page_id TEXT PRIMARY KEY,
        document_id TEXT NOT NULL,
        page_number INTEGER NOT NULL CHECK(page_number > 0),
        original_page_number INTEGER NOT NULL CHECK(original_page_number > 0),
        source TEXT NOT NULL CHECK(source IN ('camera', 'gallery', 'pdf')),
        data_relative_path TEXT NOT NULL UNIQUE,
        mime_type TEXT NOT NULL CHECK(mime_type IN ('image/jpeg', 'image/png')),
        file_size_bytes INTEGER NOT NULL CHECK(file_size_bytes > 0),
        width INTEGER NOT NULL CHECK(width > 0),
        height INTEGER NOT NULL CHECK(height > 0),
        sha256 TEXT NOT NULL,
        quality_code TEXT NOT NULL,
        quality_warning_accepted INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        normalization_status TEXT NOT NULL
          DEFAULT 'pending'
          CHECK(normalization_status IN ('pending', 'ready', 'source_ready')),
        FOREIGN KEY(document_id) REFERENCES documents(document_id) ON DELETE CASCADE,
        UNIQUE(document_id, page_number),
        UNIQUE(document_id, original_page_number)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_source_pages_document_id '
      'ON source_pages(document_id)',
    );
    await db.execute('''
      CREATE TABLE page_normalizations (
        page_id TEXT PRIMARY KEY,
        revision INTEGER NOT NULL CHECK(revision > 0),
        normalized_relative_path TEXT NOT NULL UNIQUE,
        mime_type TEXT NOT NULL CHECK(mime_type = 'image/png'),
        file_size_bytes INTEGER NOT NULL CHECK(file_size_bytes > 0),
        width INTEGER NOT NULL CHECK(width > 0),
        height INTEGER NOT NULL CHECK(height > 0),
        sha256 TEXT NOT NULL,
        top_left_x REAL NOT NULL CHECK(top_left_x BETWEEN 0 AND 1),
        top_left_y REAL NOT NULL CHECK(top_left_y BETWEEN 0 AND 1),
        top_right_x REAL NOT NULL CHECK(top_right_x BETWEEN 0 AND 1),
        top_right_y REAL NOT NULL CHECK(top_right_y BETWEEN 0 AND 1),
        bottom_right_x REAL NOT NULL CHECK(bottom_right_x BETWEEN 0 AND 1),
        bottom_right_y REAL NOT NULL CHECK(bottom_right_y BETWEEN 0 AND 1),
        bottom_left_x REAL NOT NULL CHECK(bottom_left_x BETWEEN 0 AND 1),
        bottom_left_y REAL NOT NULL CHECK(bottom_left_y BETWEEN 0 AND 1),
        rotation_degrees INTEGER NOT NULL
          CHECK(rotation_degrees IN (0, 90, 180, 270)),
        contrast REAL NOT NULL CHECK(contrast BETWEEN -0.5 AND 0.5),
        updated_at INTEGER NOT NULL,
        FOREIGN KEY(page_id) REFERENCES source_pages(page_id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_page_normalizations_path '
      'ON page_normalizations(normalized_relative_path)',
    );
    await _createOcrTables(db);
  }

  static Future<void> migrateV3ToV4(Database db) async {
    await db.execute(
      'ALTER TABLE page_normalizations RENAME TO page_normalizations_v3',
    );
    await db.execute('ALTER TABLE source_pages RENAME TO source_pages_v3');
    await db.execute('ALTER TABLE documents RENAME TO documents_v3');
    await db.execute('DROP INDEX IF EXISTS idx_source_pages_document_id');
    await db.execute('DROP INDEX IF EXISTS idx_page_normalizations_path');

    await createV4(db);

    await db.execute('''
      INSERT INTO documents (
        document_id, title, status, privacy, page_count,
        original_file_name, original_file_relative_path,
        original_file_mime_type, original_file_size_bytes,
        original_file_sha256, created_at, updated_at
      )
      SELECT
        document_id, title, status, privacy, page_count,
        original_file_name, original_file_relative_path,
        original_file_mime_type, original_file_size_bytes,
        original_file_sha256, created_at, updated_at
      FROM documents_v3
    ''');

    await db.execute('''
      INSERT INTO source_pages (
        page_id, document_id, page_number, original_page_number, source,
        data_relative_path, mime_type, file_size_bytes, width, height,
        sha256, quality_code, quality_warning_accepted, created_at,
        normalization_status
      )
      SELECT
        page_id, document_id, page_number, original_page_number, source,
        data_relative_path, mime_type, file_size_bytes, width, height,
        sha256, quality_code, quality_warning_accepted, created_at,
        normalization_status
      FROM source_pages_v3
    ''');

    await db.execute('''
      INSERT INTO page_normalizations (
        page_id, revision, normalized_relative_path, mime_type,
        file_size_bytes, width, height, sha256,
        top_left_x, top_left_y, top_right_x, top_right_y,
        bottom_right_x, bottom_right_y, bottom_left_x, bottom_left_y,
        rotation_degrees, contrast, updated_at
      )
      SELECT
        page_id, revision, normalized_relative_path, mime_type,
        file_size_bytes, width, height, sha256,
        top_left_x, top_left_y, top_right_x, top_right_y,
        bottom_right_x, bottom_right_y, bottom_left_x, bottom_left_y,
        rotation_degrees, contrast, updated_at
      FROM page_normalizations_v3
    ''');

    await db.execute('DROP TABLE page_normalizations_v3');
    await db.execute('DROP TABLE source_pages_v3');
    await db.execute('DROP TABLE documents_v3');
  }

  static Future<void> _createDocumentsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE documents (
        document_id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        status TEXT NOT NULL
          CHECK(status IN ('pending_processing', 'pending_ocr', 'pending_ocr_review', 'ready_for_generation')),
        privacy TEXT NOT NULL DEFAULT 'private' CHECK(privacy = 'private'),
        page_count INTEGER NOT NULL DEFAULT 0 CHECK(page_count >= 0),
        original_file_name TEXT,
        original_file_relative_path TEXT UNIQUE,
        original_file_mime_type TEXT,
        original_file_size_bytes INTEGER,
        original_file_sha256 TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        CHECK(
          (original_file_relative_path IS NULL
            AND original_file_name IS NULL
            AND original_file_mime_type IS NULL
            AND original_file_size_bytes IS NULL
            AND original_file_sha256 IS NULL)
          OR
          (original_file_relative_path IS NOT NULL
            AND original_file_name IS NOT NULL
            AND original_file_mime_type = 'application/pdf'
            AND original_file_size_bytes > 0
            AND original_file_sha256 IS NOT NULL)
        )
      )
    ''');
  }

  static Future<void> _createOcrTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE ocr_page_results (
        page_id TEXT PRIMARY KEY,
        document_id TEXT NOT NULL,
        status TEXT NOT NULL CHECK(status IN ('not_started', 'processing', 'completed', 'failed')),
        recognized_language TEXT,
        raw_full_text TEXT,
        error_message TEXT,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY(page_id) REFERENCES source_pages(page_id) ON DELETE CASCADE,
        FOREIGN KEY(document_id) REFERENCES documents(document_id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_ocr_page_results_doc ON ocr_page_results(document_id)',
    );

    await db.execute('''
      CREATE TABLE source_blocks (
        block_id TEXT PRIMARY KEY,
        document_id TEXT NOT NULL,
        page_id TEXT NOT NULL,
        page_number INTEGER NOT NULL CHECK(page_number > 0),
        order_index INTEGER NOT NULL CHECK(order_index >= 0),
        raw_text TEXT NOT NULL,
        normalized_text TEXT NOT NULL,
        box_left REAL CHECK(box_left BETWEEN 0 AND 1),
        box_top REAL CHECK(box_top BETWEEN 0 AND 1),
        box_width REAL CHECK(box_width BETWEEN 0 AND 1),
        box_height REAL CHECK(box_height BETWEEN 0 AND 1),
        has_valid_box INTEGER NOT NULL DEFAULT 1 CHECK(has_valid_box IN (0, 1)),
        confidence REAL CHECK(confidence IS NULL OR (confidence BETWEEN 0 AND 1)),
        confidence_source TEXT NOT NULL CHECK(confidence_source IN ('mlkit', 'gemini', 'user', 'unavailable')),
        status TEXT NOT NULL CHECK(status IN ('draft', 'needs_review', 'verified', 'user_added', 'deleted')),
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY(document_id) REFERENCES documents(document_id) ON DELETE CASCADE,
        FOREIGN KEY(page_id) REFERENCES source_pages(page_id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_source_blocks_page ON source_blocks(page_id, order_index)',
    );
    await db.execute(
      'CREATE INDEX idx_source_blocks_doc ON source_blocks(document_id)',
    );
  }

  Future<void> close() async {
    final db = _database;
    _database = null;
    await db?.close();
  }
}
