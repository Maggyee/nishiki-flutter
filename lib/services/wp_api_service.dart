import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/wp_models.dart';

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

  Uri _buildUri(String path, [Map<String, String>? query]) {
    final base = AppConfig.wordpressBaseUrl;
    final normalizedBase = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$normalizedBase$normalizedPath').replace(queryParameters: query);
  }

  Future<List<WpCategory>> fetchCategories() async {
    final uri = _buildUri('/wp-json/wp/v2/categories', {
      'per_page': '50',
      'hide_empty': 'true',
      'orderby': 'count',
      'order': 'desc',
    });

    final response = await _safeGet(uri);
    _ensureSuccess(response);

    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .whereType<Map<String, dynamic>>()
        .map(WpCategory.fromJson)
        .toList();
  }

  Future<List<WpPost>> fetchPosts({
    String search = '',
    int? categoryId,
    int page = 1,
  }) async {
    final query = <String, String>{
      'per_page': '20',
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

    final uri = _buildUri('/wp-json/wp/v2/posts', query);
    final response = await _safeGet(uri);
    _ensureSuccess(response);

    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .whereType<Map<String, dynamic>>()
        .map(WpPost.fromJson)
        .toList();
  }

  /// 根据文章 ID 获取单篇文章的完整内容（含 _embed 数据）
  Future<WpPost?> fetchPostById(int postId) async {
    final uri = _buildUri('/wp-json/wp/v2/posts/$postId', {
      '_embed': '1',
    });

    final response = await _safeGet(uri);
    _ensureSuccess(response);

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return WpPost.fromJson(data);
  }

  Future<http.Response> _safeGet(Uri uri) async {
    try {
      return await _client.get(uri);
    } catch (e) {
      throw WpApiException(
        type: WpApiErrorType.network,
        userMessage: '无法连接到站点，请检查网络后重试。',
        technicalMessage: e.toString(),
        canRetry: true,
      );
    }
  }

  void _ensureSuccess(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    if (AppConfig.wordpressBaseUrl.contains('your-wordpress-site.com')) {
      throw const WpApiException(
        type: WpApiErrorType.config,
        userMessage: '站点地址未配置，请先设置 WordPress URL。',
        technicalMessage:
            'Please set your WordPress site URL via --dart-define=WP_BASE_URL=https://blog.nishiki.icu',
        canRetry: false,
        showConfigEntry: true,
      );
    }

    final statusCode = response.statusCode;
    if (statusCode == 401 || statusCode == 403) {
      throw WpApiException(
        type: WpApiErrorType.server,
        userMessage: '站点拒绝访问，请检查接口权限或安全策略。',
        statusCode: statusCode,
      );
    }

    if (statusCode == 404) {
      throw WpApiException(
        type: WpApiErrorType.server,
        userMessage: '未找到 WordPress REST API，请确认站点地址和接口路径。',
        statusCode: statusCode,
        showConfigEntry: true,
      );
    }

    throw WpApiException(
      type: WpApiErrorType.server,
      userMessage: '内容加载失败（HTTP $statusCode），请稍后重试。',
      technicalMessage: response.body,
      statusCode: statusCode,
    );
  }
}
