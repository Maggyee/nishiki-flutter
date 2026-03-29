// URL 自动探测器 — 输入 URL 后自动识别来源类型（WordPress 或 RSS）
//
// 探测流程：
//   1. 尝试 GET {url}/wp-json/ → 200 且合法 JSON → wordpress
//   2. 尝试解析候选 feed 地址的 XML → 识别到 RSS/Atom → rss
//   3. 所有候选失败 → 抛出异常提示用户

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

/// 探测结果
class SourceDetectResult {
  const SourceDetectResult({
    required this.sourceType,
    required this.baseUrl,
    this.feedUrl,
    this.siteUrl,
    this.siteName,
  });

  /// 来源类型：'wordpress' | 'rss'
  final String sourceType;

  /// 标准化后的站点地址（作为唯一标识）
  final String baseUrl;

  /// RSS feed 实际地址（仅 rss 类型有值）
  final String? feedUrl;

  /// 站点主页地址（可选）
  final String? siteUrl;

  /// 自动探测到的站点名称（可选）
  final String? siteName;

  /// 是否为 RSS 类型
  bool get isRss => sourceType == 'rss';
}

/// 探测异常
class SourceDetectException implements Exception {
  const SourceDetectException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// URL 来源类型探测器
class SourceDetector {
  SourceDetector({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// 超时时间
  static const Duration _timeout = Duration(seconds: 8);

  /// RSS feed 候选后缀列表
  static const List<String> _feedCandidatePaths = [
    '', // 用户输入的 URL 本身可能就是 feed
    '/feed',
    '/rss',
    '/atom.xml',
    '/index.xml',
    '/feed.xml',
    '/rss.xml',
  ];

  /// 执行探测：输入 URL，返回识别结果
  Future<SourceDetectResult> detect(String inputUrl) async {
    final normalized = _normalizeUrl(inputUrl);
    if (normalized.isEmpty) {
      throw const SourceDetectException('请输入有效的 http:// 或 https:// 地址');
    }

    // 第一步：尝试 WordPress REST API
    final wpResult = await _tryWordPress(normalized);
    if (wpResult != null) return wpResult;

    // 第二步：尝试 RSS/Atom feed 候选
    final rssResult = await _tryRssFeed(normalized);
    if (rssResult != null) return rssResult;

    // 都失败了
    throw const SourceDetectException(
      '无法识别该地址，请确认它是 WordPress 站点或有效的 RSS 源。',
    );
  }

  /// 尝试 WordPress 探测：GET /wp-json/
  Future<SourceDetectResult?> _tryWordPress(String baseUrl) async {
    try {
      final uri = Uri.parse('$baseUrl/wp-json/');
      final response = await _client.get(uri).timeout(_timeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        // 验证返回是合法 JSON 且包含 WordPress 特征字段
        final body = jsonDecode(response.body);
        if (body is Map<String, dynamic> &&
            (body.containsKey('name') || body.containsKey('namespaces'))) {
          // 尝试获取站点名称
          final siteName = body['name'] as String?;
          return SourceDetectResult(
            sourceType: 'wordpress',
            baseUrl: baseUrl,
            siteName: siteName,
          );
        }
      }
    } catch (_) {
      // WordPress 探测失败，继续尝试 RSS
    }
    return null;
  }

  /// 尝试 RSS/Atom feed 探测：遍历候选地址
  Future<SourceDetectResult?> _tryRssFeed(String baseUrl) async {
    for (final suffix in _feedCandidatePaths) {
      final candidateUrl = suffix.isEmpty ? baseUrl : '$baseUrl$suffix';
      try {
        final uri = Uri.parse(candidateUrl);
        final response = await _client.get(uri).timeout(_timeout);

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final result = _parseAsRssFeed(response.body, baseUrl, candidateUrl);
          if (result != null) return result;
        }
      } catch (_) {
        // 该候选失败，尝试下一个
        continue;
      }
    }
    return null;
  }

  /// 解析 XML 判断是否为 RSS/Atom feed
  SourceDetectResult? _parseAsRssFeed(
    String body,
    String baseUrl,
    String feedUrl,
  ) {
    try {
      final document = XmlDocument.parse(body);
      final root = document.rootElement;

      // RSS 2.0：根元素为 <rss>
      if (root.name.local == 'rss') {
        final channel = root.findElements('channel').firstOrNull;
        final title = channel?.findElements('title').firstOrNull?.innerText;
        final link = channel?.findElements('link').firstOrNull?.innerText;
        return SourceDetectResult(
          sourceType: 'rss',
          baseUrl: baseUrl,
          feedUrl: feedUrl,
          siteUrl: link,
          siteName: title,
        );
      }

      // Atom：根元素为 <feed>（含 namespace）
      if (root.name.local == 'feed') {
        final title = root.findElements('title').firstOrNull?.innerText;
        // Atom 的 link 可能有多个，取 rel="alternate" 或第一个
        String? siteUrl;
        for (final link in root.findElements('link')) {
          final rel = link.getAttribute('rel') ?? 'alternate';
          if (rel == 'alternate') {
            siteUrl = link.getAttribute('href');
            break;
          }
        }
        siteUrl ??= root.findElements('link').firstOrNull?.getAttribute('href');

        return SourceDetectResult(
          sourceType: 'rss',
          baseUrl: baseUrl,
          feedUrl: feedUrl,
          siteUrl: siteUrl,
          siteName: title,
        );
      }

      // RDF (RSS 1.0)：根元素为 <rdf:RDF> 或 <RDF>
      if (root.name.local == 'RDF') {
        final channel = root.findElements('channel').firstOrNull;
        final title = channel?.findElements('title').firstOrNull?.innerText;
        final link = channel?.findElements('link').firstOrNull?.innerText;
        return SourceDetectResult(
          sourceType: 'rss',
          baseUrl: baseUrl,
          feedUrl: feedUrl,
          siteUrl: link,
          siteName: title,
        );
      }
    } catch (_) {
      // XML 解析失败，不是合法 feed
    }
    return null;
  }

  /// 标准化 URL：去除末尾斜杠、加上 https:// 前缀
  String _normalizeUrl(String input) {
    var trimmed = input.trim();
    if (trimmed.isEmpty) return '';

    // 自动补全协议
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      trimmed = 'https://$trimmed';
    }

    // 验证 URL 合法性
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.isEmpty) return '';

    // 去除末尾斜杠
    if (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }

    return trimmed;
  }
}
