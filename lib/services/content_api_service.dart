// 统一内容服务 — UI 层的唯一入口（Facade 模式）
//
// 取代 UI 层直接使用 WpApiService，按 sourceType 分发到：
//   - WpApiService（WordPress REST API）
//   - RssSourceProvider（RSS/Atom feed 解析）
//
// 对外暴露与原 WpApiService 完全一致的方法签名，UI 无需感知底层差异。

import 'dart:async';

import 'package:http/http.dart' as http;

import '../models/wp_models.dart';
import 'blog_source_service.dart';
import 'post_cache_service.dart';
import 'rss_source_provider.dart';
import 'wp_api_service.dart';

// ===== 统一异常类型（兼容 WpApiException） =====

/// 内容服务异常类型枚举
enum ContentApiErrorType { network, config, server, rss, unknown }

/// 内容服务统一异常
class ContentApiException implements Exception {
  const ContentApiException({
    required this.type,
    required this.userMessage,
    this.technicalMessage,
    this.statusCode,
    this.canRetry = true,
    this.showConfigEntry = false,
  });

  final ContentApiErrorType type;
  final String userMessage;
  final String? technicalMessage;
  final int? statusCode;
  final bool canRetry;
  final bool showConfigEntry;

  /// 从 WpApiException 构造
  factory ContentApiException.fromWpException(WpApiException e) {
    return ContentApiException(
      type: _mapWpErrorType(e.type),
      userMessage: e.userMessage,
      technicalMessage: e.technicalMessage,
      statusCode: e.statusCode,
      canRetry: e.canRetry,
      showConfigEntry: e.showConfigEntry,
    );
  }

  /// 从 RssParseException 构造
  factory ContentApiException.fromRssException(RssParseException e) {
    return ContentApiException(
      type: ContentApiErrorType.rss,
      userMessage: e.message,
      canRetry: true,
    );
  }

  static ContentApiErrorType _mapWpErrorType(WpApiErrorType type) {
    switch (type) {
      case WpApiErrorType.network:
        return ContentApiErrorType.network;
      case WpApiErrorType.config:
        return ContentApiErrorType.config;
      case WpApiErrorType.server:
        return ContentApiErrorType.server;
      case WpApiErrorType.unknown:
        return ContentApiErrorType.unknown;
    }
  }

  @override
  String toString() => userMessage;
}

/// 统一内容服务 — UI 层入口
class ContentApiService {
  ContentApiService({http.Client? client})
      : _wpApi = WpApiService(client: client),
        _rssProvider = RssSourceProvider(client: client);

  final WpApiService _wpApi;
  final RssSourceProvider _rssProvider;
  final BlogSourceService _blogSource = BlogSourceService();
  final PostCacheService _postCache = PostCacheService();

  // ==================== 分类相关 ====================

  /// 获取缓存中的分类
  Future<List<WpCategory>> getCachedCategories() {
    return _postCache.getCachedCategories();
  }

  /// 拉取分类列表（按当前 sourceType 分发）
  Future<List<WpCategory>> fetchCategories() async {
    try {
      final currentEntry = _blogSource.currentSourceEntry;

      // RSS 类型：从 feed 中提取分类
      if (currentEntry != null && currentEntry.isRss) {
        final feedUrl = currentEntry.feedUrl;
        if (feedUrl == null || feedUrl.isEmpty) {
          return const [];
        }
        return await _rssProvider.fetchCategories(
          feedUrl: feedUrl,
          sourceBaseUrl: currentEntry.baseUrl,
        );
      }

      // WordPress 类型或默认
      return await _wpApi.fetchCategories();
    } on WpApiException catch (e) {
      throw ContentApiException.fromWpException(e);
    } on RssParseException catch (e) {
      throw ContentApiException.fromRssException(e);
    }
  }

  // ==================== 文章列表 ====================

  /// 获取缓存中的文章（分页）
  Future<List<WpPost>> getCachedPosts({
    String search = '',
    int? categoryId,
    int page = 1,
  }) {
    return _wpApi.getCachedPosts(
      search: search,
      categoryId: categoryId,
      page: page,
    );
  }

  /// 拉取文章列表（按当前 sourceType 分发，支持聚合模式）
  Future<List<WpPost>> fetchPosts({
    String search = '',
    int? categoryId,
    int page = 1,
  }) async {
    try {
      // 聚合模式：可能混合 WP 和 RSS 源
      if (_blogSource.mode.value == BlogSourceMode.aggregate) {
        return await _fetchAggregatedPostsFast(
          search: search,
          categoryId: categoryId,
          page: page,
        );
      }

      // 单站点模式
      final currentEntry = _blogSource.currentSourceEntry;

      if (currentEntry != null && currentEntry.isRss) {
        final feedUrl = currentEntry.feedUrl;
        if (feedUrl == null || feedUrl.isEmpty) {
          throw const ContentApiException(
            type: ContentApiErrorType.config,
            userMessage: 'RSS 源的 Feed 地址为空，请重新添加。',
            canRetry: false,
            showConfigEntry: true,
          );
        }
        return await _rssProvider.fetchPosts(
          feedUrl: feedUrl,
          sourceBaseUrl: currentEntry.baseUrl,
          search: search,
          categoryId: categoryId,
          page: page,
        );
      }

      // WordPress 类型或默认
      return await _wpApi.fetchPosts(
        search: search,
        categoryId: categoryId,
        page: page,
      );
    } on ContentApiException {
      rethrow;
    } on WpApiException catch (e) {
      throw ContentApiException.fromWpException(e);
    } on RssParseException catch (e) {
      throw ContentApiException.fromRssException(e);
    }
  }

  // ==================== 文章详情 ====================

  /// 获取缓存中的文章详情
  Future<WpPost?> getCachedPostById(int postId, {String? sourceBaseUrl}) {
    return _wpApi.getCachedPostById(postId, sourceBaseUrl: sourceBaseUrl);
  }

  /// 拉取指定文章详情
  Future<WpPost?> fetchPostById(int postId, {String? sourceBaseUrl}) async {
    try {
      final resolvedSource = sourceBaseUrl ?? _blogSource.baseUrl.value.trim();
      final sourceEntry = _findSourceEntry(resolvedSource);

      // RSS 类型：直接从缓存取（feed 不支持按 ID 查单篇）
      if (sourceEntry != null && sourceEntry.isRss) {
        return await _rssProvider.fetchPostById(
          postId,
          sourceBaseUrl: resolvedSource,
        );
      }

      // WordPress 类型
      return await _wpApi.fetchPostById(postId, sourceBaseUrl: sourceBaseUrl);
    } on WpApiException catch (e) {
      throw ContentApiException.fromWpException(e);
    } on RssParseException catch (e) {
      throw ContentApiException.fromRssException(e);
    }
  }

  // ==================== 聚合模式 ====================

  /// 聚合拉取：混合 WP 和 RSS 源的文章
  Future<List<WpPost>> _fetchAggregatedPosts({
    String search = '',
    int? categoryId,
    int page = 1,
  }) async {
    final merged = <WpPost>[];

    for (final sourceUrl in _blogSource.activeSources) {
      final sourceEntry = _findSourceEntry(sourceUrl);

      try {
        List<WpPost> posts;

        if (sourceEntry != null && sourceEntry.isRss) {
          // RSS 源
          final feedUrl = sourceEntry.feedUrl;
          if (feedUrl == null || feedUrl.isEmpty) continue;

          posts = await _rssProvider.fetchPosts(
            feedUrl: feedUrl,
            sourceBaseUrl: sourceUrl,
            search: search,
            categoryId: categoryId,
            page: 1, // RSS 一次拉取全量，这里取第一页足够做聚合
          );
        } else {
          // WordPress 源：逐页拉取到目标页
          final perSourceTargetPage = page.clamp(1, 8);
          posts = <WpPost>[];
          for (int currentPage = 1;
              currentPage <= perSourceTargetPage;
              currentPage++) {
            final pagePosts = await _wpApi.fetchPosts(
              search: search,
              categoryId: categoryId,
              page: currentPage,
            );
            if (pagePosts.isEmpty) break;
            posts.addAll(pagePosts);
          }
        }

        merged.addAll(posts);
      } catch (_) {
        // 单个源失败不影响其他源
        continue;
      }
    }

    // 去重 + 按日期排序 + 分页
    return _sliceAggregatedPosts(merged, page: page);
  }

  /// 聚合分页：去重、排序、切片
  List<WpPost> _sliceAggregatedPosts(
    List<WpPost> posts, {
    required int page,
  }) {
    final deduped = <String, WpPost>{};
    for (final post in posts) {
      deduped.putIfAbsent('${post.sourceBaseUrl}::${post.id}', () => post);
    }
    final sorted = deduped.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final start = (page - 1) * 12;
    if (start >= sorted.length) return const [];
    final end = (start + 12).clamp(0, sorted.length);
    return sorted.sublist(start, end);
  }

  /// 查找指定 URL 对应的源条目（用于判断类型）
  BlogSiteSource? _findSourceEntry(String sourceBaseUrl) {
    for (final entry in _blogSource.sourceEntries.value) {
      if (entry.baseUrl == sourceBaseUrl) return entry;
    }
    return null;
  }

  Future<List<WpPost>> _fetchAggregatedPostsFast({
    String search = '',
    int? categoryId,
    int page = 1,
  }) async {
    final merged = <WpPost>[];
    final activeSources = _blogSource.activeSources;
    final perSourceTargetPage = page.clamp(1, 8);

    for (int currentPage = 1; currentPage <= perSourceTargetPage; currentPage++) {
      final roundResults = await Future.wait(
        activeSources.map((sourceUrl) async {
          final sourceEntry = _findSourceEntry(sourceUrl);

          try {
            if (sourceEntry != null && sourceEntry.isRss) {
              final feedUrl = sourceEntry.feedUrl;
              if (feedUrl == null || feedUrl.isEmpty || currentPage > 1) {
                return const <WpPost>[];
              }

              return await _rssProvider.fetchPosts(
                feedUrl: feedUrl,
                sourceBaseUrl: sourceUrl,
                search: search,
                categoryId: categoryId,
                page: 1,
              );
            }

            return await _wpApi.fetchPostsFromSource(
              sourceUrl,
              search: search,
              categoryId: categoryId,
              page: currentPage,
            );
          } catch (_) {
            return const <WpPost>[];
          }
        }),
      );

      var hadAnyPosts = false;
      for (final posts in roundResults) {
        if (posts.isNotEmpty) {
          hadAnyPosts = true;
          merged.addAll(posts);
        }
      }

      if (!hadAnyPosts) {
        break;
      }
    }

    return _sliceAggregatedPosts(merged, page: page);
  }
}
