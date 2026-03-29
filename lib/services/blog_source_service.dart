// 博客站点源管理服务 — 业务逻辑层（门面层）
//
// 三层架构：
//   BlogSourceService（本层，业务逻辑 + 状态管理）
//   → BlogSourceLocalDataSource（数据存储层，SQLite / SharedPreferences）
//   → blog_source_models.dart（数据模型层）

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../data/blog_source_local_data_source.dart';
import '../models/blog_source_models.dart';
import '../models/sync_models.dart';
import 'local_database_service.dart';
import 'source_detector.dart';
import 'sync_service.dart';

// 重新导出模型类，让现有 import 保持兼容
export '../models/blog_source_models.dart';

class BlogSourceService {
  BlogSourceService._internal();

  static BlogSourceService? _instance;

  /// 单例工厂构造函数
  factory BlogSourceService() => _instance ??= BlogSourceService._internal();

  // ===== 依赖注入 =====
  final LocalDatabaseService _databaseService = LocalDatabaseService();
  late final BlogSourceLocalDataSource _dataSource =
      BlogSourceLocalDataSource(databaseService: _databaseService);
  SyncService get _syncService => SyncService();

  // ===== 响应式状态 =====
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

  // ==================== 初始化 ====================

  /// 初始化服务：加载持久化数据，恢复用户选择状态
  Future<void> init() async {
    if (_initialized) return;

    final prefs = await SharedPreferences.getInstance();
    if (_dataSource.useSqlite) {
      await _databaseService.init();
      await _dataSource.migrateLegacyPrefsToSqliteIfNeeded(prefs);
      await _reloadFromDatabase();
    } else {
      await _loadFallbackFromPrefs(prefs);
    }

    await _restoreSelectionState(prefs);
    await _ensureMinimumConfig(prefs);
    _initialized = true;
  }

  /// 强制重新加载
  Future<void> reload() async {
    _initialized = false;
    await init();
  }

  // ==================== 查询接口 ====================

  /// 当前模式是否为聚合模式
  bool get isAggregate => mode.value == BlogSourceMode.aggregate;

  /// 当前生效的站点列表（单站点模式只返回 1 个，聚合模式返回组合中的站点）
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

  /// 当前选中的站点 URL
  String get currentSource => baseUrl.value;

  /// 当前选中的组合（聚合模式下）
  BlogSiteGroup? get activeGroup {
    final id = selectedGroupId.value;
    if (id == null || id.isEmpty) return null;
    for (final group in groups.value) {
      if (group.id == id) return group;
    }
    return null;
  }

  /// 当前站点的条目信息
  BlogSiteSource? get currentSourceEntry {
    for (final source in sourceEntries.value) {
      if (source.baseUrl == baseUrl.value) return source;
    }
    return null;
  }

  /// 当前站点的显示名称
  String get currentSourceLabel =>
      currentSourceEntry?.name ?? _dataSource.defaultSourceName(baseUrl.value);

  /// 当前作用域的描述标签
  String get currentScopeLabel {
    if (mode.value == BlogSourceMode.single) return currentSourceLabel;

    final group = activeGroup;
    if (group != null) {
      return '${group.name} · ${group.sourceBaseUrls.length} 个站点';
    }

    return '全部站点聚合 · ${sourceEntries.value.length} 个站点';
  }

  /// 获取指定站点的显示名称
  String labelForSource(String sourceBaseUrl) {
    for (final source in sourceEntries.value) {
      if (source.baseUrl == sourceBaseUrl) return source.name;
    }
    return _dataSource.defaultSourceName(sourceBaseUrl);
  }

  // ==================== 站点管理操作 ====================

  /// 设置当前使用的站点（切换到单站点模式）
  Future<void> setBaseUrl(String url, {String? name}) async {
    final normalized = _validatedUrl(url);
    await _upsertSource(normalized, name: name);
    baseUrl.value = normalized;
    mode.value = BlogSourceMode.single;
    selectedGroupId.value = null;
    await _persistSelectionState();
    await _enqueuePreferenceChange();
  }

  /// 添加新站点（自动探测类型）
  Future<void> addSource(
    String url, {
    String? name,
    SourceDetectResult? detectResult,
  }) async {
    final normalized = _validatedUrl(url);

    // 如果调用方已提供探测结果就直接用，否则直接添加为 WordPress
    if (detectResult != null) {
      await _upsertSource(
        detectResult.baseUrl,
        name: name ?? detectResult.siteName,
        sourceType: detectResult.sourceType,
        feedUrl: detectResult.feedUrl,
        siteUrl: detectResult.siteUrl,
      );
      await _persistSelectionState();
      await _enqueueSourceChange(detectResult.baseUrl);
    } else {
      await _upsertSource(normalized, name: name);
      await _persistSelectionState();
      await _enqueueSourceChange(normalized);
    }
  }

  /// 重命名站点
  Future<void> renameSource(String url, String name) async {
    final normalized = _validatedUrl(url);
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw const FormatException('请输入站点名称');
    }

    if (_dataSource.useSqlite) {
      await _dataSource.renameSourceInDb(normalized, trimmedName);
      await _reloadFromDatabase();
    } else {
      // 回退模式：在内存中更新
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
    await _enqueueSourceChange(normalized);
  }

  /// 删除站点
  Future<void> removeSource(String url) async {
    final normalized = _validatedUrl(url);
    if (sourceEntries.value.length <= 1) {
      throw const FormatException('请至少保留一个站点');
    }

    if (_dataSource.useSqlite) {
      await _dataSource.deleteSourceInDb(normalized);
      await _reloadFromDatabase();
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

    // 如果删除的是当前选中的站点，自动切换到第一个
    if (baseUrl.value == normalized) {
      baseUrl.value = sourceEntries.value.first.baseUrl;
    }

    // 如果当前组合已无站点，取消组合选择
    final selectedGroup = activeGroup;
    if (selectedGroup != null && selectedGroup.sourceBaseUrls.isEmpty) {
      selectedGroupId.value = null;
    }

    // 如果聚合模式下只剩 1 个站点，回退到单站点模式
    if (mode.value == BlogSourceMode.aggregate && activeSources.length <= 1) {
      mode.value = BlogSourceMode.single;
      selectedGroupId.value = null;
    }

    await _persistSelectionState();
    await _enqueueSourceChange(normalized, deletedAt: DateTime.now());
    await _enqueuePreferenceChange();
  }

  /// 选择现有站点
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
    await _enqueuePreferenceChange();
  }

  /// 切换数据源模式
  Future<void> setMode(BlogSourceMode nextMode) async {
    mode.value = nextMode;
    if (nextMode == BlogSourceMode.single) {
      selectedGroupId.value = null;
    } else if (activeSources.length <= 1) {
      mode.value = BlogSourceMode.single;
    }
    await _persistSelectionState();
    await _enqueuePreferenceChange();
  }

  // ==================== 组合管理操作 ====================

  /// 选择组合
  Future<void> selectGroup(String? groupId) async {
    if (groupId != null && !groups.value.any((group) => group.id == groupId)) {
      throw const FormatException('站点组合不存在');
    }

    selectedGroupId.value = groupId;
    mode.value = activeSources.length > 1
        ? BlogSourceMode.aggregate
        : BlogSourceMode.single;
    await _persistSelectionState();
    await _enqueuePreferenceChange();
  }

  /// 保存组合（新建或更新）
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

    // 确保组合中的站点都存在
    for (final source in normalizedSources) {
      if (!sourceEntries.value.any((item) => item.baseUrl == source)) {
        await _upsertSource(source);
      }
    }

    if (_dataSource.useSqlite) {
      await _dataSource.saveGroupInDb(
        groupId: groupId,
        name: trimmedName,
        sourceBaseUrls: normalizedSources,
      );
      await _reloadFromDatabase();
    } else {
      final nextGroups = [...groups.value];
      final existingIndex = nextGroups.indexWhere(
        (group) => group.id == groupId,
      );
      final now = DateTime.now();
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
    await _enqueueGroupChange(groupId);
    await _enqueuePreferenceChange();
  }

  /// 删除组合
  Future<void> deleteGroup(String id) async {
    if (_dataSource.useSqlite) {
      await _dataSource.deleteGroupInDb(id);
      await _reloadFromDatabase();
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
    await _enqueueGroupChange(id, deletedAt: DateTime.now());
    await _enqueuePreferenceChange();
  }

  /// 重置所有数据到初始状态
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await _dataSource.clearAllPrefs(prefs);

    final defaultSource = _validatedUrl(AppConfig.wordpressBaseUrl.trim());
    final defaultName = _dataSource.defaultSourceName(defaultSource);
    final now = DateTime.now();

    sourceEntries.value = <BlogSiteSource>[
      BlogSiteSource(
        baseUrl: defaultSource,
        name: defaultName,
        createdAt: now,
        updatedAt: now,
      ),
    ];
    groups.value = const <BlogSiteGroup>[];
    sources.value = <String>[defaultSource];
    baseUrl.value = defaultSource;
    mode.value = BlogSourceMode.single;
    selectedGroupId.value = null;

    if (_dataSource.useSqlite) {
      await _dataSource.resetDatabase(defaultSource, defaultName);
    }

    await _persistSelectionState();
    if (!_dataSource.useSqlite) {
      await _persistFallbackCollections();
    }
    await _enqueuePreferenceChange();
  }

  // ==================== 内部方法 ====================

  /// 从 SQLite 重新加载数据到内存
  Future<void> _reloadFromDatabase() async {
    final result = await _dataSource.loadFromDatabase();
    sourceEntries.value = result.sources;
    groups.value = result.groups;
    sources.value = result.sources.map((item) => item.baseUrl).toList();
  }

  /// 从 SharedPreferences 加载回退数据
  Future<void> _loadFallbackFromPrefs(SharedPreferences prefs) async {
    final result = await _dataSource.loadFallbackFromPrefs(prefs);
    sourceEntries.value = result.sources;
    groups.value = result.groups;
    sources.value = result.sources.map((item) => item.baseUrl).toList();
  }

  /// 恢复用户上次的选择状态
  Future<void> _restoreSelectionState(SharedPreferences prefs) async {
    final state = _dataSource.restoreSelectionState(
      prefs,
      knownSources: sources.value,
      knownGroups: groups.value,
    );
    baseUrl.value = state.baseUrl;
    mode.value = state.mode;
    selectedGroupId.value = state.groupId;
  }

  /// 确保至少有一个站点配置
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
    if (!_dataSource.useSqlite) {
      await _persistFallbackCollections(prefs);
    }
  }

  /// 插入或更新站点（支持 RSS 新字段）
  Future<void> _upsertSource(
    String baseUrl, {
    String? name,
    String sourceType = 'wordpress',
    String? feedUrl,
    String? siteUrl,
  }) async {
    final effectiveName = (name?.trim().isNotEmpty ?? false)
        ? name!.trim()
        : _dataSource.defaultSourceName(baseUrl);

    if (_dataSource.useSqlite) {
      await _dataSource.upsertSourceInDb(
        baseUrl,
        effectiveName,
        sourceType: sourceType,
        feedUrl: feedUrl,
        siteUrl: siteUrl,
      );
      await _reloadFromDatabase();
      return;
    }

    // 回退模式：内存中操作
    final nextSources = [...sourceEntries.value];
    final existingIndex = nextSources.indexWhere(
      (item) => item.baseUrl == baseUrl,
    );
    final now = DateTime.now();
    if (existingIndex >= 0) {
      final existing = nextSources[existingIndex];
      nextSources[existingIndex] = BlogSiteSource(
        baseUrl: existing.baseUrl,
        name: existing.name,
        sourceType: sourceType,
        feedUrl: feedUrl,
        siteUrl: siteUrl,
        createdAt: existing.createdAt,
        updatedAt: now,
      );
    } else {
      nextSources.add(
        BlogSiteSource(
          baseUrl: baseUrl,
          name: effectiveName,
          sourceType: sourceType,
          feedUrl: feedUrl,
          siteUrl: siteUrl,
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

  /// 持久化选择状态
  Future<void> _persistSelectionState([SharedPreferences? prefs]) async {
    final resolvedPrefs = prefs ?? await SharedPreferences.getInstance();
    await _dataSource.persistSelectionState(
      resolvedPrefs,
      baseUrl: baseUrl.value,
      mode: mode.value,
      groupId: selectedGroupId.value,
    );
  }

  /// 持久化回退集合
  Future<void> _persistFallbackCollections([SharedPreferences? prefs]) async {
    final resolvedPrefs = prefs ?? await SharedPreferences.getInstance();
    await _dataSource.persistFallbackCollections(
      resolvedPrefs,
      sources: sourceEntries.value,
      groups: groups.value,
    );
  }

  // ==================== URL 校验 ====================

  String _validatedUrl(String value) {
    final normalized = _normalizeIfValid(value);
    if (normalized == null) {
      throw const FormatException('请输入有效的 http:// 或 https:// 地址');
    }
    return normalized;
  }

  String? _normalizeIfValid(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (!_isValidUrl(trimmed)) return null;
    return _dataSource.normalizeUrl(trimmed);
  }

  bool _isValidUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        (uri.host.isNotEmpty ||
            value.startsWith('http://127.0.0.1') ||
            value.startsWith('http://localhost'));
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

  // ==================== 同步队列 ====================

  Future<void> _enqueueSourceChange(
    String sourceBaseUrl, {
    DateTime? deletedAt,
  }) async {
    final source = _findSource(sourceBaseUrl);
    await _syncService.enqueueChange(
      SyncChange(
        entityType: 'source',
        entityId: sourceBaseUrl,
        data: {
          'id': sourceBaseUrl,
          'baseUrl': sourceBaseUrl,
          'name': source?.name ?? _dataSource.defaultSourceName(sourceBaseUrl),
          'sourceType': source?.sourceType ?? 'wordpress',
          if (source?.feedUrl != null) 'feedUrl': source!.feedUrl,
          if (source?.siteUrl != null) 'siteUrl': source!.siteUrl,
          'createdAt':
              source?.createdAt.toIso8601String() ??
              DateTime.now().toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
          if (deletedAt != null) 'deletedAt': deletedAt.toIso8601String(),
        },
      ),
    );
  }

  Future<void> _enqueueGroupChange(
    String groupId, {
    DateTime? deletedAt,
  }) async {
    final group = _findGroup(groupId);
    await _syncService.enqueueChange(
      SyncChange(
        entityType: 'source_group',
        entityId: groupId,
        data: {
          'id': groupId,
          'name': group?.name ?? 'Untitled group',
          'sourceIds': group?.sourceBaseUrls ?? const <String>[],
          'createdAt':
              group?.createdAt.toIso8601String() ??
              DateTime.now().toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
          if (deletedAt != null) 'deletedAt': deletedAt.toIso8601String(),
        },
      ),
    );
  }

  Future<void> _enqueuePreferenceChange() async {
    await _syncService.enqueueChange(
      SyncChange(
        entityType: 'preference',
        data: {
          'selectedSourceBaseUrl': baseUrl.value,
          'sourceMode': mode.value.name,
          'selectedGroupId': selectedGroupId.value,
          'updatedAt': DateTime.now().toIso8601String(),
        },
      ),
    );
  }

  BlogSiteSource? _findSource(String sourceBaseUrl) {
    for (final source in sourceEntries.value) {
      if (source.baseUrl == sourceBaseUrl) return source;
    }
    return null;
  }

  BlogSiteGroup? _findGroup(String groupId) {
    for (final group in groups.value) {
      if (group.id == groupId) return group;
    }
    return null;
  }
}
