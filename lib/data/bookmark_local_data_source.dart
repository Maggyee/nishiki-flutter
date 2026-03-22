import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../services/blog_source_service.dart';
import '../services/local_database_service.dart';

class BookmarkLocalDataSource {
  static final BookmarkLocalDataSource _instance = BookmarkLocalDataSource._internal();

  factory BookmarkLocalDataSource() => _instance;

  BookmarkLocalDataSource._internal();

  static const String _likedKey = 'liked_post_ids';
  static const String _savedKey = 'saved_post_ids';
  static const String _likedPostsKey = 'liked_posts_data';
  static const String _savedPostsKey = 'saved_posts_data';
  static const String _sqliteMigrationKey = 'bookmark_sqlite_migrated_v1';

  final LocalDatabaseService _databaseService = LocalDatabaseService();
  final BlogSourceService _blogSource = BlogSourceService();

  Set<String> _likedKeys = {};
  Set<String> _savedKeys = {};
  bool _initialized = false;
  String? _loadedSourceBaseUrl;

  bool get _useSqlite => _databaseService.isSupported;
  String get _currentSourceBaseUrl => _blogSource.baseUrl.value.trim();

  Future<void> init() async {
    final currentSource = _currentSourceBaseUrl;
    if (_initialized && _loadedSourceBaseUrl == currentSource) {
      return;
    }

    if (_useSqlite) {
      await _databaseService.init();
      await _migrateSharedPrefsToSqliteIfNeeded();
      await _reloadIdsFromDatabase();
    } else {
      await _loadFromPrefs();
    }

    _initialized = true;
    _loadedSourceBaseUrl = currentSource;
  }

  bool isLiked(int postId, {String? sourceBaseUrl}) =>
      _likedKeys.contains(_postKey(postId, sourceBaseUrl));

  Future<bool> toggleLike(
    int postId, {
    String? sourceBaseUrl,
    Map<String, dynamic>? postData,
  }) async {
    await init();
    final resolvedSource = _normalizeSource(sourceBaseUrl);
    final key = _postKey(postId, resolvedSource);

    if (_useSqlite) {
      final db = await _databaseService.database;
      if (db == null) {
        return false;
      }

      if (_likedKeys.contains(key)) {
        await db.delete(
          LocalDatabaseService.likedPostsTable,
          where: 'post_id = ? AND source_base_url = ?',
          whereArgs: [postId, resolvedSource],
        );
        _likedKeys.remove(key);
      } else {
        await db.insert(
          LocalDatabaseService.likedPostsTable,
          {
            'post_id': postId,
            'source_base_url': resolvedSource,
            'liked_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        _likedKeys.add(key);
        if (postData != null) {
          await _upsertSavedPostSummary(db, postId, postData, resolvedSource);
        }
      }

      return _likedKeys.contains(key);
    }

    if (_likedKeys.contains(key)) {
      _likedKeys.remove(key);
      await _removeLikedPostDataFromPrefs(postId, resolvedSource);
    } else {
      _likedKeys.add(key);
      if (postData != null) {
        await _addLikedPostDataToPrefs(postId, postData, resolvedSource);
      }
    }
    await _saveLikedIdsToPrefs();
    return _likedKeys.contains(key);
  }

  int get likedCount => _likedKeys.length;

  Future<List<Map<String, dynamic>>> getLikedPostsData() async {
    await init();

    if (_useSqlite) {
      final db = await _databaseService.database;
      if (db == null) {
        return [];
      }

      final rows = await db.rawQuery('''
        SELECT
          l.post_id AS id,
          l.source_base_url AS sourceBaseUrl,
          p.title,
          p.excerpt,
          p.author,
          p.published_at AS date,
          p.featured_image_url AS featuredImageUrl,
          p.categories_json AS categoriesJson,
          p.category_ids_json AS categoryIdsJson,
          p.link,
          p.read_minutes AS readMinutes
        FROM ${LocalDatabaseService.likedPostsTable} l
        LEFT JOIN ${LocalDatabaseService.postsTable} p
          ON p.id = l.post_id
         AND p.source_base_url = l.source_base_url
        ORDER BY l.liked_at DESC
      ''');

      return rows
          .where((row) => row['title'] != null)
          .map(_savedPostRowToMap)
          .toList();
    }

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_likedPostsKey);
    if (raw == null) {
      return [];
    }

    try {
      final List<dynamic> list = json.decode(raw);
      return list
          .cast<Map<String, dynamic>>()
          .where(
            (item) => _likedKeys.contains(
              _postKey(item['id'] as int, item['sourceBaseUrl'] as String?),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  bool isSaved(int postId, {String? sourceBaseUrl}) =>
      _savedKeys.contains(_postKey(postId, sourceBaseUrl));

  Future<bool> toggleSave(
    int postId, {
    String? sourceBaseUrl,
    Map<String, dynamic>? postData,
  }) async {
    await init();
    final resolvedSource = _normalizeSource(sourceBaseUrl);
    final key = _postKey(postId, resolvedSource);

    if (_useSqlite) {
      final db = await _databaseService.database;
      if (db == null) {
        return false;
      }

      if (_savedKeys.contains(key)) {
        await db.delete(
          LocalDatabaseService.savedPostsTable,
          where: 'post_id = ? AND source_base_url = ?',
          whereArgs: [postId, resolvedSource],
        );
        _savedKeys.remove(key);
      } else {
        await db.insert(
          LocalDatabaseService.savedPostsTable,
          {
            'post_id': postId,
            'source_base_url': resolvedSource,
            'saved_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        _savedKeys.add(key);
        if (postData != null) {
          await _upsertSavedPostSummary(db, postId, postData, resolvedSource);
        }
      }

      return _savedKeys.contains(key);
    }

    if (_savedKeys.contains(key)) {
      _savedKeys.remove(key);
      await _removeSavedPostDataFromPrefs(postId, resolvedSource);
    } else {
      _savedKeys.add(key);
      if (postData != null) {
        await _addSavedPostDataToPrefs(postId, postData, resolvedSource);
      }
    }
    await _saveSavedIdsToPrefs();
    return _savedKeys.contains(key);
  }

  Set<int> get savedPostIds => Set.unmodifiable(
    _savedKeys.map(_parsePostIdFromKey).whereType<int>().toSet(),
  );

  Future<List<Map<String, dynamic>>> getSavedPostsData() async {
    await init();

    if (_useSqlite) {
      final db = await _databaseService.database;
      if (db == null) {
        return [];
      }

      final rows = await db.rawQuery('''
        SELECT
          s.post_id AS id,
          s.source_base_url AS sourceBaseUrl,
          p.title,
          p.excerpt,
          p.author,
          p.published_at AS date,
          p.featured_image_url AS featuredImageUrl,
          p.categories_json AS categoriesJson,
          p.category_ids_json AS categoryIdsJson,
          p.link,
          p.read_minutes AS readMinutes
        FROM ${LocalDatabaseService.savedPostsTable} s
        LEFT JOIN ${LocalDatabaseService.postsTable} p
          ON p.id = s.post_id
         AND p.source_base_url = s.source_base_url
        ORDER BY s.saved_at DESC
      ''');

      return rows
          .where((row) => row['title'] != null)
          .map(_savedPostRowToMap)
          .toList();
    }

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_savedPostsKey);
    if (raw == null) {
      return [];
    }

    try {
      final List<dynamic> list = json.decode(raw);
      return list
          .cast<Map<String, dynamic>>()
          .where(
            (item) => _savedKeys.contains(
              _postKey(item['id'] as int, item['sourceBaseUrl'] as String?),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  int get savedCount => _savedKeys.length;

  Future<void> clearAll() async {
    await init();

    if (_useSqlite) {
      final db = await _databaseService.database;
      if (db != null) {
        await db.delete(LocalDatabaseService.savedPostsTable);
        await db.delete(LocalDatabaseService.likedPostsTable);
      }
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_savedKey);
      await prefs.remove(_likedKey);
      await prefs.remove(_likedPostsKey);
      await prefs.remove(_savedPostsKey);
    }

    _savedKeys = {};
    _likedKeys = {};
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final likedList = prefs.getStringList(_likedKey) ?? [];
    final savedList = prefs.getStringList(_savedKey) ?? [];

    _likedKeys = likedList.where((item) => item.isNotEmpty).toSet();
    _savedKeys = savedList.where((item) => item.isNotEmpty).toSet();
  }

  Future<void> _reloadIdsFromDatabase() async {
    final db = await _databaseService.database;
    if (db == null) {
      return;
    }

    final likedRows = await db.query(
      LocalDatabaseService.likedPostsTable,
      columns: ['post_id', 'source_base_url'],
    );
    final savedRows = await db.query(
      LocalDatabaseService.savedPostsTable,
      columns: ['post_id', 'source_base_url'],
    );

    _likedKeys = likedRows
        .map(
          (row) => _postKey(
            row['post_id'] as int,
            row['source_base_url'] as String?,
          ),
        )
        .toSet();
    _savedKeys = savedRows
        .map(
          (row) => _postKey(
            row['post_id'] as int,
            row['source_base_url'] as String?,
          ),
        )
        .toSet();
  }

  Future<void> _migrateSharedPrefsToSqliteIfNeeded() async {
    if (!_useSqlite) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final alreadyMigrated = prefs.getBool(_sqliteMigrationKey) ?? false;
    if (alreadyMigrated) {
      return;
    }

    final db = await _databaseService.database;
    if (db == null) {
      return;
    }

    final likedList = prefs.getStringList(_likedKey) ?? const [];
    final savedList = prefs.getStringList(_savedKey) ?? const [];
    final rawLikedPosts = prefs.getString(_likedPostsKey);
    final rawSavedPosts = prefs.getString(_savedPostsKey);

    final likedPostMapById = <int, Map<String, dynamic>>{};
    if (rawLikedPosts != null) {
      try {
        final decoded = json.decode(rawLikedPosts) as List<dynamic>;
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            final id = item['id'];
            if (id is int) {
              likedPostMapById[id] = item;
            }
          }
        }
      } catch (_) {}
    }

    final savedPostMapById = <int, Map<String, dynamic>>{};
    if (rawSavedPosts != null) {
      try {
        final decoded = json.decode(rawSavedPosts) as List<dynamic>;
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            final id = item['id'];
            if (id is int) {
              savedPostMapById[id] = item;
            }
          }
        }
      } catch (_) {}
    }

    await db.transaction((txn) async {
      for (final id in likedList.map(_parsePostIdFromKey).whereType<int>()) {
        await txn.insert(
          LocalDatabaseService.likedPostsTable,
          {
            'post_id': id,
            'source_base_url': _currentSourceBaseUrl,
            'liked_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );

        final postData = likedPostMapById[id];
        if (postData != null) {
          await _upsertSavedPostSummary(
            txn,
            id,
            postData,
            _currentSourceBaseUrl,
          );
        }
      }

      for (final id in savedList.map(_parsePostIdFromKey).whereType<int>()) {
        await txn.insert(
          LocalDatabaseService.savedPostsTable,
          {
            'post_id': id,
            'source_base_url': _currentSourceBaseUrl,
            'saved_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );

        final postData = savedPostMapById[id];
        if (postData != null) {
          await _upsertSavedPostSummary(
            txn,
            id,
            postData,
            _currentSourceBaseUrl,
          );
        }
      }
    });

    await prefs.setBool(_sqliteMigrationKey, true);
  }

  Future<void> _saveLikedIdsToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_likedKey, _likedKeys.toList());
  }

  Future<void> _saveSavedIdsToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_savedKey, _savedKeys.toList());
  }

  Future<void> _addSavedPostDataToPrefs(
    int postId,
    Map<String, dynamic> postData,
    String sourceBaseUrl,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_savedPostsKey);
    List<Map<String, dynamic>> list = [];

    if (raw != null) {
      try {
        list = (json.decode(raw) as List).cast<Map<String, dynamic>>();
      } catch (_) {}
    }

    list.removeWhere(
      (item) =>
          item['id'] == postId &&
          _normalizeSource(item['sourceBaseUrl'] as String?) == sourceBaseUrl,
    );
    list.insert(0, {...postData, 'sourceBaseUrl': sourceBaseUrl});

    await prefs.setString(_savedPostsKey, json.encode(list));
  }

  Future<void> _addLikedPostDataToPrefs(
    int postId,
    Map<String, dynamic> postData,
    String sourceBaseUrl,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_likedPostsKey);
    List<Map<String, dynamic>> list = [];

    if (raw != null) {
      try {
        list = (json.decode(raw) as List).cast<Map<String, dynamic>>();
      } catch (_) {}
    }

    list.removeWhere(
      (item) =>
          item['id'] == postId &&
          _normalizeSource(item['sourceBaseUrl'] as String?) == sourceBaseUrl,
    );
    list.insert(0, {...postData, 'sourceBaseUrl': sourceBaseUrl});

    await prefs.setString(_likedPostsKey, json.encode(list));
  }

  Future<void> _removeSavedPostDataFromPrefs(
    int postId,
    String sourceBaseUrl,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_savedPostsKey);
    if (raw == null) {
      return;
    }

    try {
      final list = (json.decode(raw) as List).cast<Map<String, dynamic>>();
      list.removeWhere(
        (item) =>
            item['id'] == postId &&
            _normalizeSource(item['sourceBaseUrl'] as String?) == sourceBaseUrl,
      );
      await prefs.setString(_savedPostsKey, json.encode(list));
    } catch (_) {}
  }

  Future<void> _removeLikedPostDataFromPrefs(
    int postId,
    String sourceBaseUrl,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_likedPostsKey);
    if (raw == null) {
      return;
    }

    try {
      final list = (json.decode(raw) as List).cast<Map<String, dynamic>>();
      list.removeWhere(
        (item) =>
            item['id'] == postId &&
            _normalizeSource(item['sourceBaseUrl'] as String?) == sourceBaseUrl,
      );
      await prefs.setString(_likedPostsKey, json.encode(list));
    } catch (_) {}
  }

  Future<void> _upsertSavedPostSummary(
    DatabaseExecutor db,
    int postId,
    Map<String, dynamic> postData,
    String sourceBaseUrl,
  ) async {
    final categories = ((postData['categories'] as List<dynamic>?) ?? const [])
        .map((item) => item.toString())
        .toList();
    final categoryIds =
        ((postData['categoryIds'] as List<dynamic>?) ?? const [])
            .whereType<int>()
            .toList();

    await db.insert(
      LocalDatabaseService.postsTable,
      {
        'id': postId,
        'source_base_url': sourceBaseUrl,
        'slug': null,
        'title': (postData['title'] as String?) ?? 'Untitled',
        'excerpt': (postData['excerpt'] as String?) ?? '',
        'content_html': '',
        'author': (postData['author'] as String?) ?? 'Unknown',
        'featured_image_url': postData['featuredImageUrl'] as String?,
        'categories_json': json.encode(categories),
        'category_ids_json': json.encode(categoryIds),
        'link': (postData['link'] as String?) ?? '',
        'read_minutes': (postData['readMinutes'] as int?) ?? 1,
        'published_at':
            (postData['date'] as String?) ?? DateTime.now().toIso8601String(),
        'modified_at':
            (postData['date'] as String?) ?? DateTime.now().toIso8601String(),
        'fetched_at': DateTime.now().toIso8601String(),
        'is_detail_fetched': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Map<String, dynamic> _savedPostRowToMap(Map<String, Object?> row) {
    List<String> categories = const [];
    final categoriesRaw = row['categoriesJson'] as String?;
    if (categoriesRaw != null && categoriesRaw.isNotEmpty) {
      try {
        categories = (json.decode(categoriesRaw) as List<dynamic>)
            .map((item) => item.toString())
            .toList();
      } catch (_) {}
    }

    List<int> categoryIds = const [];
    final categoryIdsRaw = row['categoryIdsJson'] as String?;
    if (categoryIdsRaw != null && categoryIdsRaw.isNotEmpty) {
      try {
        categoryIds = (json.decode(categoryIdsRaw) as List<dynamic>)
            .whereType<int>()
            .toList();
      } catch (_) {}
    }

    return {
      'id': row['id'] as int,
      'title': (row['title'] as String?) ?? 'Untitled',
      'excerpt': (row['excerpt'] as String?) ?? '',
      'author': (row['author'] as String?) ?? 'Unknown',
      'date': (row['date'] as String?) ?? DateTime.now().toIso8601String(),
      'featuredImageUrl': row['featuredImageUrl'] as String?,
      'categories': categories,
      'categoryIds': categoryIds,
      'link': (row['link'] as String?) ?? '',
      'readMinutes': (row['readMinutes'] as int?) ?? 1,
      'sourceBaseUrl':
          (row['sourceBaseUrl'] as String?) ?? _currentSourceBaseUrl,
    };
  }

  String _normalizeSource(String? sourceBaseUrl) =>
      ((sourceBaseUrl == null || sourceBaseUrl.trim().isEmpty)
              ? _currentSourceBaseUrl
              : sourceBaseUrl)
          .trim();

  String _postKey(int postId, [String? sourceBaseUrl]) =>
      '${_normalizeSource(sourceBaseUrl)}::$postId';

  int? _parsePostIdFromKey(String key) {
    final separatorIndex = key.lastIndexOf('::');
    if (separatorIndex == -1 || separatorIndex == key.length - 2) {
      return int.tryParse(key);
    }
    return int.tryParse(key.substring(separatorIndex + 2));
  }
}
