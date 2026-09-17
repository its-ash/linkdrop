import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/download_item.dart';

class DatabaseService {
  DatabaseService._();

  static final DatabaseService instance = DatabaseService._();

  Database? _db;

  Future<Database> get _database async => _db ??= await _open();

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'linkdrop.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) => db.execute('''
        CREATE TABLE downloads (
          id TEXT PRIMARY KEY,
          url TEXT NOT NULL,
          fileName TEXT NOT NULL,
          filePath TEXT NOT NULL,
          status TEXT NOT NULL,
          createdAt TEXT NOT NULL,
          mimeType TEXT,
          totalBytes INTEGER NOT NULL DEFAULT 0,
          receivedBytes INTEGER NOT NULL DEFAULT 0,
          errorMessage TEXT
        )
      '''),
    );
  }

  Future<void> upsert(DownloadItem item) async {
    final db = await _database;
    await db.insert(
      'downloads',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String id) async {
    final db = await _database;
    await db.delete('downloads', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<DownloadItem>> all() async {
    final db = await _database;
    final rows = await db.query('downloads', orderBy: 'createdAt DESC');
    return rows.map(DownloadItem.fromMap).toList();
  }
}
