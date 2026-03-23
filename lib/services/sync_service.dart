import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';
import '../models/sync_models.dart';
import 'auth_service.dart';
import 'blog_source_service.dart';
import 'local_database_service.dart';
import 'settings_service.dart';

class SyncService {
  SyncService._internal();

  static SyncService? _instance;

  factory SyncService() => _instance ??= SyncService._internal();

  static const String _syncVersionKey = 'sync_latest_version';

  final LocalDatabaseService _databaseService = LocalDatabaseService();
  final AuthService _authService = AuthService();
  BlogSourceService get _blogSourceService => BlogSourceService();
  SettingsService get _settingsService => SettingsService();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSub;

  Future<void> init() async {
    await _databaseService.init();
    await _authService.init();
  }

  Future<void> enqueueChange(SyncChange change) async {
    if (!_databaseService.isSupported) {
      return;
    }

    final db = await _databaseService.database;
    if (db == null) {
      return;
    }

    await db.insert(LocalDatabaseService.syncQueueTable, {
      'entity_type': change.entityType,
      'entity_id': change.entityId,
      'payload_json': jsonEncode(change.toJson()),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> pushPendingChanges() async {
    if (!_authService.isSignedIn || !_databaseService.isSupported) {
      return;
    }

    final db = await _databaseService.database;
    if (db == null) {
      return;
    }

    final rows = await db.query(
      LocalDatabaseService.syncQueueTable,
      orderBy: 'created_at ASC',
    );
    if (rows.isEmpty) {
      return;
    }

    final changes = rows
        .map((row) => jsonDecode(row['payload_json'] as String))
        .whereType<Map<String, dynamic>>()
        .toList();

    final response = await _authService.authorizedPostJson('/api/sync/push', {
      'changes': changes,
    });
    final latestVersion = (response['latestVersion'] as num?)?.toInt() ?? 0;
    await _setLatestVersion(latestVersion);
    await db.delete(LocalDatabaseService.syncQueueTable);
  }

  Future<void> reconcileLocalState() async {
    if (!_authService.isSignedIn) {
      return;
    }

    final bootstrapChanges = <Map<String, dynamic>>[];
    bootstrapChanges.add(_buildPreferenceChange().toJson());
    bootstrapChanges.addAll(await _buildSourceChanges());
    bootstrapChanges.addAll(await _buildSavedPostChanges());
    bootstrapChanges.addAll(await _buildLikedPostChanges());
    bootstrapChanges.addAll(await _buildReadingProgressChanges());
    bootstrapChanges.addAll(await _buildAiSummaryChanges());
    bootstrapChanges.addAll(await _buildAiThreadChanges());

    final response = await _authService.authorizedPostJson(
      '/api/sync/reconcile',
      {'changes': bootstrapChanges},
    );
    await _applyBootstrapData(
      SyncEnvelope(
        latestVersion: (response['latestVersion'] as num?)?.toInt() ?? 0,
        data: (response['data'] as Map<String, dynamic>?) ?? const {},
      ),
    );
  }

  Future<void> bootstrap() async {
    if (!_authService.isSignedIn) {
      return;
    }

    final response = await _authService.authorizedGetJson(
      '/api/sync/bootstrap',
    );
    await _applyBootstrapData(
      SyncEnvelope(
        latestVersion: (response['latestVersion'] as num?)?.toInt() ?? 0,
        data: (response['data'] as Map<String, dynamic>?) ?? const {},
      ),
    );
  }

  Future<void> pullChanges() async {
    if (!_authService.isSignedIn) {
      return;
    }

    final sinceVersion = await _getLatestVersion();
    final response = await _authService.authorizedGetJson(
      '/api/sync/changes?sinceVersion=$sinceVersion',
    );
    final changes = ((response['changes'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    if (changes.isNotEmpty) {
      await bootstrap();
      return;
    }
    await _setLatestVersion(
      (response['latestVersion'] as num?)?.toInt() ?? sinceVersion,
    );
  }

  Future<void> connectRealtime() async {
    final headers = _authService.buildAuthHeaders();
    final authorization = headers['Authorization'];
    if (!_authService.isSignedIn || authorization == null) {
      return;
    }

    final token = authorization.replaceFirst('Bearer ', '').trim();
    await _channelSub?.cancel();
    await _channel?.sink.close();
    _channel = WebSocketChannel.connect(AppConfig.resolveWebSocketUri(token));
    _channelSub = _channel!.stream.listen((event) async {
      try {
        final decoded = jsonDecode(event as String) as Map<String, dynamic>;
        final eventName = decoded['event'] as String? ?? '';
        if (eventName == 'sync.updated' || eventName == 'preferences.updated') {
          await pullChanges();
        }
      } catch (_) {}
    });
  }

  Future<void> disposeRealtime() async {
    await _channelSub?.cancel();
    await _channel?.sink.close();
    _channelSub = null;
    _channel = null;
  }

  SyncChange _buildPreferenceChange() {
    return SyncChange(
      entityType: 'preference',
      data: {
        'themeMode': _settingsService.themeMode.value.name,
        'fontScale': _settingsService.fontScale.value,
        'selectedSourceBaseUrl': _blogSourceService.baseUrl.value,
        'sourceMode': _blogSourceService.mode.value.name,
        'selectedGroupId': _blogSourceService.selectedGroupId.value,
        'updatedAt': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<List<Map<String, dynamic>>> _buildSourceChanges() async {
    await _blogSourceService.init();
    final changes = <Map<String, dynamic>>[];
    for (final source in _blogSourceService.sourceEntries.value) {
      changes.add(
        SyncChange(
          entityType: 'source',
          entityId: source.baseUrl,
          data: {
            'id': source.baseUrl,
            'baseUrl': source.baseUrl,
            'name': source.name,
            'createdAt': source.createdAt.toIso8601String(),
            'updatedAt': source.updatedAt.toIso8601String(),
          },
        ).toJson(),
      );
    }
    for (final group in _blogSourceService.groups.value) {
      changes.add(
        SyncChange(
          entityType: 'source_group',
          entityId: group.id,
          data: {
            'id': group.id,
            'name': group.name,
            'sourceIds': group.sourceBaseUrls,
            'createdAt': group.createdAt.toIso8601String(),
            'updatedAt': group.updatedAt.toIso8601String(),
          },
        ).toJson(),
      );
    }
    return changes;
  }

  Future<List<Map<String, dynamic>>> _buildSavedPostChanges() async {
    final db = await _databaseService.database;
    if (db == null) {
      return const [];
    }

    final rows = await db.query(LocalDatabaseService.savedPostsTable);
    return rows
        .map(
          (row) => SyncChange(
            entityType: 'saved_post',
            entityId:
                '${row['source_base_url'] as String}:${row['post_id'] as int}',
            data: {
              'sourceBaseUrl': row['source_base_url'],
              'postId': row['post_id'],
              'savedAt': row['saved_at'],
              'updatedAt': row['saved_at'],
            },
          ).toJson(),
        )
        .toList();
  }

  Future<List<Map<String, dynamic>>> _buildLikedPostChanges() async {
    final db = await _databaseService.database;
    if (db == null) {
      return const [];
    }

    final rows = await db.query(LocalDatabaseService.likedPostsTable);
    return rows
        .map(
          (row) => SyncChange(
            entityType: 'liked_post',
            entityId:
                '${row['source_base_url'] as String}:${row['post_id'] as int}',
            data: {
              'sourceBaseUrl': row['source_base_url'],
              'postId': row['post_id'],
              'likedAt': row['liked_at'],
              'updatedAt': row['liked_at'],
            },
          ).toJson(),
        )
        .toList();
  }

  Future<List<Map<String, dynamic>>> _buildReadingProgressChanges() async {
    final db = await _databaseService.database;
    if (db == null) {
      return const [];
    }

    final rows = await db.query(LocalDatabaseService.readingHistoryTable);
    return rows
        .map(
          (row) => SyncChange(
            entityType: 'reading_progress',
            entityId:
                '${row['source_base_url'] as String}:${row['post_id'] as int}',
            data: {
              'sourceBaseUrl': row['source_base_url'],
              'postId': row['post_id'],
              'progress': row['progress'],
              'lastReadAt': row['last_read_at'],
              'updatedAt': row['last_read_at'],
            },
          ).toJson(),
        )
        .toList();
  }

  Future<List<Map<String, dynamic>>> _buildAiSummaryChanges() async {
    final db = await _databaseService.database;
    if (db == null) {
      return const [];
    }

    final rows = await db.query(LocalDatabaseService.aiSummariesTable);
    return rows
        .map(
          (row) => SyncChange(
            entityType: 'ai_summary',
            entityId:
                '${row['source_base_url'] as String}:${row['post_id'] as int}',
            data: {
              'sourceBaseUrl': row['source_base_url'],
              'postId': row['post_id'],
              'summary': row['summary'],
              'keyPoints': _decodeStringList(row['key_points_json'] as String?),
              'keywords': _decodeStringList(row['keywords_json'] as String?),
              'provider': row['provider'],
              'model': row['model'],
              'updatedAt': row['updated_at'],
            },
          ).toJson(),
        )
        .toList();
  }

  Future<List<Map<String, dynamic>>> _buildAiThreadChanges() async {
    final db = await _databaseService.database;
    if (db == null) {
      return const [];
    }

    final rows = await db.query(
      LocalDatabaseService.aiMessagesTable,
      orderBy: 'source_base_url ASC, post_id ASC, created_at ASC',
    );
    final grouped = <String, List<Map<String, Object?>>>{};
    for (final row in rows) {
      final key =
          '${row['source_base_url'] as String}:${row['post_id'] as int}';
      grouped.putIfAbsent(key, () => []).add(row);
    }

    return grouped.entries.map((entry) {
      final first = entry.value.first;
      return SyncChange(
        entityType: 'ai_thread',
        entityId: entry.key,
        data: {
          'id': entry.key,
          'sourceBaseUrl': first['source_base_url'],
          'postId': first['post_id'],
          'createdAt': first['created_at'],
          'updatedAt': entry.value.last['created_at'],
          'messages': entry.value
              .map(
                (row) => {
                  'id': row['id'],
                  'role': row['role'],
                  'content': row['content'],
                  'createdAt': row['created_at'],
                  'updatedAt': row['created_at'],
                },
              )
              .toList(),
        },
      ).toJson();
    }).toList();
  }

  Future<void> _applyBootstrapData(SyncEnvelope envelope) async {
    final db = await _databaseService.database;
    if (db == null) {
      return;
    }

    final data = envelope.data;
    await db.transaction((txn) async {
      await txn.delete(LocalDatabaseService.savedPostsTable);
      await txn.delete(LocalDatabaseService.likedPostsTable);
      await txn.delete(LocalDatabaseService.readingHistoryTable);
      await txn.delete(LocalDatabaseService.aiSummariesTable);
      await txn.delete(LocalDatabaseService.aiMessagesTable);
      await txn.delete(LocalDatabaseService.siteGroupMembersTable);
      await txn.delete(LocalDatabaseService.siteGroupsTable);
      await txn.delete(LocalDatabaseService.siteSourcesTable);

      for (final source in ((data['sources'] as List<dynamic>?) ?? const [])) {
        if (source is! Map<String, dynamic>) continue;
        await txn.insert(LocalDatabaseService.siteSourcesTable, {
          'base_url': source['baseUrl'],
          'name': source['name'],
          'created_at': source['createdAt'],
          'updated_at': source['updatedAt'],
        });
      }

      for (final group
          in ((data['sourceGroups'] as List<dynamic>?) ?? const [])) {
        if (group is! Map<String, dynamic>) continue;
        await txn.insert(LocalDatabaseService.siteGroupsTable, {
          'id': group['id'],
          'name': group['name'],
          'created_at': group['createdAt'],
          'updated_at': group['updatedAt'],
        });

        final sourceIds = ((group['sourceIds'] as List<dynamic>?) ?? const []);
        for (int i = 0; i < sourceIds.length; i += 1) {
          await txn.insert(LocalDatabaseService.siteGroupMembersTable, {
            'group_id': group['id'],
            'source_base_url': sourceIds[i],
            'sort_order': i,
          });
        }
      }

      for (final item in ((data['savedPosts'] as List<dynamic>?) ?? const [])) {
        if (item is! Map<String, dynamic> || item['deletedAt'] != null) {
          continue;
        }
        await txn.insert(LocalDatabaseService.savedPostsTable, {
          'source_base_url': item['sourceBaseUrl'],
          'post_id': item['postId'],
          'saved_at': item['savedAt'],
        });
      }

      for (final item in ((data['likedPosts'] as List<dynamic>?) ?? const [])) {
        if (item is! Map<String, dynamic> || item['deletedAt'] != null) {
          continue;
        }
        await txn.insert(LocalDatabaseService.likedPostsTable, {
          'source_base_url': item['sourceBaseUrl'],
          'post_id': item['postId'],
          'liked_at': item['likedAt'],
        });
      }

      for (final item
          in ((data['readingProgress'] as List<dynamic>?) ?? const [])) {
        if (item is! Map<String, dynamic> || item['deletedAt'] != null) {
          continue;
        }
        await txn.insert(LocalDatabaseService.readingHistoryTable, {
          'source_base_url': item['sourceBaseUrl'],
          'post_id': item['postId'],
          'last_read_at': item['lastReadAt'],
          'progress': item['progress'],
        });
      }

      for (final item
          in ((data['aiSummaries'] as List<dynamic>?) ?? const [])) {
        if (item is! Map<String, dynamic> || item['deletedAt'] != null) {
          continue;
        }
        await txn.insert(LocalDatabaseService.aiSummariesTable, {
          'source_base_url': item['sourceBaseUrl'],
          'post_id': item['postId'],
          'summary': item['summary'],
          'key_points_json': jsonEncode(item['keyPoints'] ?? const []),
          'keywords_json': jsonEncode(item['keywords'] ?? const []),
          'provider': item['provider'],
          'model': item['model'],
          'updated_at': item['updatedAt'],
        });
      }

      for (final thread
          in ((data['aiThreads'] as List<dynamic>?) ?? const [])) {
        if (thread is! Map<String, dynamic> || thread['deletedAt'] != null) {
          continue;
        }
        for (final message
            in ((thread['messages'] as List<dynamic>?) ?? const [])) {
          if (message is! Map<String, dynamic> ||
              message['deletedAt'] != null) {
            continue;
          }
          await txn.insert(LocalDatabaseService.aiMessagesTable, {
            'source_base_url': thread['sourceBaseUrl'],
            'id': message['id'],
            'post_id': thread['postId'],
            'role': message['role'],
            'content': message['content'],
            'created_at': message['createdAt'],
          });
        }
      }
    });

    final prefs = await SharedPreferences.getInstance();
    final preference = data['preference'] as Map<String, dynamic>?;
    if (preference != null) {
      final sourceMode = preference['sourceMode'] as String? ?? 'single';
      await prefs.setInt(
        'theme_mode',
        _themeModeIndex(preference['themeMode'] as String? ?? 'system'),
      );
      await prefs.setDouble(
        'font_scale',
        (preference['fontScale'] as num?)?.toDouble() ?? 1.0,
      );
      if ((preference['selectedSourceBaseUrl'] as String?)?.isNotEmpty ??
          false) {
        await prefs.setString(
          'selected_wordpress_source',
          preference['selectedSourceBaseUrl'] as String,
        );
        await prefs.setString(
          'wordpress_base_url',
          preference['selectedSourceBaseUrl'] as String,
        );
      }
      await prefs.setString('wordpress_source_mode', sourceMode);
      final selectedGroupId = preference['selectedGroupId'] as String?;
      if (selectedGroupId == null || selectedGroupId.isEmpty) {
        await prefs.remove('selected_wordpress_group');
      } else {
        await prefs.setString('selected_wordpress_group', selectedGroupId);
      }
    }

    await _setLatestVersion(envelope.latestVersion);
    await _blogSourceService.reload();
    await _settingsService.reload();
  }

  List<String> _decodeStringList(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((item) => item.toString())
          .toList();
    } catch (_) {
      return const [];
    }
  }

  int _themeModeIndex(String value) {
    switch (value) {
      case 'light':
        return 1;
      case 'dark':
        return 2;
      default:
        return 0;
    }
  }

  Future<int> _getLatestVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_syncVersionKey) ?? 0;
  }

  Future<void> _setLatestVersion(int version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_syncVersionKey, version);
  }
}
