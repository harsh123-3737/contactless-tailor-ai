import 'dart:async';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('tailor_scans.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    // Creates the database file on the Android device
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
    CREATE TABLE scans (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      scan_id TEXT NOT NULL,
      recommended_size TEXT NOT NULL,
      image_path TEXT NOT NULL,
      measurements_json TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
    ''');
  }

  Future<int> insertScan(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('scans', row);
  }

  Future<List<Map<String, dynamic>>> readAllScans() async {
    final db = await instance.database;
    return await db.query('scans', orderBy: 'created_at DESC');
  }

  Future<int> deleteScan(String id) async {
    final db = await DatabaseHelper.instance.database;
    return await db.delete('scans', where: 'scan_id = ?', whereArgs: [id]);
  }
}
