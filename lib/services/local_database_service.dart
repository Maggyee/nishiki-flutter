import 'dart:io' show File, Platform;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class LocalDatabaseService {
  LocalDatabaseService._internal();

  static final LocalDatabaseService _instance =
      LocalDatabaseService._internal();

  factory LocalDatabaseService() => _instance;

  static const String databaseName = 'nishiki_local.db';
  static const int databaseVersion = 7;

  static const String postsTable = 'posts';
  static const String categoriesTable = 'categories';
  static const String postCategoriesTable = 'post_categories';
  static const String savedPostsTable = 'saved_posts';
  static const String likedPostsTable = 'liked_posts';
  static const String readingHistoryTable = 'reading_history';
  static const String aiSummariesTable = 'ai_summaries';
  static const String aiMessagesTable = 'ai_messages';
  static const String siteSourcesTable = 'site_sources';
  static const String siteGroupsTable = 'site_groups';
  static const String siteGroupMembersTable = 'site_group_members';
  static const String syncQueueTable = 'sync_queue';
  static const int defaultMaxCachedPostsPerSource = 240;
  static const Duration defaultMaxCachedPostAge = Duration(days: 45);

  Database? _database;
  String? _databasePath;

  bool get isSupported => !kIsWeb;
  bool get _useFfiDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  Future<void> init() async {
    if (!isSupported || _database != null) {
      return;
    }

    if (_useFfiDesktop) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final databasePath = await databaseFactory.getDatabasesPath();
    final path = p.join(databasePath, databaseName);
    _databasePath = path;

    _database = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: databaseVersion,
        onConfigure: _onConfigure,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  Future<Database?> get database async {
    await init();
    return _database;
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createTables(db);
  }

  Future<void> _onConfigure(Database db) async {
    await _setPragma(db, 'foreign_keys', 'ON');
    await _setPragma(db, 'journal_mode', 'WAL');
    await _setPragma(db, 'synchronous', 'NORMAL');
    await _setPragma(db, 'temp_store', 'MEMORY');
  }

  Future<void> _setPragma(Database db, String name, String value) async {
    await db.rawQuery('PRAGMA $name = $value');
  }

  Future<void> _createPostCacheTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $postsTable (
        source_base_url TEXT NOT NULL,
        id INTEGER NOT NULL,
        slug TEXT,
        title TEXT NOT NULL,
        excerpt TEXT,
        content_html TEXT,
        author TEXT,
        featured_image_url TEXT,
        categories_json TEXT,
        category_ids_json TEXT,
        link TEXT,
        read_minutes INTEGER NOT NULL DEFAULT 1,
        published_at TEXT,
        modified_at TEXT,
        fetched_at TEXT NOT NULL,
        is_detail_fetched INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (source_base_url, id)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_posts_source_published
      ON $postsTable(source_base_url, published_at DESC)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_posts_source_modified
      ON $postsTable(source_base_url, modified_at DESC)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $categoriesTable (
        id INTEGER NOT NULL,
        source_base_url TEXT NOT NULL,
        name TEXT NOT NULL,
        slug TEXT,
        count INTEGER NOT NULL DEFAULT 0,
        fetched_at TEXT NOT NULL,
        PRIMARY KEY (source_base_url, id)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_categories_source_count
      ON $categoriesTable(source_base_url, count DESC)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $postCategoriesTable (
        source_base_url TEXT NOT NULL,
        post_id INTEGER NOT NULL,
        category_id INTEGER NOT NULL,
        PRIMARY KEY (source_base_url, post_id, category_id)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_post_categories_lookup
      ON $postCategoriesTable(source_base_url, category_id, post_id)
    ''');
  }

  Future<void> _createTables(Database db) async {
    await _createPostCacheTables(db);

    await db.execute('''
      CREATE TABLE $savedPostsTable (
        source_base_url TEXT NOT NULL,
        post_id INTEGER NOT NULL,
        saved_at TEXT NOT NULL,
        PRIMARY KEY (source_base_url, post_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE $likedPostsTable (
        source_base_url TEXT NOT NULL,
        post_id INTEGER NOT NULL,
        liked_at TEXT NOT NULL,
        PRIMARY KEY (source_base_url, post_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE $readingHistoryTable (
        source_base_url TEXT NOT NULL,
        post_id INTEGER NOT NULL,
        last_read_at TEXT NOT NULL,
        progress REAL NOT NULL DEFAULT 0,
        PRIMARY KEY (source_base_url, post_id)
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_reading_history_last_read
      ON $readingHistoryTable(last_read_at DESC)
    ''');

    await db.execute('''
      CREATE TABLE $aiSummariesTable (
        source_base_url TEXT NOT NULL,
        post_id INTEGER NOT NULL,
        summary TEXT NOT NULL,
        key_points_json TEXT NOT NULL,
        keywords_json TEXT NOT NULL,
        provider TEXT,
        model TEXT,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (source_base_url, post_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE $aiMessagesTable (
        source_base_url TEXT NOT NULL,
        id TEXT NOT NULL,
        post_id INTEGER NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at TEXT NOT NULL,
        PRIMARY KEY (source_base_url, id)
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_ai_messages_post_created
      ON $aiMessagesTable(source_base_url, post_id, created_at ASC)
    ''');

    await _createSourceManagementTables(db);
    await _createSyncQueueTable(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE $postsTable ADD COLUMN categories_json TEXT',
      );
      await db.execute(
        'ALTER TABLE $postsTable ADD COLUMN read_minutes INTEGER NOT NULL DEFAULT 1',
      );
    }
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE $postsTable ADD COLUMN category_ids_json TEXT',
      );
    }
    if (oldVersion < 4) {
      await _migrateToCompositePrimaryKeys(db);
    }
    if (oldVersion < 5) {
      await _createSourceManagementTables(db);
    }
    if (oldVersion < 6) {
      await _createSyncQueueTable(db);
    }
    if (oldVersion < 7) {
      // 新增 RSS 源元数据字段
      // SQLite 不支持 NOT NULL 且无默认値的 ALTER TABLE
      // source_type 有默认値，历史数据自动回填 'wordpress'
      await db.execute(
        "ALTER TABLE $siteSourcesTable ADD COLUMN source_type TEXT NOT NULL DEFAULT 'wordpress'",
      );
      // feed_url 和 site_url 允许为空
      await db.execute(
        'ALTER TABLE $siteSourcesTable ADD COLUMN feed_url TEXT',
      );
      await db.execute(
        'ALTER TABLE $siteSourcesTable ADD COLUMN site_url TEXT',
      );
    }
  }

  Future<void> _createSourceManagementTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $siteSourcesTable (
        base_url TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        source_type TEXT NOT NULL DEFAULT 'wordpress',
        feed_url TEXT,
        site_url TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_site_sources_name
      ON $siteSourcesTable(name COLLATE NOCASE ASC)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $siteGroupsTable (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_site_groups_name
      ON $siteGroupsTable(name COLLATE NOCASE ASC)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $siteGroupMembersTable (
        group_id TEXT NOT NULL,
        source_base_url TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (group_id, source_base_url),
        FOREIGN KEY (group_id) REFERENCES $siteGroupsTable(id) ON DELETE CASCADE,
        FOREIGN KEY (source_base_url) REFERENCES $siteSourcesTable(base_url) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_site_group_members_group_sort
      ON $siteGroupMembersTable(group_id, sort_order ASC)
    ''');
  }

  Future<void> _createSyncQueueTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $syncQueueTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_type TEXT NOT NULL,
        entity_id TEXT,
        payload_json TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sync_queue_created
      ON $syncQueueTable(created_at ASC)
    ''');
  }

  Future<void> _migrateToCompositePrimaryKeys(Database db) async {
    const postsTableNew = '${postsTable}_v4';
    const savedPostsTableNew = '${savedPostsTable}_v4';
    const likedPostsTableNew = '${likedPostsTable}_v4';
    const readingHistoryTableNew = '${readingHistoryTable}_v4';
    const aiSummariesTableNew = '${aiSummariesTable}_v4';
    const aiMessagesTableNew = '${aiMessagesTable}_v4';

    await db.transaction((txn) async {
      await txn.execute('''
        CREATE TABLE $postsTableNew (
          source_base_url TEXT NOT NULL,
          id INTEGER NOT NULL,
          slug TEXT,
          title TEXT NOT NULL,
          excerpt TEXT,
          content_html TEXT,
          author TEXT,
          featured_image_url TEXT,
          categories_json TEXT,
          category_ids_json TEXT,
          link TEXT,
          read_minutes INTEGER NOT NULL DEFAULT 1,
          published_at TEXT,
          modified_at TEXT,
          fetched_at TEXT NOT NULL,
          is_detail_fetched INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY (source_base_url, id)
        )
      ''');

      await txn.execute('''
        INSERT OR REPLACE INTO $postsTableNew (
          source_base_url, id, slug, title, excerpt, content_html, author,
          featured_image_url, categories_json, category_ids_json, link,
          read_minutes, published_at, modified_at, fetched_at, is_detail_fetched
        )
        SELECT
          source_base_url, id, slug, title, excerpt, content_html, author,
          featured_image_url, categories_json, category_ids_json, link,
          read_minutes, published_at, modified_at, fetched_at, is_detail_fetched
        FROM $postsTable
      ''');

      await txn.execute('''
        CREATE TABLE $savedPostsTableNew (
          source_base_url TEXT NOT NULL,
          post_id INTEGER NOT NULL,
          saved_at TEXT NOT NULL,
          PRIMARY KEY (source_base_url, post_id)
        )
      ''');
      await txn.execute('''
        INSERT OR REPLACE INTO $savedPostsTableNew (source_base_url, post_id, saved_at)
        SELECT source_base_url, post_id, saved_at FROM $savedPostsTable
      ''');

      await txn.execute('''
        CREATE TABLE $likedPostsTableNew (
          source_base_url TEXT NOT NULL,
          post_id INTEGER NOT NULL,
          liked_at TEXT NOT NULL,
          PRIMARY KEY (source_base_url, post_id)
        )
      ''');
      await txn.execute('''
        INSERT OR REPLACE INTO $likedPostsTableNew (source_base_url, post_id, liked_at)
        SELECT source_base_url, post_id, liked_at FROM $likedPostsTable
      ''');

      await txn.execute('''
        CREATE TABLE $readingHistoryTableNew (
          source_base_url TEXT NOT NULL,
          post_id INTEGER NOT NULL,
          last_read_at TEXT NOT NULL,
          progress REAL NOT NULL DEFAULT 0,
          PRIMARY KEY (source_base_url, post_id)
        )
      ''');
      await txn.execute('''
        INSERT OR REPLACE INTO $readingHistoryTableNew (
          source_base_url, post_id, last_read_at, progress
        )
        SELECT source_base_url, post_id, last_read_at, progress
        FROM $readingHistoryTable
      ''');

      await txn.execute('''
        CREATE TABLE $aiSummariesTableNew (
          source_base_url TEXT NOT NULL,
          post_id INTEGER NOT NULL,
          summary TEXT NOT NULL,
          key_points_json TEXT NOT NULL,
          keywords_json TEXT NOT NULL,
          provider TEXT,
          model TEXT,
          updated_at TEXT NOT NULL,
          PRIMARY KEY (source_base_url, post_id)
        )
      ''');
      await txn.execute('''
        INSERT OR REPLACE INTO $aiSummariesTableNew (
          source_base_url, post_id, summary, key_points_json, keywords_json,
          provider, model, updated_at
        )
        SELECT
          source_base_url, post_id, summary, key_points_json, keywords_json,
          provider, model, updated_at
        FROM $aiSummariesTable
      ''');

      await txn.execute('''
        CREATE TABLE $aiMessagesTableNew (
          source_base_url TEXT NOT NULL,
          id TEXT NOT NULL,
          post_id INTEGER NOT NULL,
          role TEXT NOT NULL,
          content TEXT NOT NULL,
          created_at TEXT NOT NULL,
          PRIMARY KEY (source_base_url, id)
        )
      ''');
      await txn.execute('''
        INSERT OR REPLACE INTO $aiMessagesTableNew (
          source_base_url, id, post_id, role, content, created_at
        )
        SELECT source_base_url, id, post_id, role, content, created_at
        FROM $aiMessagesTable
      ''');

      await txn.execute('DROP TABLE $postsTable');
      await txn.execute('DROP TABLE $savedPostsTable');
      await txn.execute('DROP TABLE $likedPostsTable');
      await txn.execute('DROP TABLE $readingHistoryTable');
      await txn.execute('DROP TABLE $aiSummariesTable');
      await txn.execute('DROP TABLE $aiMessagesTable');

      await txn.execute('ALTER TABLE $postsTableNew RENAME TO $postsTable');
      await txn.execute(
        'ALTER TABLE $savedPostsTableNew RENAME TO $savedPostsTable',
      );
      await txn.execute(
        'ALTER TABLE $likedPostsTableNew RENAME TO $likedPostsTable',
      );
      await txn.execute(
        'ALTER TABLE $readingHistoryTableNew RENAME TO $readingHistoryTable',
      );
      await txn.execute(
        'ALTER TABLE $aiSummariesTableNew RENAME TO $aiSummariesTable',
      );
      await txn.execute(
        'ALTER TABLE $aiMessagesTableNew RENAME TO $aiMessagesTable',
      );

      await txn.execute('''
        CREATE INDEX idx_posts_source_published
        ON $postsTable(source_base_url, published_at DESC)
      ''');
      await txn.execute('''
        CREATE INDEX idx_posts_source_modified
        ON $postsTable(source_base_url, modified_at DESC)
      ''');
      await txn.execute('''
        CREATE INDEX idx_reading_history_last_read
        ON $readingHistoryTable(source_base_url, last_read_at DESC)
      ''');
      await txn.execute('''
        CREATE INDEX idx_ai_messages_post_created
        ON $aiMessagesTable(source_base_url, post_id, created_at ASC)
      ''');
    });
  }

  Future<void> clearAllData() async {
    final db = await database;
    if (db == null) {
      return;
    }

    await db.transaction((txn) async {
      await txn.delete(aiMessagesTable);
      await txn.delete(aiSummariesTable);
      await txn.delete(readingHistoryTable);
      await txn.delete(likedPostsTable);
      await txn.delete(savedPostsTable);
      await txn.delete(postCategoriesTable);
      await txn.delete(categoriesTable);
      await txn.delete(postsTable);
      await txn.delete(siteGroupMembersTable);
      await txn.delete(siteGroupsTable);
      await txn.delete(siteSourcesTable);
    });
  }

  Future<LocalCacheStats> getCacheStats([String? sourceBaseUrl]) async {
    if (!isSupported) {
      return const LocalCacheStats(
        currentSourcePostCount: 0,
        totalPostCount: 0,
        databaseBytes: 0,
      );
    }

    final db = await database;
    if (db == null) {
      return const LocalCacheStats(
        currentSourcePostCount: 0,
        totalPostCount: 0,
        databaseBytes: 0,
      );
    }

    final totalRows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM $postsTable',
    );
    final totalPostCount = totalRows.isNotEmpty
        ? ((totalRows.first['count'] as int?) ?? 0)
        : 0;

    var currentSourcePostCount = totalPostCount;
    if (sourceBaseUrl != null && sourceBaseUrl.isNotEmpty) {
      final sourceRows = await db.rawQuery(
        'SELECT COUNT(*) AS count FROM $postsTable WHERE source_base_url = ?',
        [sourceBaseUrl],
      );
      currentSourcePostCount = sourceRows.isNotEmpty
          ? ((sourceRows.first['count'] as int?) ?? 0)
          : 0;
    }

    final bytes = await _readDatabaseFileBytes();
    return LocalCacheStats(
      currentSourcePostCount: currentSourcePostCount,
      totalPostCount: totalPostCount,
      databaseBytes: bytes,
    );
  }

  Future<void> clearTransientContentCache() async {
    final db = await database;
    if (db == null) {
      return;
    }

    await db.transaction((txn) async {
      await txn.delete(postCategoriesTable);
      await txn.delete(categoriesTable);
    });

    await pruneAllSourcesCache(maxPosts: 0, maxAge: Duration.zero);
  }

  Future<void> pruneSourceCache(
    String sourceBaseUrl, {
    int maxPosts = defaultMaxCachedPostsPerSource,
    Duration maxAge = defaultMaxCachedPostAge,
  }) async {
    final db = await database;
    if (db == null) {
      return;
    }

    final cutoff = DateTime.now().subtract(maxAge).toIso8601String();

    await db.transaction((txn) async {
      final protectedRows = await txn.rawQuery('''
        SELECT id FROM $postsTable
        WHERE source_base_url = ?
          AND id IN (
            SELECT post_id FROM $savedPostsTable WHERE source_base_url = ?
            UNION
            SELECT post_id FROM $likedPostsTable WHERE source_base_url = ?
            UNION
            SELECT post_id FROM $readingHistoryTable WHERE source_base_url = ?
            UNION
            SELECT post_id FROM $aiSummariesTable WHERE source_base_url = ?
            UNION
            SELECT post_id FROM $aiMessagesTable WHERE source_base_url = ?
          )
      ''', List.filled(6, sourceBaseUrl));

      final protectedIds = protectedRows
          .map((row) => row['id'])
          .whereType<int>()
          .toSet();

      final unprotectedRows = await txn.query(
        postsTable,
        columns: ['id', 'fetched_at'],
        where: 'source_base_url = ?',
        whereArgs: [sourceBaseUrl],
        orderBy: 'published_at DESC, fetched_at DESC',
      );

      final staleIds = <int>[];
      final overflowIds = <int>[];
      var retainedUnprotected = 0;

      for (final row in unprotectedRows) {
        final id = row['id'];
        if (id is! int || protectedIds.contains(id)) {
          continue;
        }

        retainedUnprotected += 1;
        final fetchedAt = row['fetched_at'] as String?;
        final isOlderThanCutoff =
            fetchedAt != null &&
            fetchedAt.isNotEmpty &&
            fetchedAt.compareTo(cutoff) < 0;

        if (retainedUnprotected > maxPosts) {
          overflowIds.add(id);
        } else if (isOlderThanCutoff) {
          staleIds.add(id);
        }
      }

      final idsToDelete = {...overflowIds, ...staleIds}.toList();
      if (idsToDelete.isEmpty) {
        return;
      }

      final placeholders = List.filled(idsToDelete.length, '?').join(', ');
      final whereArgs = <Object?>[sourceBaseUrl, ...idsToDelete];

      await txn.delete(
        postCategoriesTable,
        where: 'source_base_url = ? AND post_id IN ($placeholders)',
        whereArgs: whereArgs,
      );
      await txn.delete(
        postsTable,
        where: 'source_base_url = ? AND id IN ($placeholders)',
        whereArgs: whereArgs,
      );
    });
  }

  Future<void> pruneAllSourcesCache({
    int maxPosts = defaultMaxCachedPostsPerSource,
    Duration maxAge = defaultMaxCachedPostAge,
  }) async {
    final db = await database;
    if (db == null) {
      return;
    }

    final rows = await db.rawQuery(
      'SELECT DISTINCT source_base_url FROM $postsTable',
    );

    for (final row in rows) {
      final source = row['source_base_url'] as String?;
      if (source == null || source.isEmpty) {
        continue;
      }
      await pruneSourceCache(source, maxPosts: maxPosts, maxAge: maxAge);
    }
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  Future<int> _readDatabaseFileBytes() async {
    final path = _databasePath;
    if (path == null || path.isEmpty) {
      return 0;
    }

    final file = File(path);
    if (!await file.exists()) {
      return 0;
    }

    return file.length();
  }
}

class LocalCacheStats {
  const LocalCacheStats({
    required this.currentSourcePostCount,
    required this.totalPostCount,
    required this.databaseBytes,
  });

  final int currentSourcePostCount;
  final int totalPostCount;
  final int databaseBytes;
}
