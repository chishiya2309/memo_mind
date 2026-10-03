import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../core/database/memo_mind_database.dart';
import '../../../core/workspace/workspace_context.dart';
import '../../../core/workspace/source_file_pins.dart';
import '../domain/auth_repository.dart';

const maxBackupBytes = 100 * 1024 * 1024;
String canonicalJson(Object? value) {
  Object? sorted(Object? item) {
    if (item is List) return item.map(sorted).toList();
    if (item is Map) {
      final keys = item.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: sorted(item[key])};
    }
    return item;
  }

  return jsonEncode(sorted(value));
}

String contentHash(List<int> bytes) => sha256.convert(bytes).toString();
Future<String> fileHash(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();
bool safeFileKey(String key) =>
    key.isNotEmpty &&
    key.length <= 500 &&
    !key.startsWith('/') &&
    !key.contains('\\') &&
    key
        .split('/')
        .every(
          (s) => s.isNotEmpty && s != '.' && s != '..' && !s.contains(':'),
        );

Future<void> _encodeSnapshot(
  String stagingPath,
  String zipPath,
  List<String> keys,
) => Isolate.run(() async {
  final encoder = ZipFileEncoder()..create(zipPath);
  try {
    await encoder.addFile(File(p.join(stagingPath, 'data.json')), 'data.json');
    await encoder.addFile(
      File(p.join(stagingPath, 'manifest.json')),
      'manifest.json',
    );
    for (final key in keys) {
      await encoder.addFile(
        File(p.joinAll([stagingPath, 'files', ...key.split('/')])),
        'files/$key',
      );
    }
  } finally {
    await encoder.close();
  }
});

class BackupSnapshot {
  const BackupSnapshot(this.request, this.path);
  final Map<String, Object?> request;
  final String path;
}

class SnapshotCodec {
  Future<({int decks, int cards, int files, int bytes})> estimate(
    WorkspaceContext workspace,
  ) async {
    final db = await workspace.database.database;
    final tables = {
      for (final t in MemoMindDatabase.studyTables) t: await db.query(t),
    };
    final refs = _references(tables);
    return (
      decks: tables['decks']!.where((r) => r['status'] == 'active').length,
      cards: tables['cards']!.where((r) => r['status'] == 'active').length,
      files: refs.length,
      bytes: refs.values.fold(
        0,
        (sum, file) => sum + (file['sizeBytes'] as int),
      ),
    );
  }

  Map<String, Map<String, Object?>> _references(
    Map<String, List<Map<String, Object?>>> tables,
  ) {
    final refs = <String, Map<String, Object?>>{};
    void add(Object? key, Object? size, Object? hash) {
      if (key == null) return;
      if (key is! String ||
          (!safeFileKey(key) || !key.startsWith('documents/')) ||
          size is! int ||
          size <= 0 ||
          hash is! String) {
        throw const AccountFailure(
          'invalid_source',
          'Thông tin tệp nguồn không hợp lệ.',
        );
      }
      refs[key] = {'sizeBytes': size, 'sha256': hash};
    }

    for (final r in tables['documents']!) {
      add(
        r['original_file_relative_path'],
        r['original_file_size_bytes'],
        r['original_file_sha256'],
      );
    }
    for (final r in tables['source_pages']!) {
      add(r['data_relative_path'], r['file_size_bytes'], r['sha256']);
    }
    for (final r in tables['page_normalizations']!) {
      add(r['normalized_relative_path'], r['file_size_bytes'], r['sha256']);
    }
    return refs;
  }

  Future<BackupSnapshot> capture(WorkspaceContext workspace, String uid) async {
    if (!workspace.active || workspace.record.ownerUid != uid) {
      throw const AccountFailure(
        'wrong_workspace',
        'Kho chưa thuộc tài khoản này.',
      );
    }
    final backupId = const Uuid().v4();
    final staging = Directory(
      p.join(workspace.record.filesPath, '.backups', backupId),
    );
    await staging.create(recursive: true);
    final pinned = <String>[];
    final tables = <String, List<Map<String, Object?>>>{};
    late int revision, at;
    late Map<String, Map<String, Object?>> references;
    try {
      final db = await workspace.database.database;
      await db.transaction((txn) async {
        for (final table in MemoMindDatabase.studyTables) {
          final rows = (await txn.query(table))
              .map((r) => Map<String, Object?>.from(r))
              .toList();
          rows.sort((a, b) => canonicalJson(a).compareTo(canonicalJson(b)));
          tables[table] = rows;
        }
        revision =
            (await txn.query('workspace_revision')).single['revision'] as int;
        at = DateTime.now().millisecondsSinceEpoch;
        references = _references(tables);
        if (references.length > 1000) {
          throw const AccountFailure(
            'backup_limit',
            'Tối đa 1.000 tệp nguồn mỗi bản.',
          );
        }
        for (final key in references.keys) {
          final path = p.joinAll([
            workspace.record.filesPath,
            ...key.split('/'),
          ]);
          SourceFilePins.pin(path);
          pinned.add(path);
        }
      });
      final keys = references.keys.toList()..sort();
      final files = <Map<String, Object?>>[];
      var expanded = 0;
      for (final key in keys) {
        final source = File(
          p.joinAll([workspace.record.filesPath, ...key.split('/')]),
        );
        if (!await source.exists()) {
          throw AccountFailure('missing_source', 'Thiếu tệp nguồn: $key');
        }
        expanded += await source.length();
        if (expanded > maxBackupBytes) {
          throw const AccountFailure('backup_limit', 'Kho vượt 100 MiB.');
        }
        final copy = File(
          p.joinAll([staging.path, 'files', ...key.split('/')]),
        );
        await copy.parent.create(recursive: true);
        await source.copy(copy.path);
        final size = await copy.length(), hash = await fileHash(copy);
        if (size != references[key]!['sizeBytes'] ||
            hash != references[key]!['sha256']) {
          throw AccountFailure(
            'corrupt_source',
            'Tệp nguồn hỏng hoặc đã thay đổi: $key',
          );
        }
        files.add({'fileKey': key, 'sizeBytes': size, 'sha256': hash});
      }
      final dataBytes = utf8.encode(canonicalJson({'tables': tables}));
      final fingerprint = contentHash(
        utf8.encode(
          canonicalJson({
            'schemaVersion': 9,
            'schedulerVersion': 'sm2-v1',
            'dataHash': contentHash(dataBytes),
            'files': files,
          }),
        ),
      );
      final manifest = {
        'ownerUid': uid,
        'backupId': backupId,
        'workspaceId': workspace.record.id,
        'snapshotRevision': revision,
        'snapshotAt': at,
        'schemaVersion': 9,
        'schedulerVersion': 'sm2-v1',
        'fingerprint': fingerprint,
        'dataHash': contentHash(dataBytes),
        'files': files,
      };
      final manifestBytes = utf8.encode(canonicalJson(manifest));
      if (expanded + dataBytes.length + manifestBytes.length > maxBackupBytes) {
        throw const AccountFailure(
          'backup_limit',
          'Dữ liệu giải nén vượt 100 MiB.',
        );
      }
      final dataFile = File(p.join(staging.path, 'data.json'));
      final manifestFile = File(p.join(staging.path, 'manifest.json'));
      await dataFile.writeAsBytes(dataBytes, flush: true);
      await manifestFile.writeAsBytes(manifestBytes, flush: true);
      final zip = File(p.join(staging.path, 'snapshot.zip'));
      await _encodeSnapshot(staging.path, zip.path, keys);
      final size = await zip.length();
      if (size > maxBackupBytes) {
        throw const AccountFailure('backup_limit', 'Gói ZIP vượt 100 MiB.');
      }
      return BackupSnapshot({
        ...manifest
          ..remove('files')
          ..remove('dataHash'),
        'manifestHash': contentHash(manifestBytes),
        'bundleHash': await fileHash(zip),
        'sizeBytes': size,
        'fileCount': files.length,
      }, zip.path);
    } catch (_) {
      if (await staging.exists()) await staging.delete(recursive: true);
      rethrow;
    } finally {
      for (final path in pinned) {
        await SourceFilePins.release(path);
      }
    }
  }

  Future<WorkspaceRecord> restore(
    File zip,
    Map<String, dynamic> expected,
    String uid,
    WorkspaceRepository workspaces,
  ) async {
    if (expected['ownerUid'] != uid ||
        expected['status'] != 'ready' ||
        expected['schemaVersion'] != 9 ||
        expected['schedulerVersion'] != 'sm2-v1') {
      throw const AccountFailure(
        'incompatible_backup',
        'Bản sao không hợp lệ cho tài khoản hoặc phiên bản này.',
      );
    }
    if (await zip.length() > maxBackupBytes ||
        await fileHash(zip) != expected['bundleHash']) {
      throw const AccountFailure('checksum_mismatch', 'Gói tải xuống hỏng.');
    }
    final input = InputFileStream(zip.path);
    WorkspaceRecord? record;
    MemoMindDatabase? imported;
    try {
      final names = <String>{};
      var expanded = 0;
      final directory = ZipDirectory()..read(input);
      if (directory.fileHeaders.length > 1002) {
        throw const AccountFailure('backup_limit', 'Quá nhiều tệp.');
      }
      for (final header in directory.fileHeaders) {
        expanded += header.uncompressedSize;
        if (!names.add(header.filename) ||
            !safeFileKey(header.filename) ||
            (header.generalPurposeBitFlag & 1) != 0 ||
            ((header.externalFileAttributes >> 16) & 0xf000) == 0xa000 ||
            expanded > maxBackupBytes) {
          throw const AccountFailure(
            'invalid_archive',
            'ZIP có mục trùng, liên kết hoặc dung lượng không hợp lệ.',
          );
        }
      }
      input.setPosition(0);
      final archive = ZipDecoder().decodeStream(input);
      expanded = 0;
      for (final entry in archive) {
        expanded += entry.size;
        if (!safeFileKey(entry.name) ||
            !entry.isFile ||
            entry.isSymbolicLink ||
            expanded > maxBackupBytes) {
          throw const AccountFailure(
            'invalid_archive',
            'ZIP chứa đường dẫn hoặc dung lượng không hợp lệ.',
          );
        }
      }
      final manifestEntry = archive.find('manifest.json'),
          dataEntry = archive.find('data.json');
      if (manifestEntry == null || dataEntry == null) {
        throw const AccountFailure(
          'invalid_archive',
          'Thiếu dữ liệu hoặc manifest.',
        );
      }
      final manifestBytes = manifestEntry.content;
      if (contentHash(manifestBytes) != expected['manifestHash']) {
        throw const AccountFailure('checksum_mismatch', 'Manifest hỏng.');
      }
      final manifest =
          jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
      for (final key in [
        'ownerUid',
        'backupId',
        'workspaceId',
        'schemaVersion',
        'schedulerVersion',
        'snapshotRevision',
        'snapshotAt',
        'fingerprint',
      ]) {
        if (manifest[key] != expected[key]) {
          throw const AccountFailure(
            'invalid_manifest',
            'Manifest không khớp bản sao.',
          );
        }
      }
      final dataBytes = dataEntry.content;
      if (contentHash(dataBytes) != manifest['dataHash']) {
        throw const AccountFailure('checksum_mismatch', 'Dữ liệu hỏng.');
      }
      final data = jsonDecode(utf8.decode(dataBytes)) as Map<String, dynamic>;
      final rawTables = Map<String, dynamic>.from(data['tables'] as Map);
      if (rawTables.length != MemoMindDatabase.studyTables.length ||
          MemoMindDatabase.studyTables.any((t) => rawTables[t] is! List)) {
        throw const AccountFailure(
          'invalid_data',
          'Bảng dữ liệu không hợp lệ.',
        );
      }
      final files = (manifest['files'] as List).cast<Map<String, dynamic>>();
      if (archive.length != files.length + 2 ||
          files.length != expected['fileCount']) {
        throw const AccountFailure('missing_source', 'Số tệp không khớp.');
      }
      if (contentHash(
            utf8.encode(
              canonicalJson({
                'schemaVersion': 9,
                'schedulerVersion': 'sm2-v1',
                'dataHash': contentHash(dataBytes),
                'files': files,
              }),
            ),
          ) !=
          expected['fingerprint']) {
        throw const AccountFailure(
          'checksum_mismatch',
          'Dấu vân tay không khớp.',
        );
      }
      record = await workspaces.create(
        uid,
        name:
            'Kho khôi phục ${DateTime.fromMillisecondsSinceEpoch(expected['snapshotAt'] as int).toLocal()}',
        status: 'staging',
      );
      final fileKeys = <String>{};
      for (final file in files) {
        final key = file['fileKey'] as String;
        final entry = archive.find('files/$key');
        if ((!safeFileKey(key) || !key.startsWith('documents/')) ||
            !fileKeys.add(key) ||
            entry == null ||
            entry.size != file['sizeBytes']) {
          throw const AccountFailure('missing_source', 'Thiếu tệp nguồn.');
        }
        final destination = File(
          p.joinAll([record.filesPath, ...key.split('/')]),
        );
        await destination.parent.create(recursive: true);
        final output = OutputFileStream(destination.path);
        try {
          entry.writeContent(output);
        } finally {
          await output.close();
        }
        if (await fileHash(destination) != file['sha256']) {
          throw const AccountFailure('checksum_mismatch', 'Tệp nguồn hỏng.');
        }
      }
      final tables = {
        for (final t in MemoMindDatabase.studyTables)
          t: (rawTables[t] as List)
              .map((r) => Map<String, Object?>.from(r as Map))
              .toList(),
      };
      final refs = _references(tables);
      final manifestFiles = {for (final file in files) file['fileKey']: file};
      if (refs.entries.any(
        (r) =>
            !fileKeys.contains(r.key) ||
            manifestFiles[r.key]!['sizeBytes'] != r.value['sizeBytes'] ||
            manifestFiles[r.key]!['sha256'] != r.value['sha256'],
      )) {
        throw const AccountFailure(
          'missing_source',
          'Tệp tham chiếu không khớp metadata.',
        );
      }
      imported = MemoMindDatabase.atPath(record.databasePath);
      final db = await imported.database;
      await db.transaction((txn) async {
        for (final table in MemoMindDatabase.studyTables) {
          for (final row in tables[table]!) {
            await txn.insert(table, row);
          }
        }
        if ((await txn.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
          throw const AccountFailure('invalid_data', 'Quan hệ dữ liệu hỏng.');
        }
        await txn.update('decks', {'card_count': 0});
        await txn.execute(
          "UPDATE decks SET card_count=(SELECT COUNT(*) FROM cards WHERE cards.deck_id=decks.deck_id AND cards.status!='deleted')",
        );
        await txn.update('workspace_revision', {
          'revision': manifest['snapshotRevision'],
        }, where: 'id=1');
      });
      await imported.close();
      imported = null;
      await workspaces.publish(record.id);
      return await workspaces.get(record.id);
    } catch (_) {
      await imported?.close();
      if (record != null) {
        await workspaces.registry.update(
          'workspaces',
          {'status': 'failed'},
          where: 'workspace_id=?',
          whereArgs: [record.id],
        );
        await Directory(record.filesPath).delete(recursive: true);
        await deleteDatabaseFile(record.databasePath);
      }
      rethrow;
    } finally {
      await input.close();
    }
  }

  Future<void> deleteDatabaseFile(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
