import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../config.dart';
import '../models/ai_models.dart';
import '../models/wp_models.dart';
import 'blog_source_service.dart';
import 'local_database_service.dart';

class AiService {
  static final AiService _instance = AiService._internal();

  factory AiService() => _instance;

  AiService._internal({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;
  final Map<String, AiSummary> _summaryCache = <String, AiSummary>{};
  final Map<String, List<AiMessage>> _chatCache = <String, List<AiMessage>>{};
  final LocalDatabaseService _databaseService = LocalDatabaseService();
  final BlogSourceService _blogSource = BlogSourceService();

  AiSummary? getCachedSummary(int postId, {String? sourceBaseUrl}) =>
      _summaryCache[_postKey(postId, sourceBaseUrl)];

  Future<AiSummary?> getStoredSummary(
    int postId, {
    String? sourceBaseUrl,
  }) async {
    final resolvedSource = _normalizeSource(sourceBaseUrl);
    final key = _postKey(postId, resolvedSource);
    final memorySummary = _summaryCache[key];
    if (memorySummary != null) {
      return memorySummary;
    }

    if (!_databaseService.isSupported) {
      return null;
    }

    final db = await _databaseService.database;
    if (db == null) {
      return null;
    }

    final rows = await db.query(
      LocalDatabaseService.aiSummariesTable,
      where: 'post_id = ? AND source_base_url = ?',
      whereArgs: [postId, resolvedSource],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    final summary = _summaryFromRow(rows.first);
    _summaryCache[key] = summary;
    return summary;
  }

  Future<void> cacheSummary(
    int postId,
    AiSummary summary, {
    String? sourceBaseUrl,
  }) async {
    final resolvedSource = _normalizeSource(sourceBaseUrl);
    _summaryCache[_postKey(postId, resolvedSource)] = summary;

    if (!_databaseService.isSupported) {
      return;
    }

    final db = await _databaseService.database;
    if (db == null) {
      return;
    }

    await db.insert(
      LocalDatabaseService.aiSummariesTable,
      {
        'post_id': postId,
        'source_base_url': resolvedSource,
        'summary': summary.summary,
        'key_points_json': jsonEncode(summary.keyPoints),
        'keywords_json': jsonEncode(summary.keywords),
        'provider': 'proxy',
        'model': AppConfig.aiProxyBaseUrl,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> clearSummaryCache(int postId, {String? sourceBaseUrl}) async {
    final resolvedSource = _normalizeSource(sourceBaseUrl);
    _summaryCache.remove(_postKey(postId, resolvedSource));

    if (!_databaseService.isSupported) {
      return;
    }

    final db = await _databaseService.database;
    if (db == null) {
      return;
    }

    await db.delete(
      LocalDatabaseService.aiSummariesTable,
      where: 'post_id = ? AND source_base_url = ?',
      whereArgs: [postId, resolvedSource],
    );
  }

  Future<List<AiMessage>> getChatHistory(
    int postId, {
    String? sourceBaseUrl,
  }) async {
    final resolvedSource = _normalizeSource(sourceBaseUrl);
    final key = _postKey(postId, resolvedSource);
    final memoryMessages = _chatCache[key];
    if (memoryMessages != null) {
      return memoryMessages.map(_copyMessage).toList();
    }

    if (!_databaseService.isSupported) {
      return const [];
    }

    final db = await _databaseService.database;
    if (db == null) {
      return const [];
    }

    final rows = await db.query(
      LocalDatabaseService.aiMessagesTable,
      where: 'post_id = ? AND source_base_url = ?',
      whereArgs: [postId, resolvedSource],
      orderBy: 'created_at ASC',
    );

    final messages = rows.map(_messageFromRow).toList();
    _chatCache[key] = messages.map(_copyMessage).toList();
    return messages;
  }

  Future<void> saveChatHistory(
    int postId,
    List<AiMessage> messages, {
    String? sourceBaseUrl,
  }) async {
    final resolvedSource = _normalizeSource(sourceBaseUrl);
    final key = _postKey(postId, resolvedSource);
    _chatCache[key] = messages.map(_copyMessage).toList();

    if (!_databaseService.isSupported) {
      return;
    }

    final db = await _databaseService.database;
    if (db == null) {
      return;
    }

    await db.transaction((txn) async {
      await txn.delete(
        LocalDatabaseService.aiMessagesTable,
        where: 'post_id = ? AND source_base_url = ?',
        whereArgs: [postId, resolvedSource],
      );

      for (final message in messages) {
        await txn.insert(
          LocalDatabaseService.aiMessagesTable,
          {
            'id': message.id,
            'post_id': postId,
            'source_base_url': resolvedSource,
            'role': _serializeMessage(message)['role'],
            'content': message.content,
            'created_at': message.timestamp.toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<AiSummary> summarizeArticle(WpPost post) async {
    final payload = await _postJson(
      '/api/ai/summarize',
      {'post': _serializePost(post)},
    );

    final text = (payload['text'] as String?)?.trim();
    if (text == null || text.isEmpty) {
      throw const AiServiceException(
        message: 'AI 返回内容为空，请稍后重试',
      );
    }

    return _parseSummaryResponse(text);
  }

  Stream<String> chatWithArticle({
    required WpPost post,
    required String userMessage,
    required List<AiMessage> history,
  }) async* {
    final payload = await _postJson(
      '/api/ai/chat',
      {
        'post': _serializePost(post),
        'userMessage': userMessage,
        'history': history.map(_serializeMessage).toList(),
      },
    );

    final reply = (payload['reply'] as String?)?.trim();
    if (reply == null || reply.isEmpty) {
      throw const AiServiceException(
        message: '对话失败，请稍后重试',
      );
    }

    yield reply;
  }

  Future<void> resetChat(int postId, {String? sourceBaseUrl}) async {
    final resolvedSource = _normalizeSource(sourceBaseUrl);
    _chatCache.remove(_postKey(postId, resolvedSource));

    if (!_databaseService.isSupported) {
      return;
    }

    final db = await _databaseService.database;
    if (db == null) {
      return;
    }

    await db.delete(
      LocalDatabaseService.aiMessagesTable,
      where: 'post_id = ? AND source_base_url = ?',
      whereArgs: [postId, resolvedSource],
    );
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    if (!AppConfig.hasAiProxy) {
      throw const AiServiceException(
        message: 'AI 代理未配置：请设置 AI_PROXY_BASE_URL',
      );
    }

    late final http.Response response;
    try {
      response = await _client.post(
        _resolveUri(path),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
    } on Exception {
      throw AiServiceException(
        message: 'AI 请求失败，请检查网络连接',
      );
    }

    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      throw AiServiceException(
        message: 'AI 代理返回了无法解析的响应（HTTP ${response.statusCode}）',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded['error'];
      if (error is Map<String, dynamic>) {
        final message = (error['message'] as String?)?.trim();
        final details = error['details'];
        final formattedDetails = _formatDetails(details);
        throw AiServiceException(
          message: [
            message ?? 'AI 请求失败（HTTP ${response.statusCode}）',
            formattedDetails,
          ].join('\n\n'),
        );
      }

      throw AiServiceException(
        message: 'AI 请求失败（HTTP ${response.statusCode}）',
      );
    }

    return decoded;
  }

  Uri _resolveUri(String path) {
    final base = AppConfig.aiProxyBaseUrl.trim();
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;

    if (base.startsWith('http://') || base.startsWith('https://')) {
      final baseUri = Uri.parse(base.endsWith('/') ? base : '$base/');
      return baseUri.resolve(normalizedPath);
    }

    final relativeBase = base.startsWith('/') ? base : '/$base';
    final baseUri =
        Uri.base.resolve(relativeBase.endsWith('/') ? relativeBase : '$relativeBase/');
    return baseUri.resolve(normalizedPath);
  }

  Map<String, dynamic> _serializePost(WpPost post) {
    return {
      'id': post.id,
      'title': post.title,
      'author': post.author,
      'date': post.date.toIso8601String(),
      'categories': post.categories,
      'contentHtml': post.contentHtml,
      'excerpt': post.excerpt,
      'link': post.link,
    };
  }

  Map<String, dynamic> _serializeMessage(AiMessage message) {
    final role = switch (message.role) {
      AiMessageRole.user => 'user',
      AiMessageRole.assistant => 'assistant',
      AiMessageRole.system => 'system',
    };

    return {
      'role': role,
      'content': message.content,
      'isError': message.isError,
    };
  }

  String get _sourceBaseUrl => _blogSource.baseUrl.value.trim();

  String _normalizeSource(String? sourceBaseUrl) =>
      (sourceBaseUrl ?? _sourceBaseUrl).trim();

  String _postKey(int postId, [String? sourceBaseUrl]) =>
      '${_normalizeSource(sourceBaseUrl)}::$postId';

  AiSummary _summaryFromRow(Map<String, Object?> row) {
    return AiSummary(
      summary: (row['summary'] as String?) ?? '',
      keyPoints: _decodeStringList(row['key_points_json'] as String?),
      keywords: _decodeStringList(row['keywords_json'] as String?),
    );
  }

  AiMessage _messageFromRow(Map<String, Object?> row) {
    return AiMessage(
      id: (row['id'] as String?) ?? AiMessage.generateId(),
      content: (row['content'] as String?) ?? '',
      role: _deserializeRole((row['role'] as String?) ?? 'assistant'),
      timestamp: DateTime.tryParse((row['created_at'] as String?) ?? ''),
      isStreaming: false,
      isError: false,
    );
  }

  AiMessageRole _deserializeRole(String role) {
    switch (role) {
      case 'user':
        return AiMessageRole.user;
      case 'system':
        return AiMessageRole.system;
      default:
        return AiMessageRole.assistant;
    }
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

  AiMessage _copyMessage(AiMessage message) {
    return AiMessage(
      id: message.id,
      content: message.content,
      role: message.role,
      timestamp: message.timestamp,
      isStreaming: message.isStreaming,
      isError: message.isError,
    );
  }

  String? _formatDetails(Object? details) {
    if (details == null) {
      return null;
    }

    if (details is Map<String, dynamic>) {
      final items = <String>[];
      details.forEach((key, value) {
        if (value == null) {
          return;
        }
        final text = value is String ? value : jsonEncode(value);
        items.add('$key: $text');
      });
      if (items.isEmpty) {
        return null;
      }
      return '调试信息：\n${items.map((item) => '- $item').join('\n')}';
    }

    if (details is List && details.isNotEmpty) {
      return '调试信息：\n- ${jsonEncode(details)}';
    }

    return '调试信息：\n- $details';
  }

  AiSummary _parseSummaryResponse(String text) {
    var summary = '';
    var keyPoints = <String>[];
    var keywords = <String>[];

    final summaryMatch =
        RegExp(r'【摘要】\s*([\s\S]*?)(?=【|$)').firstMatch(text);
    if (summaryMatch != null) {
      summary = summaryMatch.group(1)?.trim() ?? '';
    }

    final pointsMatch =
        RegExp(r'【关键要点】\s*([\s\S]*?)(?=【|$)').firstMatch(text);
    if (pointsMatch != null) {
      final pointsText = pointsMatch.group(1)?.trim() ?? '';
      keyPoints = pointsText
          .split('\n')
          .map(
            (line) =>
                line.replaceAll(RegExp(r'^[\*\-\d+.、]+\s*'), '').trim(),
          )
          .where((line) => line.isNotEmpty)
          .toList();
    }

    final keywordsMatch =
        RegExp(r'【关键词】\s*([\s\S]*?)(?=【|$)').firstMatch(text);
    if (keywordsMatch != null) {
      final keywordsText = keywordsMatch.group(1)?.trim() ?? '';
      keywords = keywordsText
          .split(RegExp(r'[、,，\s]+'))
          .where((item) => item.isNotEmpty)
          .toList();
    }

    if (summary.isEmpty && keyPoints.isEmpty) {
      summary = text.trim();
    }

    return AiSummary(
      summary: summary,
      keyPoints: keyPoints,
      keywords: keywords,
    );
  }
}

class AiServiceException implements Exception {
  const AiServiceException({required this.message});

  final String message;

  @override
  String toString() => message;
}
