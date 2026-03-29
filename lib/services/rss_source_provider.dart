// RSS/Atom 来源 Provider — 负责拉取和解析 RSS/Atom feed
//
// 将 RSS 条目转化为现有 WpPost 模型，直接复用 PostCacheService 缓存链路。
// 分类通过文本 hashCode 映射为稳定 int ID，适配现有分类筛选 UI。

import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../models/wp_models.dart';
import 'post_cache_service.dart';

/// RSS 源 Provider — 拉取 feed 并解析为 WpPost 列表
class RssSourceProvider {
  RssSourceProvider({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final PostCacheService _postCache = PostCacheService();

  /// 请求超时时间
  static const Duration _timeout = Duration(seconds: 12);

  /// 每页文章数（与 WP 一致）
  static const int _pageSize = 12;

  // ==================== 公共接口（与 WpApiService 对齐） ====================

  /// 拉取 RSS 文章列表（支持搜索、分类筛选、分页）
  Future<List<WpPost>> fetchPosts({
    required String feedUrl,
    required String sourceBaseUrl,
    String search = '',
    int? categoryId,
    int page = 1,
  }) async {
    // 拉取并解析全量 feed
    final allPosts = await _fetchAndParseFeed(feedUrl, sourceBaseUrl);

    // 缓存到 SQLite（复用现有缓存链路）
    if (allPosts.isNotEmpty) {
      await _postCache.cachePosts(allPosts);
    }

    // 本地过滤 + 分页
    var filtered = allPosts;

    // 搜索过滤
    if (search.trim().isNotEmpty) {
      final keyword = search.trim().toLowerCase();
      filtered = filtered
          .where(
            (post) =>
                post.title.toLowerCase().contains(keyword) ||
                post.excerpt.toLowerCase().contains(keyword),
          )
          .toList();
    }

    // 分类筛选
    if (categoryId != null) {
      filtered = filtered
          .where((post) => post.categoryIds.contains(categoryId))
          .toList();
    }

    // 分页切片
    final start = (page - 1) * _pageSize;
    if (start >= filtered.length) return const [];
    final end = (start + _pageSize).clamp(0, filtered.length);
    return filtered.sublist(start, end);
  }

  /// 获取指定文章详情（从缓存中取）
  Future<WpPost?> fetchPostById(
    int postId, {
    required String sourceBaseUrl,
  }) async {
    return _postCache.getCachedPostById(postId, sourceBaseUrl: sourceBaseUrl);
  }

  /// 获取 RSS 源的分类列表（从已缓存的文章中提取）
  Future<List<WpCategory>> fetchCategories({
    required String feedUrl,
    required String sourceBaseUrl,
  }) async {
    // 拉取最新 feed 获取分类信息
    final allPosts = await _fetchAndParseFeed(feedUrl, sourceBaseUrl);

    // 从文章中收集所有分类
    final categoryMap = <int, String>{};
    for (final post in allPosts) {
      for (int i = 0; i < post.categoryIds.length; i++) {
        if (i < post.categories.length) {
          categoryMap[post.categoryIds[i]] = post.categories[i];
        }
      }
    }

    // 缓存分类
    final categories = categoryMap.entries
        .map((entry) => WpCategory(id: entry.key, name: entry.value))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    if (categories.isNotEmpty) {
      await _postCache.cacheCategories(categories);
    }

    return categories;
  }

  // ==================== 内部方法 ====================

  /// 拉取 feed XML 并解析为 WpPost 列表
  Future<List<WpPost>> _fetchAndParseFeed(
    String feedUrl,
    String sourceBaseUrl,
  ) async {
    final uri = Uri.parse(feedUrl);
    final http.Response response;

    try {
      response = await _client.get(uri).timeout(_timeout);
    } on TimeoutException {
      throw const RssParseException('RSS 源请求超时，请检查网络或地址。');
    } catch (e) {
      throw RssParseException('无法连接到 RSS 源：${e.toString()}');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RssParseException(
        'RSS 源返回异常（HTTP ${response.statusCode}）',
      );
    }

    try {
      final document = XmlDocument.parse(response.body);
      final root = document.rootElement;

      // 根据根元素判断 feed 格式
      if (root.name.local == 'rss') {
        return _parseRss2(root, sourceBaseUrl);
      } else if (root.name.local == 'feed') {
        return _parseAtom(root, sourceBaseUrl);
      } else if (root.name.local == 'RDF') {
        return _parseRdf(root, sourceBaseUrl);
      }

      throw const RssParseException('无法识别的 feed 格式');
    } on RssParseException {
      rethrow;
    } catch (e) {
      throw RssParseException('RSS 解析失败：${e.toString()}');
    }
  }

  /// 解析 RSS 2.0 格式
  List<WpPost> _parseRss2(XmlElement root, String sourceBaseUrl) {
    final channel = root.findElements('channel').firstOrNull;
    if (channel == null) return const [];

    final items = channel.findElements('item');
    return items.map((item) => _rss2ItemToPost(item, sourceBaseUrl)).toList();
  }

  /// 解析 Atom 格式
  List<WpPost> _parseAtom(XmlElement root, String sourceBaseUrl) {
    final entries = root.findElements('entry');
    return entries.map((entry) => _atomEntryToPost(entry, sourceBaseUrl)).toList();
  }

  /// 解析 RDF (RSS 1.0) 格式
  List<WpPost> _parseRdf(XmlElement root, String sourceBaseUrl) {
    final items = root.findElements('item');
    return items.map((item) => _rss2ItemToPost(item, sourceBaseUrl)).toList();
  }

  /// RSS 2.0 item 转 WpPost
  WpPost _rss2ItemToPost(XmlElement item, String sourceBaseUrl) {
    final title = _getElementText(item, 'title') ?? 'Untitled';
    final link = _getElementText(item, 'link') ?? '';
    final guid = _getElementText(item, 'guid') ?? link;
    final description = _getElementText(item, 'description') ?? '';

    // 正文优先级：content:encoded > description
    final contentEncoded = _getContentEncoded(item);
    final contentHtml = contentEncoded ?? description;

    final author = _getElementText(item, 'author') ??
        _getElementText(item, 'dc:creator') ??
        'Unknown';
    final pubDate = _getElementText(item, 'pubDate');
    final date = _parseRssDate(pubDate);

    // 分类映射：RSS category 文本 → 稳定 int ID
    final categories = _extractRssCategories(item);
    final categoryNames = categories.map((c) => c.name).toList();
    final categoryIds = categories.map((c) => c.id).toList();

    // 尝试提取封面图
    final imageUrl = _extractImageUrl(item, contentHtml);

    // 文章 ID：guid 或 link 的稳定 hash
    final postId = _stableHashId(guid.isNotEmpty ? guid : link);

    final excerpt = htmlToText(description);
    final readMinutes = WpPost.estimateReadMinutesFromHtml(contentHtml);

    return WpPost(
      sourceBaseUrl: sourceBaseUrl,
      id: postId,
      title: htmlToText(title),
      excerpt: excerpt,
      contentHtml: contentHtml,
      author: _cleanAuthor(author),
      date: date,
      featuredImageUrl: imageUrl,
      categories: categoryNames,
      categoryIds: categoryIds,
      link: link,
      readMinutes: readMinutes,
    );
  }

  /// Atom entry 转 WpPost
  WpPost _atomEntryToPost(XmlElement entry, String sourceBaseUrl) {
    final title = _getElementText(entry, 'title') ?? 'Untitled';

    // Atom link：取 rel="alternate" 或第一个
    String link = '';
    for (final linkEl in entry.findElements('link')) {
      final rel = linkEl.getAttribute('rel') ?? 'alternate';
      if (rel == 'alternate') {
        link = linkEl.getAttribute('href') ?? '';
        break;
      }
    }
    if (link.isEmpty) {
      link = entry.findElements('link').firstOrNull?.getAttribute('href') ?? '';
    }

    final id = _getElementText(entry, 'id') ?? link;

    // Atom 正文：content > summary
    final contentEl = entry.findElements('content').firstOrNull;
    final summaryEl = entry.findElements('summary').firstOrNull;
    final contentHtml = contentEl?.innerText ?? summaryEl?.innerText ?? '';
    final excerpt = htmlToText(summaryEl?.innerText ?? contentHtml);

    // 作者
    final authorEl = entry.findElements('author').firstOrNull;
    final author = authorEl?.findElements('name').firstOrNull?.innerText ?? 'Unknown';

    // 日期
    final published = _getElementText(entry, 'published') ??
        _getElementText(entry, 'updated');
    final date = DateTime.tryParse(published ?? '') ?? DateTime.now();

    // 分类映射
    final categories = <WpCategory>[];
    for (final cat in entry.findElements('category')) {
      final term = cat.getAttribute('term') ?? cat.getAttribute('label');
      if (term != null && term.isNotEmpty) {
        categories.add(WpCategory(id: _stableHashId(term), name: term));
      }
    }

    final imageUrl = _extractImageUrl(entry, contentHtml);
    final postId = _stableHashId(id.isNotEmpty ? id : link);
    final readMinutes = WpPost.estimateReadMinutesFromHtml(contentHtml);

    return WpPost(
      sourceBaseUrl: sourceBaseUrl,
      id: postId,
      title: htmlToText(title),
      excerpt: excerpt,
      contentHtml: contentHtml,
      author: author,
      date: date,
      featuredImageUrl: imageUrl,
      categories: categories.map((c) => c.name).toList(),
      categoryIds: categories.map((c) => c.id).toList(),
      link: link,
      readMinutes: readMinutes,
    );
  }

  // ==================== 辅助方法 ====================

  /// 获取元素文本内容（兼容命名空间）
  String? _getElementText(XmlElement parent, String name) {
    // 先按本地名称搜索
    final el = parent.findElements(name).firstOrNull;
    if (el != null) return el.innerText.trim();
    return null;
  }

  /// 获取 content:encoded 内容（RSS 全文扩展）
  String? _getContentEncoded(XmlElement item) {
    // content:encoded 可能在不同命名空间下
    for (final child in item.children) {
      if (child is XmlElement) {
        if (child.name.local == 'encoded' ||
            child.name.qualified == 'content:encoded') {
          final text = child.innerText.trim();
          if (text.isNotEmpty) return text;
        }
      }
    }
    return null;
  }

  /// 提取 RSS 分类
  List<WpCategory> _extractRssCategories(XmlElement item) {
    final categories = <WpCategory>[];
    final seen = <String>{};

    for (final cat in item.findElements('category')) {
      final text = cat.innerText.trim();
      if (text.isNotEmpty && seen.add(text)) {
        categories.add(WpCategory(id: _stableHashId(text), name: text));
      }
    }

    return categories;
  }

  /// 尝试从 feed 条目或 HTML 中提取封面图
  String? _extractImageUrl(XmlElement item, String contentHtml) {
    // 1. 检查 enclosure 标签（type 为 image/*）
    for (final enc in item.findElements('enclosure')) {
      final type = enc.getAttribute('type') ?? '';
      if (type.startsWith('image/')) {
        final url = enc.getAttribute('url');
        if (url != null && url.isNotEmpty) return url;
      }
    }

    // 2. 检查 media:thumbnail 或 media:content
    for (final child in item.children) {
      if (child is XmlElement) {
        if (child.name.local == 'thumbnail' ||
            child.name.local == 'content') {
          final url = child.getAttribute('url');
          final medium = child.getAttribute('medium');
          if (url != null &&
              url.isNotEmpty &&
              (medium == 'image' || medium == null)) {
            return url;
          }
        }
      }
    }

    // 3. 从 HTML 正文中提取第一张 img 的 src
    final imgPattern = RegExp('<img[^>]+src=["\u0027]([^"\u0027]+)["\u0027]');
    final imgMatch = imgPattern.firstMatch(contentHtml);
    if (imgMatch != null) {
      return imgMatch.group(1);
    }

    return null;
  }

  /// 生成稳定的正整数 ID（基于字符串 hash）
  int _stableHashId(String input) {
    // 使用简单的 djb2 hash 保证稳定性
    int hash = 5381;
    for (int i = 0; i < input.length; i++) {
      hash = ((hash << 5) + hash) + input.codeUnitAt(i);
      hash = hash & 0x7FFFFFFF; // 保持为正整数
    }
    return hash == 0 ? 1 : hash;
  }

  /// 清理作者名（去除 email 包裹等）
  String _cleanAuthor(String raw) {
    // RSS 的 author 可能是 "email (Name)" 格式
    final match = RegExp(r'\((.+)\)$').firstMatch(raw);
    if (match != null) return match.group(1)!.trim();

    // 或纯 email，提取 @ 前的用户名
    if (raw.contains('@')) {
      return raw.split('@').first.trim();
    }

    return raw.trim().isEmpty ? 'Unknown' : raw.trim();
  }

  /// 解析 RSS 日期格式（RFC 822 / RFC 2822）
  DateTime _parseRssDate(String? dateStr) {
    if (dateStr == null || dateStr.trim().isEmpty) return DateTime.now();

    // 先尝试 ISO 8601
    final iso = DateTime.tryParse(dateStr);
    if (iso != null) return iso;

    // 尝试 RFC 822 格式：Wed, 02 Oct 2002 08:00:00 GMT
    try {
      final cleaned = dateStr
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      // 移除星期前缀（可选）
      final noDow = cleaned.replaceFirst(RegExp(r'^[A-Za-z]{3},?\s*'), '');

      // 解析：dd Mon yyyy HH:mm:ss TZ
      final parts = noDow.split(' ');
      if (parts.length >= 4) {
        final day = int.tryParse(parts[0]) ?? 1;
        final month = _monthNumber(parts[1]);
        final year = int.tryParse(parts[2]) ?? DateTime.now().year;

        final timeParts = parts[3].split(':');
        final hour = int.tryParse(timeParts.isNotEmpty ? timeParts[0] : '0') ?? 0;
        final minute = int.tryParse(timeParts.length > 1 ? timeParts[1] : '0') ?? 0;
        final second = int.tryParse(timeParts.length > 2 ? timeParts[2] : '0') ?? 0;

        return DateTime.utc(year, month, day, hour, minute, second);
      }
    } catch (_) {}

    return DateTime.now();
  }

  /// 月份缩写 → 数字
  int _monthNumber(String abbr) {
    const months = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4,
      'may': 5, 'jun': 6, 'jul': 7, 'aug': 8,
      'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    };
    return months[abbr.toLowerCase()] ?? 1;
  }
}

/// RSS 解析异常
class RssParseException implements Exception {
  const RssParseException(this.message);
  final String message;

  @override
  String toString() => message;
}
