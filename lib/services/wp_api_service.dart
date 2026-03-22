import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/wp_models.dart';
import 'blog_source_service.dart';
import 'post_cache_service.dart';

enum WpApiErrorType { network, config, server, unknown }

class WpApiException implements Exception {
  const WpApiException({
    required this.type,
    required this.userMessage,
    this.technicalMessage,
    this.statusCode,
    this.canRetry = true,
    this.showConfigEntry = false,
  });

  final WpApiErrorType type;
  final String userMessage;
  final String? technicalMessage;
  final int? statusCode;
  final bool canRetry;
  final bool showConfigEntry;

  @override
  String toString() => userMessage;
}

class WpApiService {
  WpApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final BlogSourceService _blogSource = BlogSourceService();
  final PostCacheService _postCache = PostCacheService();

  Future<List<WpCategory>> getCachedCategories() {
    return _postCache.getCachedCategories();
  }

  Future<List<WpPost>> getCachedPosts({
    String search = '',
    int? categoryId,
    int page = 1,
  }) async {
    if (_blogSource.mode.value == BlogSourceMode.aggregate) {
      final merged = <WpPost>[];
      final limit = page * 12;
      for (final source in _blogSource.activeSources) {
        final cached = await _postCache.getCachedPosts(
          search: search,
          categoryId: categoryId,
          limit: limit,
          offset: 0,
          sourceBaseUrl: source,
        );
        merged.addAll(cached);
      }
      return _sliceAggregatedPosts(merged, page: page);
    }

    return _postCache.getCachedPosts(
      search: search,
      categoryId: categoryId,
      limit: 12,
      offset: (page - 1) * 12,
    );
  }

  Future<WpPost?> getCachedPostById(int postId, {String? sourceBaseUrl}) {
    return _postCache.getCachedPostById(
      postId,
      sourceBaseUrl: sourceBaseUrl,
    );
  }

  Uri _buildUri(
    String path, [
    Map<String, String>? query,
    String? sourceBaseUrl,
  ]) {
    final base = (sourceBaseUrl ?? _blogSource.baseUrl.value).trim();
    final normalizedBase =
        base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$normalizedBase$normalizedPath')
        .replace(queryParameters: query);
  }

  Future<List<WpCategory>> fetchCategories() async {
    if (_blogSource.mode.value == BlogSourceMode.aggregate) {
      final merged = <int, WpCategory>{};
      for (final source in _blogSource.activeSources) {
        final categories = await _fetchCategoriesFromSource(source);
        for (final category in categories) {
          merged.putIfAbsent(category.id, () => category);
        }
      }
      final result = merged.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return result;
    }

    return _fetchCategoriesFromSource(_blogSource.baseUrl.value.trim());
  }

  Future<List<WpCategory>> _fetchCategoriesFromSource(String sourceBaseUrl) async {
    final uri = _buildUri('/wp-json/wp/v2/categories', {
      'per_page': '50',
      'hide_empty': 'true',
      'orderby': 'count',
      'order': 'desc',
    }, sourceBaseUrl);

    try {
      final response = await _safeGet(uri);
      _ensureSuccess(response);

      final data = jsonDecode(response.body) as List<dynamic>;
      final categories = data
          .whereType<Map<String, dynamic>>()
          .map(WpCategory.fromJson)
          .toList();
      if (_blogSource.mode.value == BlogSourceMode.single) {
        await _postCache.cacheCategories(categories);
      }
      return categories;
    } catch (error) {
      final cached = await _postCache.getCachedCategories(
        sourceBaseUrl: sourceBaseUrl,
      );
      if (cached.isNotEmpty) {
        return cached;
      }
      rethrow;
    }
  }

  Future<List<WpPost>> fetchPosts({
    String search = '',
    int? categoryId,
    int page = 1,
  }) async {
    if (_blogSource.mode.value == BlogSourceMode.aggregate) {
      return _fetchAggregatedPosts(
        search: search,
        categoryId: categoryId,
        page: page,
      );
    }

    return _fetchPostsFromSource(
      _blogSource.baseUrl.value.trim(),
      search: search,
      categoryId: categoryId,
      page: page,
    );
  }

  Future<List<WpPost>> _fetchPostsFromSource(
    String sourceBaseUrl, {
    String search = '',
    int? categoryId,
    int page = 1,
  }) async {
    final query = <String, String>{
      'per_page': '12',
      'page': '$page',
      '_embed': '1',
      'orderby': 'date',
      'order': 'desc',
    };

    if (search.trim().isNotEmpty) {
      query['search'] = search.trim();
    }
    if (categoryId != null) {
      query['categories'] = '$categoryId';
    }

    final uri = _buildUri('/wp-json/wp/v2/posts', query, sourceBaseUrl);

    try {
      final response = await _safeGet(uri);
      if (response.statusCode == 400 &&
          response.body.contains('rest_post_invalid_page_number')) {
        return const [];
      }
      _ensureSuccess(response);

      final data = jsonDecode(response.body) as List<dynamic>;
      final posts = data
          .whereType<Map<String, dynamic>>()
          .map((item) => WpPost.fromJson(item, sourceBaseUrl: sourceBaseUrl))
          .toList();
      await _postCache.cachePosts(posts);
      return posts;
    } catch (error) {
      final cached = await _postCache.getCachedPosts(
        search: search,
        categoryId: categoryId,
        limit: 12,
        offset: (page - 1) * 12,
        sourceBaseUrl: sourceBaseUrl,
      );
      if (cached.isNotEmpty) {
        return cached;
      }
      rethrow;
    }
  }

  Future<List<WpPost>> _fetchAggregatedPosts({
    String search = '',
    int? categoryId,
    int page = 1,
  }) async {
    final merged = <WpPost>[];
    final perSourceTargetPage = page.clamp(1, 8);

    try {
      for (final source in _blogSource.activeSources) {
        for (int currentPage = 1; currentPage <= perSourceTargetPage; currentPage++) {
          final posts = await _fetchPostsFromSource(
            source,
            search: search,
            categoryId: categoryId,
            page: currentPage,
          );
          if (posts.isEmpty) {
            break;
          }
          merged.addAll(posts);
        }
      }
      return _sliceAggregatedPosts(merged, page: page);
    } catch (_) {
      final cached = await getCachedPosts(
        search: search,
        categoryId: categoryId,
        page: page,
      );
      if (cached.isNotEmpty) {
        return cached;
      }
      rethrow;
    }
  }

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
    if (start >= sorted.length) {
      return const [];
    }
    final end = (start + 12).clamp(0, sorted.length);
    return sorted.sublist(start, end);
  }

  Future<WpPost?> fetchPostById(int postId, {String? sourceBaseUrl}) async {
    final resolvedSource = (sourceBaseUrl ?? _blogSource.baseUrl.value).trim();
    final uri = _buildUri(
      '/wp-json/wp/v2/posts/$postId',
      {
        '_embed': '1',
      },
      resolvedSource,
    );

    try {
      final response = await _safeGet(uri);
      _ensureSuccess(response);

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final post = WpPost.fromJson(
        data,
        sourceBaseUrl: resolvedSource,
      );
      await _postCache.cachePostDetail(post);
      return post;
    } catch (error) {
      final cached = await _postCache.getCachedPostById(
        postId,
        sourceBaseUrl: resolvedSource,
      );
      if (cached != null) {
        return cached;
      }
      rethrow;
    }
  }

  Future<http.Response> _safeGet(Uri uri) async {
    try {
      return await _client.get(uri).timeout(const Duration(seconds: 10));
    } on TimeoutException catch (error) {
      throw WpApiException(
        type: WpApiErrorType.network,
        userMessage: '请求超时，请检查网络或博客地址是否可访问。',
        technicalMessage: error.toString(),
      );
    } catch (error) {
      throw WpApiException(
        type: WpApiErrorType.network,
        userMessage: '无法连接到博客数据源，请检查地址或网络环境。',
        technicalMessage: error.toString(),
      );
    }
  }

  void _ensureSuccess(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    final currentBaseUrl = _blogSource.baseUrl.value;
    if (currentBaseUrl.trim().isEmpty) {
      throw const WpApiException(
        type: WpApiErrorType.config,
        userMessage: '请先在应用内填写 WordPress 博客地址。',
        technicalMessage: 'WordPress base URL is empty.',
        canRetry: false,
        showConfigEntry: true,
      );
    }

    final statusCode = response.statusCode;
    if (statusCode == 401 || statusCode == 403) {
      throw WpApiException(
        type: WpApiErrorType.server,
        userMessage: '博客地址可访问，但当前站点拒绝了 WordPress API 请求。',
        statusCode: statusCode,
        showConfigEntry: true,
      );
    }

    if (statusCode == 404) {
      throw WpApiException(
        type: WpApiErrorType.server,
        userMessage: '没有找到 WordPress REST API，请检查博客地址是否正确。',
        statusCode: statusCode,
        showConfigEntry: true,
      );
    }

    throw WpApiException(
      type: WpApiErrorType.server,
      userMessage: '博客接口返回异常（HTTP $statusCode），请检查站点配置。',
      technicalMessage: response.body,
      statusCode: statusCode,
      showConfigEntry: true,
    );
  }
}
