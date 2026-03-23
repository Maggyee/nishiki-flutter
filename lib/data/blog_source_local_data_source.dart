// 博客站点的本地数据源 — 负责 SQLite 和 SharedPreferences 的读写操作
//
// 仿照 BookmarkLocalDataSource 的三层架构模式：
// Service → (Repository) → DataSource
// 本层负责直接与 SQLite 和 SharedPreferences 交互

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../config.dart';
import '../models/blog_source_models.dart';
import '../services/local_database_service.dart';

class BlogSourceLocalDataSource {
  BlogSourceLocalDataSource({required LocalDatabaseService databaseService})
      : _databaseService = databaseService;

  final LocalDatabaseService _databaseService;

  // ===== SharedPreferences 键名常量 =====
  static const String legacyWordpressBaseUrlKey = 'wordpress_base_url';
  static const String selectedWordpressSourceKey = 'selected_wordpress_source';
  static const String wordpressSourceModeKey = 'wordpress_source_mode';
  static const String selectedWordpressGroupKey = 'selected_wordpress_group';
  static const String legacyWordpressSourcesKey = 'wordpress_sources';
  static const String fallbackWordpressSourceEntriesKey =
      'wordpress_source_entries_v2';
  static const String fallbackWordpressGroupsKey = 'wordpress_groups_v2';

  /// 是否使用 SQLite 存储（某些平台不支持 sqflite）
  bool get useSqlite => _databaseService.isSupported;

  // ==================== SQLite 操作 ====================

  /// 从 SQLite 加载所有站点和组合
  Future<({List<BlogSiteSource> sources, List<BlogSiteGroup> groups})>
      loadFromDatabase() async {
    final db = await _databaseService.database;
    if (db == null) {
      return (sources: const <BlogSiteSource>[], groups: const <BlogSiteGroup>[]);
    }

    // 查询站点
    final sourceRows = await db.query(
      LocalDatabaseService.siteSourcesTable,
      orderBy: 'name COLLATE NOCASE ASC',
    );
    // 查询组合
    final groupRows = await db.query(
      LocalDatabaseService.siteGroupsTable,
      orderBy: 'name COLLATE NOCASE ASC',
    );
    // 查询组合成员关系
    final memberRows = await db.query(
      LocalDatabaseService.siteGroupMembersTable,
      orderBy: 'group_id ASC, sort_order ASC',
    );

    // 解析站点
    final loadedSources = sourceRows
        .map((row) => BlogSiteSource.fromRow(row))
        .toList();

    // 构建组合 ↔ 站点的映射关系
    final membersByGroup = <String, List<String>>{};
    for (final row in memberRows) {
      final groupId = row['group_id'] as String?;
      final sourceBaseUrl = row['source_base_url'] as String?;
      if (groupId == null || sourceBaseUrl == null) continue;
      membersByGroup.putIfAbsent(groupId, () => <String>[]).add(sourceBaseUrl);
    }

    // 解析组合
    final loadedGroups = groupRows
        .map(
          (row) => BlogSiteGroup(
            id: row['id'] as String,
            name: (row['name'] as String?) ?? '未命名组合',
            sourceBaseUrls: List.unmodifiable(
              membersByGroup[row['id'] as String] ?? const [],
            ),
            createdAt:
                DateTime.tryParse((row['created_at'] as String?) ?? '') ??
                DateTime.now(),
            updatedAt:
                DateTime.tryParse((row['updated_at'] as String?) ?? '') ??
                DateTime.now(),
          ),
        )
        .where((group) => group.sourceBaseUrls.isNotEmpty)
        .toList();

    return (sources: loadedSources, groups: loadedGroups);
  }

  /// 插入或更新站点记录
  Future<void> upsertSourceInDb(String baseUrl, String name) async {
    final db = await _databaseService.database;
    if (db == null) return;

    final now = DateTime.now();
    final existing = await db.query(
      LocalDatabaseService.siteSourcesTable,
      columns: ['created_at', 'name'],
      where: 'base_url = ?',
      whereArgs: [baseUrl],
      limit: 1,
    );

    await db.insert(
      LocalDatabaseService.siteSourcesTable,
      {
        'base_url': baseUrl,
        'name': existing.isNotEmpty
            ? ((existing.first['name'] as String?)?.trim().isNotEmpty ?? false)
                  ? existing.first['name']
                  : name
            : name,
        'created_at': existing.isNotEmpty
            ? existing.first['created_at'] as String
            : now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 重命名站点
  Future<void> renameSourceInDb(String baseUrl, String name) async {
    final db = await _databaseService.database;
    if (db == null) return;

    await db.update(
      LocalDatabaseService.siteSourcesTable,
      {'name': name, 'updated_at': DateTime.now().toIso8601String()},
      where: 'base_url = ?',
      whereArgs: [baseUrl],
    );
  }

  /// 删除站点记录
  Future<void> deleteSourceInDb(String baseUrl) async {
    final db = await _databaseService.database;
    if (db == null) return;

    await db.delete(
      LocalDatabaseService.siteSourcesTable,
      where: 'base_url = ?',
      whereArgs: [baseUrl],
    );
  }

  /// 保存站点组合（事务操作：先写组合信息，再写成员关系）
  Future<void> saveGroupInDb({
    required String groupId,
    required String name,
    required List<String> sourceBaseUrls,
  }) async {
    final db = await _databaseService.database;
    if (db == null) return;
    final now = DateTime.now();

    await db.transaction((txn) async {
      final existing = await txn.query(
        LocalDatabaseService.siteGroupsTable,
        columns: ['created_at'],
        where: 'id = ?',
        whereArgs: [groupId],
        limit: 1,
      );

      await txn.insert(
        LocalDatabaseService.siteGroupsTable,
        {
          'id': groupId,
          'name': name,
          'created_at': existing.isNotEmpty
              ? existing.first['created_at'] as String
              : now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 先清空旧成员，再插入新成员
      await txn.delete(
        LocalDatabaseService.siteGroupMembersTable,
        where: 'group_id = ?',
        whereArgs: [groupId],
      );

      for (int index = 0; index < sourceBaseUrls.length; index++) {
        await txn.insert(
          LocalDatabaseService.siteGroupMembersTable,
          {
            'group_id': groupId,
            'source_base_url': sourceBaseUrls[index],
            'sort_order': index,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  /// 删除组合
  Future<void> deleteGroupInDb(String id) async {
    final db = await _databaseService.database;
    if (db == null) return;

    await db.delete(
      LocalDatabaseService.siteGroupsTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 重置数据库中所有站点和组合，恢复默认站点
  Future<void> resetDatabase(String defaultSource, String defaultName) async {
    final db = await _databaseService.database;
    if (db == null) return;
    final now = DateTime.now();

    await db.transaction((txn) async {
      await txn.delete(LocalDatabaseService.siteGroupMembersTable);
      await txn.delete(LocalDatabaseService.siteGroupsTable);
      await txn.delete(LocalDatabaseService.siteSourcesTable);
      await txn.insert(
        LocalDatabaseService.siteSourcesTable,
        {
          'base_url': defaultSource,
          'name': defaultName,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  /// 迁移旧版 SharedPreferences 数据到 SQLite
  Future<void> migrateLegacyPrefsToSqliteIfNeeded(
    SharedPreferences prefs,
  ) async {
    final db = await _databaseService.database;
    if (db == null) return;

    // 如果 SQLite 已有数据，则跳过迁移
    final existingRows = await db.query(
      LocalDatabaseService.siteSourcesTable,
      columns: ['base_url'],
      limit: 1,
    );
    if (existingRows.isNotEmpty) return;

    final now = DateTime.now();
    final legacySources = readLegacySourceUrls(prefs);
    final fallbackSources = readFallbackSourceEntries(prefs);

    // 优先使用 v2 fallback 数据，其次使用旧版 URL 列表
    final seedSources = fallbackSources.isNotEmpty
        ? fallbackSources
        : legacySources
              .map(
                (url) => BlogSiteSource(
                  baseUrl: url,
                  name: defaultSourceName(url),
                  createdAt: now,
                  updatedAt: now,
                ),
              )
              .toList();

    final sourcesToInsert = seedSources.isNotEmpty
        ? seedSources
        : <BlogSiteSource>[
            BlogSiteSource(
              baseUrl: normalizeUrl(AppConfig.wordpressBaseUrl.trim()),
              name: defaultSourceName(AppConfig.wordpressBaseUrl.trim()),
              createdAt: now,
              updatedAt: now,
            ),
          ];

    final fallbackGroups = readFallbackGroups(prefs);

    await db.transaction((txn) async {
      for (final source in sourcesToInsert) {
        await txn.insert(
          LocalDatabaseService.siteSourcesTable,
          {
            'base_url': source.baseUrl,
            'name': source.name,
            'created_at': source.createdAt.toIso8601String(),
            'updated_at': source.updatedAt.toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      for (final group in fallbackGroups) {
        await txn.insert(
          LocalDatabaseService.siteGroupsTable,
          {
            'id': group.id,
            'name': group.name,
            'created_at': group.createdAt.toIso8601String(),
            'updated_at': group.updatedAt.toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        for (int index = 0; index < group.sourceBaseUrls.length; index++) {
          await txn.insert(
            LocalDatabaseService.siteGroupMembersTable,
            {
              'group_id': group.id,
              'source_base_url': group.sourceBaseUrls[index],
              'sort_order': index,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
  }

  // ==================== SharedPreferences 回退存储 ====================

  /// 持久化选择状态到 SharedPreferences
  Future<void> persistSelectionState(
    SharedPreferences prefs, {
    required String baseUrl,
    required BlogSourceMode mode,
    required String? groupId,
  }) async {
    await prefs.setString(selectedWordpressSourceKey, baseUrl);
    await prefs.setString(legacyWordpressBaseUrlKey, baseUrl);
    await prefs.setString(
      wordpressSourceModeKey,
      mode == BlogSourceMode.aggregate ? 'aggregate' : 'single',
    );

    if (groupId == null || groupId.isEmpty) {
      await prefs.remove(selectedWordpressGroupKey);
    } else {
      await prefs.setString(selectedWordpressGroupKey, groupId);
    }
  }

  /// 持久化站点和组合列表到 SharedPreferences（作为 SQLite 不可用时的回退）
  Future<void> persistFallbackCollections(
    SharedPreferences prefs, {
    required List<BlogSiteSource> sources,
    required List<BlogSiteGroup> groups,
  }) async {
    await prefs.setString(
      fallbackWordpressSourceEntriesKey,
      json.encode(sources.map((item) => item.toJson()).toList()),
    );
    await prefs.setString(
      fallbackWordpressGroupsKey,
      json.encode(groups.map((item) => item.toJson()).toList()),
    );
    await prefs.setString(
      legacyWordpressSourcesKey,
      json.encode(sources.map((item) => item.baseUrl).toList()),
    );
  }

  /// 从 SharedPreferences 加载回退数据
  Future<({List<BlogSiteSource> sources, List<BlogSiteGroup> groups})>
      loadFallbackFromPrefs(SharedPreferences prefs) async {
    final fallbackSources = readFallbackSourceEntries(prefs);
    final fallbackGroups = readFallbackGroups(prefs);
    final legacySources = readLegacySourceUrls(prefs);
    final now = DateTime.now();

    final loadedSources = fallbackSources.isNotEmpty
        ? fallbackSources
        : legacySources
              .map(
                (url) => BlogSiteSource(
                  baseUrl: url,
                  name: defaultSourceName(url),
                  createdAt: now,
                  updatedAt: now,
                ),
              )
              .toList();

    final effectiveSources = loadedSources.isNotEmpty
        ? loadedSources
        : <BlogSiteSource>[
            BlogSiteSource(
              baseUrl: normalizeUrl(AppConfig.wordpressBaseUrl.trim()),
              name: defaultSourceName(AppConfig.wordpressBaseUrl.trim()),
              createdAt: now,
              updatedAt: now,
            ),
          ];

    return (sources: effectiveSources, groups: fallbackGroups);
  }

  /// 恢复用户上次的选择状态
  ({String baseUrl, BlogSourceMode mode, String? groupId})
      restoreSelectionState(
    SharedPreferences prefs, {
    required List<String> knownSources,
    required List<BlogSiteGroup> knownGroups,
  }) {
    final fallbackSource = knownSources.isNotEmpty
        ? knownSources.first
        : normalizeUrl(AppConfig.wordpressBaseUrl.trim());

    final selectedSource =
        _normalizeIfValid(prefs.getString(selectedWordpressSourceKey)) ??
        _normalizeIfValid(prefs.getString(legacyWordpressBaseUrlKey)) ??
        fallbackSource;

    final storedMode = prefs.getString(wordpressSourceModeKey);
    final selectedGroup = prefs.getString(selectedWordpressGroupKey);

    return (
      baseUrl: knownSources.contains(selectedSource)
          ? selectedSource
          : fallbackSource,
      mode: storedMode == 'aggregate'
          ? BlogSourceMode.aggregate
          : BlogSourceMode.single,
      groupId: knownGroups.any((group) => group.id == selectedGroup)
          ? selectedGroup
          : null,
    );
  }

  /// 清除所有 SharedPreferences 中的站点相关数据
  Future<void> clearAllPrefs(SharedPreferences prefs) async {
    await prefs.remove(legacyWordpressBaseUrlKey);
    await prefs.remove(legacyWordpressSourcesKey);
    await prefs.remove(selectedWordpressSourceKey);
    await prefs.remove(wordpressSourceModeKey);
    await prefs.remove(selectedWordpressGroupKey);
    await prefs.remove(fallbackWordpressSourceEntriesKey);
    await prefs.remove(fallbackWordpressGroupsKey);
  }

  // ==================== 辅助方法 ====================

  /// 读取旧版站点 URL 列表
  List<String> readLegacySourceUrls(SharedPreferences prefs) {
    final raw = prefs.getString(legacyWordpressSourcesKey);
    if (raw == null || raw.isEmpty) {
      final legacySingle = _normalizeIfValid(
        prefs.getString(legacyWordpressBaseUrlKey),
      );
      return legacySingle == null
          ? <String>[normalizeUrl(AppConfig.wordpressBaseUrl.trim())]
          : <String>[legacySingle];
    }

    try {
      final decoded = json.decode(raw) as List<dynamic>;
      final items = decoded
          .whereType<String>()
          .map(_normalizeIfValid)
          .whereType<String>()
          .toSet()
          .toList();
      if (items.isNotEmpty) return items;
    } catch (_) {}

    return <String>[normalizeUrl(AppConfig.wordpressBaseUrl.trim())];
  }

  /// 读取 v2 回退站点条目
  List<BlogSiteSource> readFallbackSourceEntries(SharedPreferences prefs) {
    final raw = prefs.getString(fallbackWordpressSourceEntriesKey);
    if (raw == null || raw.isEmpty) return const <BlogSiteSource>[];

    try {
      final decoded = json.decode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(BlogSiteSource.fromJson)
          .where((item) => item.baseUrl.isNotEmpty)
          .toList();
    } catch (_) {
      return const <BlogSiteSource>[];
    }
  }

  /// 读取 v2 回退组合列表
  List<BlogSiteGroup> readFallbackGroups(SharedPreferences prefs) {
    final raw = prefs.getString(fallbackWordpressGroupsKey);
    if (raw == null || raw.isEmpty) return const <BlogSiteGroup>[];

    try {
      final decoded = json.decode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(BlogSiteGroup.fromJson)
          .where((item) => item.id.isNotEmpty && item.sourceBaseUrls.isNotEmpty)
          .toList();
    } catch (_) {
      return const <BlogSiteGroup>[];
    }
  }

  /// 从 URL 提取域名作为默认站点名称
  String defaultSourceName(String url) {
    final host = Uri.tryParse(url)?.host;
    if (host == null || host.isEmpty) return url;
    return host.replaceFirst('www.', '');
  }

  /// 标准化 URL（去掉末尾斜杠）
  String normalizeUrl(String value) {
    if (value.endsWith('/')) {
      return value.substring(0, value.length - 1);
    }
    return value;
  }

  /// 尝试标准化 URL，无效返回 null
  String? _normalizeIfValid(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (!_isValidUrl(trimmed)) return null;
    return normalizeUrl(trimmed);
  }

  /// 验证 URL 是否合法
  bool _isValidUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        (uri.host.isNotEmpty ||
            value.startsWith('http://127.0.0.1') ||
            value.startsWith('http://localhost'));
  }
}
