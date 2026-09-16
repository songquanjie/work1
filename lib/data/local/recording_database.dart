import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../models/recording.dart';

abstract class RecordingStore {
  Future<void> insert(Recording recording);
  Future<void> delete(String id);
  Future<Recording?> findById(String id);
  Future<List<Recording>> findAllNewestFirst();
  Future<void> close();
}

class RecordingDatabase implements RecordingStore {
  RecordingDatabase({Database? database}) : _injected = database;

  final Database? _injected;
  Database? _db;

  static const int schemaVersion = 2;

  static Future<void> createSchema(Database db, int _) async {
    await db.execute('''
      CREATE TABLE recordings (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        file_name TEXT NOT NULL,
        local_path TEXT NOT NULL,
        duration_ms INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_recordings_created_at ON recordings(created_at DESC)',
    );
  }

  /// Copies the columns this app still uses, whether the old table was slim
  /// or the earlier full P0 schema (both shipped as version 1).
  static Future<void> upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion >= newVersion) {
      return;
    }
    await db.execute('DROP INDEX IF EXISTS idx_recordings_created_at');
    await db.execute('ALTER TABLE recordings RENAME TO recordings_old');
    await createSchema(db, newVersion);
    await db.execute('''
      INSERT INTO recordings (id, name, file_name, local_path, duration_ms, created_at)
      SELECT id, name, file_name, local_path, duration_ms, created_at FROM recordings_old
    ''');
    await db.execute('DROP TABLE recordings_old');
  }

  Future<void> init() async {
    if (_injected != null) {
      _db = _injected;
      return;
    }
    final String dbPath = p.join(await getDatabasesPath(), 'echonote.db');
    _db = await openDatabase(
      dbPath,
      version: schemaVersion,
      onCreate: createSchema,
      onUpgrade: upgradeSchema,
    );
  }

  Database get _database {
    final Database? db = _db;
    if (db == null) {
      throw StateError('RecordingDatabase has not been initialized');
    }
    return db;
  }

  @override
  Future<void> insert(Recording recording) async {
    await _database.insert('recordings', recording.toMap());
  }

  @override
  Future<void> delete(String id) async {
    await _database.delete(
      'recordings',
      where: 'id = ?',
      whereArgs: <Object>[id],
    );
  }

  @override
  Future<Recording?> findById(String id) async {
    final List<Map<String, Object?>> rows = await _database.query(
      'recordings',
      where: 'id = ?',
      whereArgs: <Object>[id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Recording.fromMap(rows.first);
  }

  @override
  Future<List<Recording>> findAllNewestFirst() async {
    final List<Map<String, Object?>> rows = await _database.query(
      'recordings',
      orderBy: 'created_at DESC',
    );
    return rows
        .map((Map<String, Object?> row) => Recording.fromMap(row))
        .toList();
  }

  @override
  Future<void> close() async {
    if (_injected != null) {
      return;
    }
    final Database? db = _db;
    _db = null;
    if (db != null && db.isOpen) {
      await db.close();
    }
  }
}
