import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/sync_models.dart';
import '../models/wp_models.dart';
import 'blog_source_service.dart';
import 'local_database_service.dart';
import 'sync_service.dart';

class SettingsService {
  SettingsService._internal();

  static final SettingsService _instance = SettingsService._internal();

  factory SettingsService() => _instance;

  static const String _themeModeKey = 'theme_mode';
  static const String _fontScaleKey = 'font_scale';
  static const String _readCountKey = 'read_article_count';
  static const String _readPostIdsKey = 'read_post_ids';
  static const String _readPostsDataKey = 'read_posts_data';
  static const String _sqliteMigrationKey =
      'reading_history_sqlite_migrated_v1';

  final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.system);
  final ValueNotifier<double> fontScale = ValueNotifier(1.0);
  final LocalDatabaseService _databaseService = LocalDatabaseService();
  final BlogSourceService _blogSource = BlogSourceService();
  SyncService get _syncService => SyncService();

  int _readCount = 0;
  int get readCount => _readCount;

  Set<String> _readPostKeys = {};
  bool _initialized = false;
  String? _loadedSourceBaseUrl;

  bool get _useSqlite => _databaseService.isSupported;
  String get _currentSourceBaseUrl => _blogSource.baseUrl.value.trim();

  Future<void> init() async {
    final currentSource = _currentSourceBaseUrl;
    if (_initialized && _loadedSourceBaseUrl == currentSource) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt(_themeModeKey) ?? ThemeMode.system.index;
    themeMode.value = ThemeMode.values[themeIndex.clamp(0, 2)];
    fontScale.value = prefs.getDouble(_fontScaleKey) ?? 1.0;

    if (_useSqlite) {
      await _databaseService.init();
      await _migrateSharedPrefsToSqliteIfNeeded();
      await _reloadReadStateFromDatabase();
    } else {
      final readIds = prefs.getStringList(_readPostIdsKey) ?? const [];
      _readPostKeys = readIds.where((item) => item.isNotEmpty).toSet();
      _readCount = _readPostKeys.length;
    }

    _initialized = true;
    _loadedSourceBaseUrl = currentSource;
  }

  Future<void> reload() async {
    _initialized = false;
    _loadedSourceBaseUrl = null;
    await init();
  }

  Future<void> cycleThemeMode() async {
    final nextMode = switch (themeMode.value) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    await setThemeMode(nextMode);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeModeKey, mode.index);
    await _enqueuePreferenceChange();
  }

  Future<void> setFontScale(double scale) async {
    fontScale.value = scale.clamp(0.8, 1.4);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontScaleKey, fontScale.value);
    await _enqueuePreferenceChange();
  }

  Future<void> markAsRead(WpPost post, {double progress = 1.0}) async {
    await init();

    final normalizedProgress = progress.clamp(0.0, 1.0);
    final key = _postKey(post.id, post.sourceBaseUrl);

    if (_useSqlite) {
      final db = await _databaseService.database;
      if (db == null) {
        return;
      }

      final isNewRead = !_readPostKeys.contains(key);
      await db.transaction((txn) async {
        await _upsertReadPostSummary(txn, post);
        await txn.insert(
          LocalDatabaseService.readingHistoryTable,
          {
            'post_id': post.id,
            'source_base_url': post.sourceBaseUrl,
            'last_read_at': DateTime.now().toIso8601String(),
            'progress': normalizedProgress,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });

      _readPostKeys.add(key);
      if (isNewRead) {
        _readCount = _readPostKeys.length;
      }
      await _syncService.enqueueChange(
        SyncChange(
          entityType: 'reading_progress',
          entityId: '${post.sourceBaseUrl}:${post.id}',
          data: {
            'sourceBaseUrl': post.sourceBaseUrl,
            'postId': post.id,
            'progress': normalizedProgress,
            'lastReadAt': DateTime.now().toIso8601String(),
            'updatedAt': DateTime.now().toIso8601String(),
          },
        ),
      );
      return;
    }

    _readPostKeys.add(key);
    _readCount = _readPostKeys.length;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_readCountKey, _readCount);
    await prefs.setStringList(_readPostIdsKey, _readPostKeys.toList());
    await _upsertReadPostSummaryToPrefs(post);
  }

  Future<List<WpPost>> getReadPosts() async {
    await init();

    if (_useSqlite) {
      final db = await _databaseService.database;
      if (db == null) {
        return const [];
      }

      final rows = await db.rawQuery('''
        SELECT
          r.post_id AS id,
          r.source_base_url AS sourceBaseUrl,
          p.title,
          p.excerpt,
          p.author,
          p.published_at AS date,
          p.featured_image_url AS featuredImageUrl,
          p.categories_json AS categoriesJson,
          p.category_ids_json AS categoryIdsJson,
          p.link,
          p.read_minutes AS readMinutes
        FROM ${LocalDatabaseService.readingHistoryTable} r
        LEFT JOIN ${LocalDatabaseService.postsTable} p
          ON p.id = r.post_id
         AND p.source_base_url = r.source_base_url
        ORDER BY r.last_read_at DESC
      ''');

      return rows
          .where((row) => row['title'] != null)
          .map(_readPostRowToPost)
          .toList();
    }

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_readPostsDataKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    try {
      final decoded = json.decode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .where(
            (item) => _readPostKeys.contains(
              _postKey(item['id'] as int, item['sourceBaseUrl'] as String?),
            ),
          )
          .map(WpPost.fromSummaryMap)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await LocalDatabaseService().clearAllData();
    await BlogSourceService().reset();

    themeMode.value = ThemeMode.system;
    fontScale.value = 1.0;
    _readCount = 0;
    _readPostKeys = {};
  }

  Future<void> pruneCachedContent() async {
    await LocalDatabaseService().pruneAllSourcesCache();
  }

  Future<void> clearTransientContentCache() async {
    await LocalDatabaseService().clearTransientContentCache();
  }

  Future<LocalCacheStats> getCacheStats() async {
    return LocalDatabaseService().getCacheStats(_currentSourceBaseUrl);
  }

  Future<void> _reloadReadStateFromDatabase() async {
    final db = await _databaseService.database;
    if (db == null) {
      return;
    }

    final rows = await db.query(
      LocalDatabaseService.readingHistoryTable,
      columns: ['post_id', 'source_base_url'],
    );

    _readPostKeys = rows
        .map(
          (row) => _postKey(
            row['post_id'] as int,
            row['source_base_url'] as String?,
          ),
        )
        .toSet();
    _readCount = _readPostKeys.length;
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

    final readIds = prefs.getStringList(_readPostIdsKey) ?? const [];
    final rawReadPosts = prefs.getString(_readPostsDataKey);
    final readPostMapById = <int, Map<String, dynamic>>{};

    if (rawReadPosts != null && rawReadPosts.isNotEmpty) {
      try {
        final decoded = json.decode(rawReadPosts) as List<dynamic>;
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            final id = item['id'];
            if (id is int) {
              readPostMapById[id] = item;
            }
          }
        }
      } catch (_) {}
    }

    await db.transaction((txn) async {
      for (final id in readIds.map(_parsePostIdFromKey).whereType<int>()) {
        await txn.insert(
          LocalDatabaseService.readingHistoryTable,
          {
            'post_id': id,
            'source_base_url': _currentSourceBaseUrl,
            'last_read_at': DateTime.now().toIso8601String(),
            'progress': 1.0,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );

        final postData = readPostMapById[id];
        if (postData != null) {
          await _upsertReadPostSummary(txn, WpPost.fromSummaryMap(postData));
        }
      }
    });

    await prefs.setBool(_sqliteMigrationKey, true);
  }

  Future<void> _upsertReadPostSummary(DatabaseExecutor db, WpPost post) async {
    await db.insert(
      LocalDatabaseService.postsTable,
      {
        'id': post.id,
        'source_base_url': post.sourceBaseUrl,
        'slug': null,
        'title': post.title,
        'excerpt': post.excerpt,
        'content_html': post.contentHtml,
        'author': post.author,
        'featured_image_url': post.featuredImageUrl,
        'categories_json': json.encode(post.categories),
        'category_ids_json': json.encode(post.categoryIds),
        'link': post.link,
        'read_minutes': post.readMinutes,
        'published_at': post.date.toIso8601String(),
        'modified_at': post.date.toIso8601String(),
        'fetched_at': DateTime.now().toIso8601String(),
        'is_detail_fetched': post.contentHtml.isNotEmpty ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _upsertReadPostSummaryToPrefs(WpPost post) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_readPostsDataKey);
    List<Map<String, dynamic>> items = [];

    if (raw != null && raw.isNotEmpty) {
      try {
        items = (json.decode(raw) as List<dynamic>)
            .whereType<Map<String, dynamic>>()
            .toList();
      } catch (_) {}
    }

    items.removeWhere(
      (item) =>
          item['id'] == post.id &&
          _normalizeSource(item['sourceBaseUrl'] as String?) ==
              post.sourceBaseUrl,
    );
    items.insert(0, post.toSummaryMap());
    await prefs.setString(_readPostsDataKey, json.encode(items));
  }

  WpPost _readPostRowToPost(Map<String, Object?> row) {
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

    return WpPost(
      sourceBaseUrl: (row['sourceBaseUrl'] as String?) ?? _currentSourceBaseUrl,
      id: row['id'] as int,
      title: (row['title'] as String?) ?? 'Untitled',
      excerpt: (row['excerpt'] as String?) ?? '',
      contentHtml: '',
      author: (row['author'] as String?) ?? 'Unknown',
      date: DateTime.tryParse((row['date'] as String?) ?? '') ?? DateTime.now(),
      featuredImageUrl: row['featuredImageUrl'] as String?,
      categories: categories,
      categoryIds: categoryIds,
      link: (row['link'] as String?) ?? '',
      readMinutes: (row['readMinutes'] as int?) ?? 1,
    );
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

  Future<void> _enqueuePreferenceChange() async {
    await _syncService.enqueueChange(
      SyncChange(
        entityType: 'preference',
        data: {
          'themeMode': themeMode.value.name,
          'fontScale': fontScale.value,
          'selectedSourceBaseUrl': _currentSourceBaseUrl,
          'updatedAt': DateTime.now().toIso8601String(),
        },
      ),
    );
  }

  String get themeModeName => switch (themeMode.value) {
    ThemeMode.system => '跟随系统',
    ThemeMode.light => '浅色模式',
    ThemeMode.dark => '深色模式',
  };

  IconData get themeModeIcon => switch (themeMode.value) {
    ThemeMode.system => Icons.brightness_auto_rounded,
    ThemeMode.light => Icons.light_mode_rounded,
    ThemeMode.dark => Icons.dark_mode_rounded,
  };

  String get fontScaleName {
    if (fontScale.value <= 0.85) {
      return '紧凑';
    }
    if (fontScale.value <= 1.05) {
      return '标准';
    }
    if (fontScale.value <= 1.25) {
      return '舒适';
    }
    return '放大';
  }
}
