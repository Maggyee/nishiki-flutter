import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/auth_models.dart';

class AuthServiceException implements Exception {
  const AuthServiceException(
    this.message, {
    this.statusCode,
    this.code,
  });

  final String message;
  final int? statusCode;
  final String? code;

  @override
  String toString() => message;
}

class AuthService {
  AuthService._internal({http.Client? client})
    : _client = client ?? http.Client();

  static final AuthService _instance = AuthService._internal();

  factory AuthService() => _instance;

  static const String _accessTokenKey = 'auth_access_token';
  static const String _refreshTokenKey = 'auth_refresh_token';
  static const String _userJsonKey = 'auth_user_json';

  final http.Client _client;

  String? _accessToken;
  String? _refreshToken;
  CurrentUser? _currentUser;

  CurrentUser? get currentUser => _currentUser;
  bool get isSignedIn =>
      (_accessToken?.isNotEmpty ?? false) &&
      (_refreshToken?.isNotEmpty ?? false) &&
      _currentUser != null;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString(_accessTokenKey);
    _refreshToken = prefs.getString(_refreshTokenKey);
    final rawUser = prefs.getString(_userJsonKey);
    if (rawUser?.isNotEmpty ?? false) {
      try {
        _currentUser = CurrentUser.fromJson(jsonDecode(rawUser!));
      } catch (_) {
        _currentUser = null;
      }
    }
  }

  Future<void> requestEmailCode(String email) async {
    await _postJson('/api/auth/email/request-code', {'email': email});
  }

  Future<AuthSession> verifyEmailCode(String email, String code) async {
    final payload = await _postJson('/api/auth/email/verify-code', {
      'email': email,
      'code': code,
    });
    final session = AuthSession.fromJson(payload);
    await _saveSession(session);
    return session;
  }

  Future<AuthSession> refreshSession() async {
    final refreshToken = _refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      throw const AuthServiceException('No refresh token available.');
    }

    final payload = await _postJson('/api/auth/refresh', {
      'refreshToken': refreshToken,
    });
    final session = AuthSession.fromJson(payload);
    await _saveSession(session);
    return session;
  }

  Future<void> logout() async {
    final refreshToken = _refreshToken;
    final body = <String, dynamic>{};
    if (refreshToken?.isNotEmpty ?? false) {
      body['refreshToken'] = refreshToken;
    }
    await _postJson('/api/auth/logout', body, includeAuth: true);
    await clearSession();
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_userJsonKey);
    _accessToken = null;
    _refreshToken = null;
    _currentUser = null;
  }

  Future<bool> ensureValidSession() async {
    if (!isSignedIn) {
      return false;
    }

    try {
      final payload = await authorizedGetJson('/api/me');
      final user = payload['user'];
      if (user is Map<String, dynamic>) {
        final nextUser = CurrentUser.fromJson(user);
        final prefs = await SharedPreferences.getInstance();
        _currentUser = nextUser;
        await prefs.setString(
          _userJsonKey,
          jsonEncode({
            'id': nextUser.id,
            'email': nextUser.email,
            'createdAt': nextUser.createdAt.toIso8601String(),
            'updatedAt': nextUser.updatedAt.toIso8601String(),
            'emailVerifiedAt': nextUser.emailVerifiedAt?.toIso8601String(),
          }),
        );
      }
      return true;
    } on AuthServiceException catch (error) {
      if (error.statusCode != 401) {
        rethrow;
      }
    }

    try {
      await refreshSession();
      return true;
    } on AuthServiceException {
      await clearSession();
      return false;
    }
  }

  Future<Map<String, dynamic>> authorizedPostJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    return _postJson(path, body, includeAuth: true);
  }

  Future<Map<String, dynamic>> authorizedGetJson(String path) async {
    return _getJson(path, includeAuth: true);
  }

  Map<String, String> buildAuthHeaders() {
    final token = _accessToken;
    if (token == null || token.isEmpty) {
      return const {};
    }
    return {'Authorization': 'Bearer $token'};
  }

  Future<void> _saveSession(AuthSession session) async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = session.accessToken;
    _refreshToken = session.refreshToken;
    _currentUser = session.user;
    await prefs.setString(_accessTokenKey, session.accessToken);
    await prefs.setString(_refreshTokenKey, session.refreshToken);
    await prefs.setString(
      _userJsonKey,
      jsonEncode({
        'id': session.user.id,
        'email': session.user.email,
        'createdAt': session.user.createdAt.toIso8601String(),
        'updatedAt': session.user.updatedAt.toIso8601String(),
        'emailVerifiedAt': session.user.emailVerifiedAt?.toIso8601String(),
      }),
    );
  }

  Future<Map<String, dynamic>> _getJson(
    String path, {
    bool includeAuth = false,
  }) async {
    final response = await _client.get(
      AppConfig.resolveApiUri(path),
      headers: {
        'Content-Type': 'application/json',
        if (includeAuth) ...buildAuthHeaders(),
      },
    );
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body, {
    bool includeAuth = false,
  }) async {
    final response = await _client.post(
      AppConfig.resolveApiUri(path),
      headers: {
        'Content-Type': 'application/json',
        if (includeAuth) ...buildAuthHeaders(),
      },
      body: jsonEncode(body),
    );
    return _decodeResponse(response);
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw AuthServiceException(
        'Invalid server response: ${response.statusCode}',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded['error'] as Map<String, dynamic>?;
      throw AuthServiceException(
        (error?['message'] as String?) ??
            'Request failed: ${response.statusCode}',
        statusCode: response.statusCode,
        code: error?['code'] as String?,
      );
    }

    return decoded;
  }
}
