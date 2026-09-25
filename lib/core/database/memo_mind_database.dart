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
      version: 2,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) => createV2(db),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await migrateV1ToV2(db);
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

  Future<void> close() async {
    final db = _database;
    _database = null;
    await db?.close();
  }
}
