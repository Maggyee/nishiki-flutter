import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../config.dart';
import 'local_database_service.dart';

enum BlogSourceMode { single, aggregate }

class BlogSiteSource {
  const BlogSiteSource({
    required this.baseUrl,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });

  final String baseUrl;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get hostLabel {
    final host = Uri.tryParse(baseUrl)?.host;
    if (host != null && host.isNotEmpty) {
      return host.replaceFirst('www.', '');
    }
    return baseUrl.replaceFirst('https://', '').replaceFirst('http://', '');
  }

  Map<String, dynamic> toJson() => {
    'baseUrl': baseUrl,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory BlogSiteSource.fromJson(Map<String, dynamic> json) {
    return BlogSiteSource(
      baseUrl: (json['baseUrl'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      createdAt:
          DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse((json['updatedAt'] as String?) ?? '') ??
          DateTime.now(),
    );
  }
}

class BlogSiteGroup {
  const BlogSiteGroup({
    required this.id,
    required this.name,
    required this.sourceBaseUrls,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final List<String> sourceBaseUrls;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'sourceBaseUrls': sourceBaseUrls,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory BlogSiteGroup.fromJson(Map<String, dynamic> json) {
    return BlogSiteGroup(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      sourceBaseUrls: ((json['sourceBaseUrls'] as List<dynamic>?) ?? const [])
          .whereType<String>()
          .toList(),
      createdAt:
          DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse((json['updatedAt'] as String?) ?? '') ??
          DateTime.now(),
    );
  }
}

class BlogSourceService {
  BlogSourceService._internal();

  static final BlogSourceService _instance = BlogSourceService._internal();

  factory BlogSourceService() => _instance;

  static const String _legacyWordpressBaseUrlKey = 'wordpress_base_url';
  static const String _selectedWordpressSourceKey = 'selected_wordpress_source';
  static const String _wordpressSourceModeKey = 'wordpress_source_mode';
  static const String _selectedWordpressGroupKey = 'selected_wordpress_group';
  static const String _legacyWordpressSourcesKey = 'wordpress_sources';
  static const String _fallbackWordpressSourceEntriesKey =
      'wordpress_source_entries_v2';
  static const String _fallbackWordpressGroupsKey = 'wordpress_groups_v2';

  final LocalDatabaseService _databaseService = LocalDatabaseService();

  final ValueNotifier<String> baseUrl = ValueNotifier(
    AppConfig.wordpressBaseUrl.trim(),
  );
  final ValueNotifier<List<String>> sources = ValueNotifier<List<String>>(
    <String>[AppConfig.wordpressBaseUrl.trim()],
  );
  final ValueNotifier<BlogSourceMode> mode = ValueNotifier(
    BlogSourceMode.single,
  );
  final ValueNotifier<List<BlogSiteSource>> sourceEntries =
      ValueNotifier<List<BlogSiteSource>>(const <BlogSiteSource>[]);
  final ValueNotifier<List<BlogSiteGroup>> groups =
      ValueNotifier<List<BlogSiteGroup>>(const <BlogSiteGroup>[]);
  final ValueNotifier<String?> selectedGroupId = ValueNotifier<String?>(null);

  bool _initialized = false;

  bool get _useSqlite => _databaseService.isSupported;

  Future<void> init() async {
    if (_initialized) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    if (_useSqlite) {
      await _databaseService.init();
      await _migrateLegacyPrefsToSqliteIfNeeded(prefs);
      await _loadFromDatabase();
    } else {
      await _loadFallbackFromPrefs(prefs);
    }

    await _restoreSelectionState(prefs);
    await _ensureMinimumConfig(prefs);
    _initialized = true;
  }

  List<String> get activeSources {
    if (mode.value != BlogSourceMode.aggregate) {
      return <String>[baseUrl.value];
    }

    final group = activeGroup;
    if (group != null && group.sourceBaseUrls.isNotEmpty) {
      return List.unmodifiable(group.sourceBaseUrls);
    }

    return List.unmodifiable(
      sourceEntries.value.map((item) => item.baseUrl).toList(),
    );
  }

  String get currentSource => baseUrl.value;

  BlogSiteGroup? get activeGroup {
    final id = selectedGroupId.value;
    if (id == null || id.isEmpty) {
      return null;
    }
    for (final group in groups.value) {
      if (group.id == id) {
        return group;
      }
    }
    return null;
  }

  BlogSiteSource? get currentSourceEntry {
    for (final source in sourceEntries.value) {
      if (source.baseUrl == baseUrl.value) {
        return source;
      }
    }
    return null;
  }

  String get currentSourceLabel =>
      currentSourceEntry?.name ?? _defaultSourceName(baseUrl.value);

  String get currentScopeLabel {
    if (mode.value == BlogSourceMode.single) {
      return currentSourceLabel;
    }

    final group = activeGroup;
    if (group != null) {
      return '${group.name} · ${group.sourceBaseUrls.length} 个站点';
    }

    return '全部站点聚合 · ${sourceEntries.value.length} 个站点';
  }

  String labelForSource(String sourceBaseUrl) {
    for (final source in sourceEntries.value) {
      if (source.baseUrl == sourceBaseUrl) {
        return source.name;
      }
    }
    return _defaultSourceName(sourceBaseUrl);
  }

  Future<void> setBaseUrl(String url, {String? name}) async {
    final normalized = _validatedUrl(url);
    await _upsertSource(normalized, name: name);
    baseUrl.value = normalized;
    mode.value = BlogSourceMode.single;
    selectedGroupId.value = null;
    await _persistSelectionState();
  }

  Future<void> addSource(String url, {String? name}) async {
    final normalized = _validatedUrl(url);
    await _upsertSource(normalized, name: name);
    await _persistSelectionState();
  }

  Future<void> renameSource(String url, String name) async {
    final normalized = _validatedUrl(url);
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw const FormatException('请输入站点名称');
    }

    if (_useSqlite) {
      final db = await _databaseService.database;
      if (db == null) {
        return;
      }
      await db.update(
        LocalDatabaseService.siteSourcesTable,
        {'name': trimmedName, 'updated_at': DateTime.now().toIso8601String()},
        where: 'base_url = ?',
        whereArgs: [normalized],
      );
      await _loadFromDatabase();
    } else {
      final items = sourceEntries.value
          .map(
            (item) => item.baseUrl == normalized
                ? BlogSiteSource(
                    baseUrl: item.baseUrl,
                    name: trimmedName,
                    createdAt: item.createdAt,
                    updatedAt: DateTime.now(),
                  )
                : item,
          )
          .toList();
      sourceEntries.value = items;
      sources.value = items.map((item) => item.baseUrl).toList();
      await _persistFallbackCollections();
    }
  }

  Future<void> removeSource(String url) async {
    final normalized = _validatedUrl(url);
    if (sourceEntries.value.length <= 1) {
      throw const FormatException('请至少保留一个站点');
    }

    if (_useSqlite) {
      final db = await _databaseService.database;
      if (db == null) {
        return;
      }
      await db.delete(
        LocalDatabaseService.siteSourcesTable,
        where: 'base_url = ?',
        whereArgs: [normalized],
      );
      await _loadFromDatabase();
    } else {
      sourceEntries.value = sourceEntries.value
          .where((item) => item.baseUrl != normalized)
          .toList();
      groups.value = groups.value
          .map(
            (group) => BlogSiteGroup(
              id: group.id,
              name: group.name,
              sourceBaseUrls: group.sourceBaseUrls
                  .where((item) => item != normalized)
                  .toList(),
              createdAt: group.createdAt,
              updatedAt: group.updatedAt,
            ),
          )
          .where((group) => group.sourceBaseUrls.isNotEmpty)
          .toList();
      sources.value = sourceEntries.value.map((item) => item.baseUrl).toList();
      await _persistFallbackCollections();
    }

    if (baseUrl.value == normalized) {
      baseUrl.value = sourceEntries.value.first.baseUrl;
    }

    final selectedGroup = activeGroup;
    if (selectedGroup != null && selectedGroup.sourceBaseUrls.isEmpty) {
      selectedGroupId.value = null;
    }

    if (mode.value == BlogSourceMode.aggregate && activeSources.length <= 1) {
      mode.value = BlogSourceMode.single;
      selectedGroupId.value = null;
    }

    await _persistSelectionState();
  }

  Future<void> selectSource(String url) async {
    final normalized = _validatedUrl(url);
    final knownSource = sourceEntries.value.any(
      (item) => item.baseUrl == normalized,
    );
    if (!knownSource) {
      await _upsertSource(normalized);
    }

    baseUrl.value = normalized;
    mode.value = BlogSourceMode.single;
    selectedGroupId.value = null;
    await _persistSelectionState();
  }

  Future<void> setMode(BlogSourceMode nextMode) async {
    mode.value = nextMode;
    if (nextMode == BlogSourceMode.single) {
      selectedGroupId.value = null;
    } else if (activeSources.length <= 1) {
      mode.value = BlogSourceMode.single;
    }
    await _persistSelectionState();
  }

  Future<void> selectGroup(String? groupId) async {
    if (groupId != null && !groups.value.any((group) => group.id == groupId)) {
      throw const FormatException('站点组合不存在');
    }

    selectedGroupId.value = groupId;
    mode.value = activeSources.length > 1
        ? BlogSourceMode.aggregate
        : BlogSourceMode.single;
    await _persistSelectionState();
  }

  Future<void> saveGroup({
    String? id,
    required String name,
    required List<String> sourceBaseUrls,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw const FormatException('请输入组合名称');
    }

    final normalizedSources = sourceBaseUrls
        .map(_validatedUrl)
        .toSet()
        .toList();
    if (normalizedSources.length < 2) {
      throw const FormatException('组合至少需要两个站点');
    }

    final groupId = (id == null || id.isEmpty)
        ? _createGroupId(trimmedName)
        : id;
    final now = DateTime.now();

    for (final source in normalizedSources) {
      if (!sourceEntries.value.any((item) => item.baseUrl == source)) {
        await _upsertSource(source);
      }
    }

    if (_useSqlite) {
      final db = await _databaseService.database;
      if (db == null) {
        return;
      }

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
            'name': trimmedName,
            'created_at': existing.isNotEmpty
                ? existing.first['created_at'] as String
                : now.toIso8601String(),
            'updated_at': now.toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        await txn.delete(
          LocalDatabaseService.siteGroupMembersTable,
          where: 'group_id = ?',
          whereArgs: [groupId],
        );

        for (int index = 0; index < normalizedSources.length; index++) {
          await txn.insert(
            LocalDatabaseService.siteGroupMembersTable,
            {
              'group_id': groupId,
              'source_base_url': normalizedSources[index],
              'sort_order': index,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });

      await _loadFromDatabase();
    } else {
      final nextGroups = [...groups.value];
      final existingIndex = nextGroups.indexWhere(
        (group) => group.id == groupId,
      );
      final nextGroup = BlogSiteGroup(
        id: groupId,
        name: trimmedName,
        sourceBaseUrls: normalizedSources,
        createdAt: existingIndex >= 0
            ? nextGroups[existingIndex].createdAt
            : now,
        updatedAt: now,
      );
      if (existingIndex >= 0) {
        nextGroups[existingIndex] = nextGroup;
      } else {
        nextGroups.add(nextGroup);
      }
      groups.value = nextGroups
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      await _persistFallbackCollections();
    }

    selectedGroupId.value = groupId;
    mode.value = BlogSourceMode.aggregate;
    await _persistSelectionState();
  }

  Future<void> deleteGroup(String id) async {
    if (_useSqlite) {
      final db = await _databaseService.database;
      if (db == null) {
        return;
      }
      await db.delete(
        LocalDatabaseService.siteGroupsTable,
        where: 'id = ?',
        whereArgs: [id],
      );
      await _loadFromDatabase();
    } else {
      groups.value = groups.value.where((group) => group.id != id).toList();
      await _persistFallbackCollections();
    }

    if (selectedGroupId.value == id) {
      selectedGroupId.value = null;
      mode.value = sourceEntries.value.length > 1
          ? BlogSourceMode.aggregate
          : BlogSourceMode.single;
      await _persistSelectionState();
    }
  }

  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyWordpressBaseUrlKey);
    await prefs.remove(_legacyWordpressSourcesKey);
    await prefs.remove(_selectedWordpressSourceKey);
    await prefs.remove(_wordpressSourceModeKey);
    await prefs.remove(_selectedWordpressGroupKey);
    await prefs.remove(_fallbackWordpressSourceEntriesKey);
    await prefs.remove(_fallbackWordpressGroupsKey);

    final defaultSource = _validatedUrl(AppConfig.wordpressBaseUrl.trim());
    final now = DateTime.now();
    sourceEntries.value = <BlogSiteSource>[
      BlogSiteSource(
        baseUrl: defaultSource,
        name: _defaultSourceName(defaultSource),
        createdAt: now,
        updatedAt: now,
      ),
    ];
    groups.value = const <BlogSiteGroup>[];
    sources.value = <String>[defaultSource];
    baseUrl.value = defaultSource;
    mode.value = BlogSourceMode.single;
    selectedGroupId.value = null;

    if (_useSqlite) {
      final db = await _databaseService.database;
      if (db != null) {
        await db.transaction((txn) async {
          await txn.delete(LocalDatabaseService.siteGroupMembersTable);
          await txn.delete(LocalDatabaseService.siteGroupsTable);
          await txn.delete(LocalDatabaseService.siteSourcesTable);
          await txn.insert(
            LocalDatabaseService.siteSourcesTable,
            {
              'base_url': defaultSource,
              'name': _defaultSourceName(defaultSource),
              'created_at': now.toIso8601String(),
              'updated_at': now.toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        });
      }
    }

    await _persistSelectionState();
    if (!_useSqlite) {
      await _persistFallbackCollections();
    }
  }

  Future<void> _migrateLegacyPrefsToSqliteIfNeeded(
    SharedPreferences prefs,
  ) async {
    final db = await _databaseService.database;
    if (db == null) {
      return;
    }

    final existingRows = await db.query(
      LocalDatabaseService.siteSourcesTable,
      columns: ['base_url'],
      limit: 1,
    );
    if (existingRows.isNotEmpty) {
      return;
    }

    final now = DateTime.now();
    final legacySources = _readLegacySourceUrls(prefs);
    final fallbackSources = _readFallbackSourceEntries(prefs);

    final seedSources = fallbackSources.isNotEmpty
        ? fallbackSources
        : legacySources
              .map(
                (url) => BlogSiteSource(
                  baseUrl: url,
                  name: _defaultSourceName(url),
                  createdAt: now,
                  updatedAt: now,
                ),
              )
              .toList();

    final sourcesToInsert = seedSources.isNotEmpty
        ? seedSources
        : <BlogSiteSource>[
            BlogSiteSource(
              baseUrl: _validatedUrl(AppConfig.wordpressBaseUrl.trim()),
              name: _defaultSourceName(AppConfig.wordpressBaseUrl.trim()),
              createdAt: now,
              updatedAt: now,
            ),
          ];

    final fallbackGroups = _readFallbackGroups(prefs);

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

  Future<void> _loadFromDatabase() async {
    final db = await _databaseService.database;
    if (db == null) {
      return;
    }

    final sourceRows = await db.query(
      LocalDatabaseService.siteSourcesTable,
      orderBy: 'name COLLATE NOCASE ASC',
    );
    final groupRows = await db.query(
      LocalDatabaseService.siteGroupsTable,
      orderBy: 'name COLLATE NOCASE ASC',
    );
    final memberRows = await db.query(
      LocalDatabaseService.siteGroupMembersTable,
      orderBy: 'group_id ASC, sort_order ASC',
    );

    final loadedSources = sourceRows
        .map(
          (row) => BlogSiteSource(
            baseUrl: row['base_url'] as String,
            name:
                (row['name'] as String?) ??
                _defaultSourceName(row['base_url'] as String),
            createdAt:
                DateTime.tryParse((row['created_at'] as String?) ?? '') ??
                DateTime.now(),
            updatedAt:
                DateTime.tryParse((row['updated_at'] as String?) ?? '') ??
                DateTime.now(),
          ),
        )
        .toList();

    final membersByGroup = <String, List<String>>{};
    for (final row in memberRows) {
      final groupId = row['group_id'] as String?;
      final sourceBaseUrl = row['source_base_url'] as String?;
      if (groupId == null || sourceBaseUrl == null) {
        continue;
      }
      membersByGroup.putIfAbsent(groupId, () => <String>[]).add(sourceBaseUrl);
    }

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

    sourceEntries.value = loadedSources;
    groups.value = loadedGroups;
    sources.value = loadedSources.map((item) => item.baseUrl).toList();
  }

  Future<void> _loadFallbackFromPrefs(SharedPreferences prefs) async {
    final fallbackSources = _readFallbackSourceEntries(prefs);
    final fallbackGroups = _readFallbackGroups(prefs);
    final legacySources = _readLegacySourceUrls(prefs);
    final now = DateTime.now();

    final loadedSources = fallbackSources.isNotEmpty
        ? fallbackSources
        : legacySources
              .map(
                (url) => BlogSiteSource(
                  baseUrl: url,
                  name: _defaultSourceName(url),
                  createdAt: now,
                  updatedAt: now,
                ),
              )
              .toList();

    sourceEntries.value = loadedSources.isNotEmpty
        ? loadedSources
        : <BlogSiteSource>[
            BlogSiteSource(
              baseUrl: _validatedUrl(AppConfig.wordpressBaseUrl.trim()),
              name: _defaultSourceName(AppConfig.wordpressBaseUrl.trim()),
              createdAt: now,
              updatedAt: now,
            ),
          ];
    groups.value = fallbackGroups;
    sources.value = sourceEntries.value.map((item) => item.baseUrl).toList();
  }

  Future<void> _restoreSelectionState(SharedPreferences prefs) async {
    final initialSources = sources.value;
    final fallbackSource = initialSources.isNotEmpty
        ? initialSources.first
        : _validatedUrl(AppConfig.wordpressBaseUrl.trim());

    final selectedSource =
        _normalizeIfValid(prefs.getString(_selectedWordpressSourceKey)) ??
        _normalizeIfValid(prefs.getString(_legacyWordpressBaseUrlKey)) ??
        fallbackSource;

    final storedMode = prefs.getString(_wordpressSourceModeKey);
    final selectedGroup = prefs.getString(_selectedWordpressGroupKey);

    baseUrl.value = initialSources.contains(selectedSource)
        ? selectedSource
        : fallbackSource;
    selectedGroupId.value =
        groups.value.any((group) => group.id == selectedGroup)
        ? selectedGroup
        : null;
    mode.value = storedMode == 'aggregate'
        ? BlogSourceMode.aggregate
        : BlogSourceMode.single;
  }

  Future<void> _ensureMinimumConfig(SharedPreferences prefs) async {
    if (sourceEntries.value.isEmpty) {
      await _upsertSource(_validatedUrl(AppConfig.wordpressBaseUrl.trim()));
    }

    if (!sources.value.contains(baseUrl.value)) {
      baseUrl.value = sources.value.first;
    }

    final group = activeGroup;
    if (mode.value == BlogSourceMode.aggregate) {
      final groupHasEnoughSources = group == null
          ? sources.value.length > 1
          : group.sourceBaseUrls.length > 1;
      if (!groupHasEnoughSources) {
        mode.value = BlogSourceMode.single;
        selectedGroupId.value = null;
      }
    }

    await _persistSelectionState(prefs);
    if (!_useSqlite) {
      await _persistFallbackCollections(prefs);
    }
  }

  Future<void> _upsertSource(String baseUrl, {String? name}) async {
    final normalized = _validatedUrl(baseUrl);
    final effectiveName = (name?.trim().isNotEmpty ?? false)
        ? name!.trim()
        : _defaultSourceName(normalized);
    final now = DateTime.now();

    if (_useSqlite) {
      final db = await _databaseService.database;
      if (db == null) {
        return;
      }

      final existing = await db.query(
        LocalDatabaseService.siteSourcesTable,
        columns: ['created_at', 'name'],
        where: 'base_url = ?',
        whereArgs: [normalized],
        limit: 1,
      );

      await db.insert(
        LocalDatabaseService.siteSourcesTable,
        {
          'base_url': normalized,
          'name': existing.isNotEmpty
              ? ((existing.first['name'] as String?)?.trim().isNotEmpty ??
                        false)
                    ? existing.first['name']
                    : effectiveName
              : effectiveName,
          'created_at': existing.isNotEmpty
              ? existing.first['created_at'] as String
              : now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _loadFromDatabase();
      return;
    }

    final nextSources = [...sourceEntries.value];
    final existingIndex = nextSources.indexWhere(
      (item) => item.baseUrl == normalized,
    );
    if (existingIndex >= 0) {
      final existing = nextSources[existingIndex];
      nextSources[existingIndex] = BlogSiteSource(
        baseUrl: existing.baseUrl,
        name: existing.name,
        createdAt: existing.createdAt,
        updatedAt: now,
      );
    } else {
      nextSources.add(
        BlogSiteSource(
          baseUrl: normalized,
          name: effectiveName,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    nextSources.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    sourceEntries.value = nextSources;
    sources.value = nextSources.map((item) => item.baseUrl).toList();
    await _persistFallbackCollections();
  }

  Future<void> _persistSelectionState([SharedPreferences? prefs]) async {
    final resolvedPrefs = prefs ?? await SharedPreferences.getInstance();
    await resolvedPrefs.setString(_selectedWordpressSourceKey, baseUrl.value);
    await resolvedPrefs.setString(_legacyWordpressBaseUrlKey, baseUrl.value);
    await resolvedPrefs.setString(
      _wordpressSourceModeKey,
      mode.value == BlogSourceMode.aggregate ? 'aggregate' : 'single',
    );

    final groupId = selectedGroupId.value;
    if (groupId == null || groupId.isEmpty) {
      await resolvedPrefs.remove(_selectedWordpressGroupKey);
    } else {
      await resolvedPrefs.setString(_selectedWordpressGroupKey, groupId);
    }
  }

  Future<void> _persistFallbackCollections([SharedPreferences? prefs]) async {
    final resolvedPrefs = prefs ?? await SharedPreferences.getInstance();
    await resolvedPrefs.setString(
      _fallbackWordpressSourceEntriesKey,
      json.encode(sourceEntries.value.map((item) => item.toJson()).toList()),
    );
    await resolvedPrefs.setString(
      _fallbackWordpressGroupsKey,
      json.encode(groups.value.map((item) => item.toJson()).toList()),
    );
    await resolvedPrefs.setString(
      _legacyWordpressSourcesKey,
      json.encode(sourceEntries.value.map((item) => item.baseUrl).toList()),
    );
  }

  List<String> _readLegacySourceUrls(SharedPreferences prefs) {
    final raw = prefs.getString(_legacyWordpressSourcesKey);
    if (raw == null || raw.isEmpty) {
      final legacySingle = _normalizeIfValid(
        prefs.getString(_legacyWordpressBaseUrlKey),
      );
      return legacySingle == null
          ? <String>[_validatedUrl(AppConfig.wordpressBaseUrl.trim())]
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
      if (items.isNotEmpty) {
        return items;
      }
    } catch (_) {}

    return <String>[_validatedUrl(AppConfig.wordpressBaseUrl.trim())];
  }

  List<BlogSiteSource> _readFallbackSourceEntries(SharedPreferences prefs) {
    final raw = prefs.getString(_fallbackWordpressSourceEntriesKey);
    if (raw == null || raw.isEmpty) {
      return const <BlogSiteSource>[];
    }

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

  List<BlogSiteGroup> _readFallbackGroups(SharedPreferences prefs) {
    final raw = prefs.getString(_fallbackWordpressGroupsKey);
    if (raw == null || raw.isEmpty) {
      return const <BlogSiteGroup>[];
    }

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

  String _validatedUrl(String value) {
    final normalized = _normalizeIfValid(value);
    if (normalized == null) {
      throw const FormatException('请输入有效的 http:// 或 https:// 地址');
    }
    return normalized;
  }

  String? _normalizeIfValid(String? value) {
    if (value == null) {
      return null;
    }

    final trimmed = value.trim();
    if (!_isValidUrl(trimmed)) {
      return null;
    }
    return _normalizeUrl(trimmed);
  }

  bool _isValidUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        (uri.host.isNotEmpty ||
            value.startsWith('http://127.0.0.1') ||
            value.startsWith('http://localhost'));
  }

  String _normalizeUrl(String value) {
    if (value.endsWith('/')) {
      return value.substring(0, value.length - 1);
    }
    return value;
  }

  String _defaultSourceName(String url) {
    final host = Uri.tryParse(url)?.host;
    if (host == null || host.isEmpty) {
      return url;
    }
    return host.replaceFirst('www.', '');
  }

  String _createGroupId(String name) {
    final normalized = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final seed = normalized.isEmpty ? 'group' : normalized;
    return '$seed-${DateTime.now().millisecondsSinceEpoch}';
  }
}
