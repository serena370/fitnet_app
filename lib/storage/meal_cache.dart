import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/meal.dart';

/// SQLite local cache of meal summaries (course topic: local database).
///
/// Firestore stays the source of truth. This cache is a best-effort,
/// read-through mirror: it is refreshed whenever a Firestore meal snapshot
/// arrives and is only read back when Firestore is unreachable, so the
/// Meals page can still show recent history offline. Cache writes must
/// never block or fail a Firestore operation.
class MealCache {
  MealCache._();

  static final MealCache instance = MealCache._();

  static const String _tableName = 'meal_summaries';

  Database? _database;

  Future<Database> _open() async {
    final existing = _database;
    if (existing != null) return existing;

    final databasesPath = await getDatabasesPath();
    final database = await openDatabase(
      p.join(databasesPath, 'fitnet_meal_cache.db'),
      version: 1,
      onCreate: (db, version) {
        return db.execute('''
          CREATE TABLE $_tableName(
            id TEXT PRIMARY KEY,
            userId TEXT NOT NULL,
            name TEXT NOT NULL,
            mealType TEXT NOT NULL,
            calories INTEGER NOT NULL,
            dateMillis INTEGER NOT NULL,
            notes TEXT NOT NULL,
            source TEXT NOT NULL
          )
        ''');
      },
    );
    _database = database;
    return database;
  }

  /// Mirrors the latest Firestore meal list. Best-effort: any failure is
  /// logged in debug mode and otherwise ignored.
  Future<void> replaceAll(String userId, List<Meal> meals) async {
    try {
      final db = await _open();
      final batch = db.batch();
      batch.delete(_tableName, where: 'userId = ?', whereArgs: [userId]);
      for (final meal in meals) {
        batch.insert(_tableName, {
          'id': meal.id,
          'userId': meal.userId,
          'name': meal.name,
          'mealType': meal.mealType,
          'calories': meal.calories,
          'dateMillis': meal.date.millisecondsSinceEpoch,
          'notes': meal.notes,
          'source': meal.source,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    } catch (error) {
      if (kDebugMode) debugPrint('Meal cache write skipped: $error');
    }
  }

  /// Reads cached meal summaries, newest first. Returns an empty list when
  /// the cache is unavailable (e.g. unsupported platform in tests).
  Future<List<Meal>> readAll(String userId) async {
    try {
      final db = await _open();
      final rows = await db.query(
        _tableName,
        where: 'userId = ?',
        whereArgs: [userId],
        orderBy: 'dateMillis DESC',
      );
      return rows.map((row) {
        return Meal(
          id: row['id'] as String,
          userId: row['userId'] as String,
          name: row['name'] as String,
          mealType: row['mealType'] as String,
          calories: row['calories'] as int,
          date: DateTime.fromMillisecondsSinceEpoch(row['dateMillis'] as int),
          notes: row['notes'] as String,
          source: row['source'] as String,
        );
      }).toList();
    } catch (error) {
      if (kDebugMode) debugPrint('Meal cache read skipped: $error');
      return const [];
    }
  }
}
