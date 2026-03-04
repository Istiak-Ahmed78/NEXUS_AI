// lib/data/datasources/local/search_cache_datasource.dart
// ✅ NEW - Cache system for search results

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';

class SearchCacheDataSource {
  static const String _tableName = 'search_cache';
  static const String _dbName = 'ai_search_cache.db';
  static const int _cacheExpiry = 86400; // 24 hours in seconds

  Database? _database;
  static final SearchCacheDataSource _instance =
      SearchCacheDataSource._internal();

  // Singleton pattern
  factory SearchCacheDataSource() {
    return _instance;
  }

  SearchCacheDataSource._internal();

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    try {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, _dbName);

      print('💾 [Cache] Initializing database at: $path');

      return openDatabase(
        path,
        version: 1,
        onCreate: (db, version) async {
          print('💾 [Cache] Creating table: $_tableName');
          await db.execute('''
            CREATE TABLE $_tableName (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              query TEXT UNIQUE NOT NULL,
              results TEXT NOT NULL,
              timestamp INTEGER NOT NULL,
              result_count INTEGER NOT NULL
            )
          ''');
          print('✅ [Cache] Table created successfully');
        },
        onOpen: (db) async {
          print('✅ [Cache] Database opened');
        },
      );
    } catch (e) {
      print('❌ [Cache] Database init error: $e');
      rethrow;
    }
  }

  /// Cache search results
  ///
  /// [query] - The search query
  /// [results] - List of search results to cache
  Future<void> cacheSearchResults(
    String query,
    List<Map<String, dynamic>> results,
  ) async {
    try {
      if (query.trim().isEmpty) {
        print('⚠️ [Cache] Empty query, skipping cache');
        return;
      }

      final db = await database;
      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final resultsJson = jsonEncode(results);

      print('💾 [Cache] Storing: "$query"');
      print('   📊 Results: ${results.length} items');
      print('   📏 JSON size: ${resultsJson.length} bytes');

      await db.insert(_tableName, {
        'query': query.toLowerCase().trim(),
        'results': resultsJson,
        'timestamp': timestamp,
        'result_count': results.length,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      print('✅ [Cache] Stored successfully');
    } catch (e) {
      print('❌ [Cache] Store error: $e');
      // Don't rethrow - cache failures shouldn't break the app
    }
  }

  /// Get cached search results (if not expired)
  ///
  /// [query] - The search query to look up
  /// Returns: List of cached results or null if not found/expired
  Future<List<Map<String, dynamic>>?> getCachedResults(String query) async {
    try {
      if (query.trim().isEmpty) {
        print('⚠️ [Cache] Empty query, skipping lookup');
        return null;
      }

      final db = await database;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final normalizedQuery = query.toLowerCase().trim();

      print('💾 [Cache] Looking up: "$normalizedQuery"');

      final results = await db.query(
        _tableName,
        where: 'query = ? AND (? - timestamp) < ?',
        whereArgs: [normalizedQuery, now, _cacheExpiry],
        limit: 1,
      );

      if (results.isNotEmpty) {
        final cached = results.first;
        final resultsJson = cached['results'] as String;
        final resultCount = cached['result_count'] as int?;

        try {
          final parsed = List<Map<String, dynamic>>.from(
            jsonDecode(resultsJson),
          );

          print('✅ [Cache] HIT: "$normalizedQuery"');
          print('   📊 Results: ${parsed.length} items');
          print('   ⏰ Age: ${now - (cached['timestamp'] as int)} seconds');

          return parsed;
        } catch (e) {
          print('❌ [Cache] JSON decode error: $e');
          // Delete corrupted cache entry
          await db.delete(
            _tableName,
            where: 'query = ?',
            whereArgs: [normalizedQuery],
          );
          return null;
        }
      }

      print('❌ [Cache] MISS: "$normalizedQuery"');
      return null;
    } catch (e) {
      print('❌ [Cache] Retrieve error: $e');
      return null;
    }
  }

  /// Check if a query is cached and valid
  Future<bool> isCached(String query) async {
    try {
      final result = await getCachedResults(query);
      return result != null && result.isNotEmpty;
    } catch (e) {
      print('❌ [Cache] Check error: $e');
      return false;
    }
  }

  /// Get cache statistics
  Future<Map<String, dynamic>> getCacheStats() async {
    try {
      final db = await database;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Total entries
      final totalResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM $_tableName',
      );
      final total = (totalResult.first['count'] as int?) ?? 0;

      // Valid entries (not expired)
      final validResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM $_tableName WHERE (? - timestamp) < ?',
        [now, _cacheExpiry],
      );
      final valid = (validResult.first['count'] as int?) ?? 0;

      // Total results cached
      final resultsResult = await db.rawQuery(
        'SELECT SUM(result_count) as total FROM $_tableName WHERE (? - timestamp) < ?',
        [now, _cacheExpiry],
      );
      final totalResults = (resultsResult.first['total'] as int?) ?? 0;

      return {
        'total_entries': total,
        'valid_entries': valid,
        'expired_entries': total - valid,
        'total_results': totalResults,
        'cache_expiry_hours': _cacheExpiry ~/ 3600,
      };
    } catch (e) {
      print('❌ [Cache] Stats error: $e');
      return {};
    }
  }

  /// Clear expired cache entries
  Future<int> clearExpiredCache() async {
    try {
      final db = await database;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      final deleted = await db.delete(
        _tableName,
        where: '(? - timestamp) >= ?',
        whereArgs: [now, _cacheExpiry],
      );

      if (deleted > 0) {
        print('🧹 [Cache] Cleared $deleted expired entries');
      }

      return deleted;
    } catch (e) {
      print('❌ [Cache] Clear expired error: $e');
      return 0;
    }
  }

  /// Clear all cache
  Future<void> clearAllCache() async {
    try {
      final db = await database;
      await db.delete(_tableName);
      print('🧹 [Cache] Cleared all cache entries');
    } catch (e) {
      print('❌ [Cache] Clear all error: $e');
    }
  }

  /// Delete specific query from cache
  Future<bool> deleteCacheEntry(String query) async {
    try {
      final db = await database;
      final normalizedQuery = query.toLowerCase().trim();

      final deleted = await db.delete(
        _tableName,
        where: 'query = ?',
        whereArgs: [normalizedQuery],
      );

      if (deleted > 0) {
        print('🗑️ [Cache] Deleted entry: "$normalizedQuery"');
        return true;
      }

      return false;
    } catch (e) {
      print('❌ [Cache] Delete error: $e');
      return false;
    }
  }

  /// Close database connection
  Future<void> close() async {
    try {
      final db = _database;
      if (db != null) {
        await db.close();
        _database = null;
        print('🔌 [Cache] Database closed');
      }
    } catch (e) {
      print('❌ [Cache] Close error: $e');
    }
  }

  /// Dispose resources (cleanup)
  Future<void> dispose() async {
    await close();
  }
}
