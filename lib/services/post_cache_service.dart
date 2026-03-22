import 'dart:convert';

import '../models/wp_models.dart';
import 'blog_source_service.dart';
import 'local_database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class PostCacheService {
  PostCacheService._internal();

  static final PostCacheService _instance = PostCacheService._internal();

  factory PostCacheService() => _instance;

  final LocalDatabaseService _databaseService = LocalDatabaseService();
  final BlogSourceService _blogSource = BlogSourceService();
  static const int _maxCachedPostsPerSource =
      LocalDatabaseService.defaultMaxCachedPostsPerSource;
  static const Duration _maxCachedPostAge =
      LocalDatabaseService.defaultMaxCachedPostAge;

  String get _sourceBaseUrl => _blogSource.baseUrl.value.trim();
  String _resolveSourceBaseUrl(String? sourceBaseUrl) =>
      ((sourceBaseUrl == null || sourceBaseUrl.trim().isEmpty)
              ? _sourceBaseUrl
              : sourceBaseUrl)
          .trim();

  bool get isSupported => _databaseService.isSupported;

  Future<void> cachePosts(List<WpPost> posts) async {
    if (!isSupported || posts.isEmpty) {
      return;
    }

    final db = await _databaseService.database;
    if (db == null) {
      return;
    }

    await db.transaction((txn) async {
      for (final post in posts) {
        await _upsertPost(txn, post, allowEmptyContent: true);
      }
    });
    final sources = posts.map((post) => post.sourceBaseUrl.trim()).toSet();
    for (final source in sources) {
      await _databaseService.pruneSourceCache(
        source,
        maxPosts: _maxCachedPostsPerSource,
        maxAge: _maxCachedPostAge,
      );
    }
  }

  Future<void> cachePostDetail(WpPost post) async {
    if (!isSupported) {
      return;
    }

    final db = await _databaseService.database;
    if (db == null) {
      return;
    }

    await _upsertPost(db, post, allowEmptyContent: false);
    await _databaseService.pruneSourceCache(
      post.sourceBaseUrl,
      maxPosts: _maxCachedPostsPerSource,
      maxAge: _maxCachedPostAge,
    );
  }

  Future<void> cacheCategories(List<WpCategory> categories) async {
    if (!isSupported || categories.isEmpty) {
      return;
    }

    final db = await _databaseService.database;
    if (db == null) {
      return;
    }

    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.delete(
        LocalDatabaseService.categoriesTable,
        where: 'source_base_url = ?',
        whereArgs: [_sourceBaseUrl],
      );

      for (final category in categories) {
        await txn.insert(LocalDatabaseService.categoriesTable, {
          'id': category.id,
          'source_base_url': _sourceBaseUrl,
          'name': category.name,
          'slug': null,
          'count': 0,
          'fetched_at': now,
        });
      }
    });
  }

  Future<List<WpPost>> getCachedPosts({
    String search = '',
    int? categoryId,
    int limit = 12,
    int offset = 0,
    String? sourceBaseUrl,
  }) async {
    if (!isSupported) {
      return const [];
    }

    final db = await _databaseService.database;
    if (db == null) {
      return const [];
    }

    final resolvedSource = _resolveSourceBaseUrl(sourceBaseUrl);
    final whereParts = <String>['source_base_url = ?'];
    final whereArgs = <Object?>[resolvedSource];

    if (search.trim().isNotEmpty) {
      whereParts.add('(title LIKE ? OR excerpt LIKE ?)');
      final pattern = '%${search.trim()}%';
      whereArgs
        ..add(pattern)
        ..add(pattern);
    }

    if (categoryId != null) {
      whereParts.add('''EXISTS (
        SELECT 1 FROM ${LocalDatabaseService.postCategoriesTable} pc
        WHERE pc.source_base_url = ${LocalDatabaseService.postsTable}.source_base_url
          AND pc.post_id = ${LocalDatabaseService.postsTable}.id
          AND pc.category_id = ?
      )''');
      whereArgs.add(categoryId);
    }

    final rows = await db.query(
      LocalDatabaseService.postsTable,
      where: whereParts.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'published_at DESC',
      limit: limit,
      offset: offset,
    );

    return rows.map(_postFromRow).toList();
  }

  Future<WpPost?> getCachedPostById(int postId, {String? sourceBaseUrl}) async {
    if (!isSupported) {
      return null;
    }

    final db = await _databaseService.database;
    if (db == null) {
      return null;
    }

    final resolvedSource = _resolveSourceBaseUrl(sourceBaseUrl);
    final rows = await db.query(
      LocalDatabaseService.postsTable,
      where: 'id = ? AND source_base_url = ?',
      whereArgs: [postId, resolvedSource],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return _postFromRow(rows.first, sourceBaseUrl: resolvedSource);
  }

  Future<List<WpCategory>> getCachedCategories({String? sourceBaseUrl}) async {
    if (!isSupported) {
      return const [];
    }

    final db = await _databaseService.database;
    if (db == null) {
      return const [];
    }

    final resolvedSource = _resolveSourceBaseUrl(sourceBaseUrl);
    final rows = await db.query(
      LocalDatabaseService.categoriesTable,
      where: 'source_base_url = ?',
      whereArgs: [resolvedSource],
      orderBy: 'name COLLATE NOCASE ASC',
    );

    return rows
        .map(
          (row) => WpCategory(
            id: row['id'] as int,
            name: (row['name'] as String?) ?? 'Unknown',
          ),
        )
        .toList();
  }

  Future<void> clearSourceCache([String? sourceBaseUrl]) async {
    if (!isSupported) {
      return;
    }

    final db = await _databaseService.database;
    if (db == null) {
      return;
    }

    final targetSource = sourceBaseUrl ?? _sourceBaseUrl;
    await db.transaction((txn) async {
      await txn.delete(
        LocalDatabaseService.postCategoriesTable,
        where: 'source_base_url = ?',
        whereArgs: [targetSource],
      );
      await txn.delete(
        LocalDatabaseService.categoriesTable,
        where: 'source_base_url = ?',
        whereArgs: [targetSource],
      );
      await txn.delete(
        LocalDatabaseService.postsTable,
        where: 'source_base_url = ?',
        whereArgs: [targetSource],
      );
    });
  }

  Future<void> _upsertPost(
    dynamic db,
    WpPost post, {
    required bool allowEmptyContent,
  }) async {
    final existingRows = await db.query(
      LocalDatabaseService.postsTable,
      columns: ['content_html', 'is_detail_fetched'],
      where: 'id = ? AND source_base_url = ?',
      whereArgs: [post.id, post.sourceBaseUrl],
      limit: 1,
    );

    final existingContent = existingRows.isNotEmpty
        ? (existingRows.first['content_html'] as String?) ?? ''
        : '';
    final nextContent = allowEmptyContent && post.contentHtml.isEmpty
        ? existingContent
        : post.contentHtml;

    await db.insert(
      LocalDatabaseService.postsTable,
      {
        'id': post.id,
        'source_base_url': post.sourceBaseUrl,
        'slug': null,
        'title': post.title,
        'excerpt': post.excerpt,
        'content_html': nextContent,
        'author': post.author,
        'featured_image_url': post.featuredImageUrl,
        'categories_json': json.encode(post.categories),
        'category_ids_json': json.encode(post.categoryIds),
        'link': post.link,
        'read_minutes': post.readMinutes,
        'published_at': post.date.toIso8601String(),
        'modified_at': post.date.toIso8601String(),
        'fetched_at': DateTime.now().toIso8601String(),
        'is_detail_fetched': nextContent.isNotEmpty ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await db.delete(
      LocalDatabaseService.postCategoriesTable,
      where: 'source_base_url = ? AND post_id = ?',
      whereArgs: [post.sourceBaseUrl, post.id],
    );

    for (final categoryId in post.categoryIds) {
      await db.insert(
        LocalDatabaseService.postCategoriesTable,
        {
          'source_base_url': post.sourceBaseUrl,
          'post_id': post.id,
          'category_id': categoryId,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  WpPost _postFromRow(Map<String, Object?> row, {String? sourceBaseUrl}) {
    List<String> categories = const [];
    final categoriesRaw = row['categories_json'] as String?;
    if (categoriesRaw != null && categoriesRaw.isNotEmpty) {
      try {
        categories = (json.decode(categoriesRaw) as List<dynamic>)
            .map((item) => item.toString())
            .toList();
      } catch (_) {}
    }

    List<int> categoryIds = const [];
    final categoryIdsRaw = row['category_ids_json'] as String?;
    if (categoryIdsRaw != null && categoryIdsRaw.isNotEmpty) {
      try {
        categoryIds = (json.decode(categoryIdsRaw) as List<dynamic>)
            .whereType<int>()
            .toList();
      } catch (_) {}
    }

    return WpPost(
      sourceBaseUrl: _resolveSourceBaseUrl(sourceBaseUrl),
      id: row['id'] as int,
      title: (row['title'] as String?) ?? 'Untitled',
      excerpt: (row['excerpt'] as String?) ?? '',
      contentHtml: (row['content_html'] as String?) ?? '',
      author: (row['author'] as String?) ?? 'Unknown',
      date:
          DateTime.tryParse((row['published_at'] as String?) ?? '') ??
          DateTime.now(),
      featuredImageUrl: row['featured_image_url'] as String?,
      categories: categories,
      categoryIds: categoryIds,
      link: (row['link'] as String?) ?? '',
      readMinutes: (row['read_minutes'] as int?) ?? 1,
    );
  }
}
