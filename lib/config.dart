class AppConfig {
  static const String wordpressBaseUrl = String.fromEnvironment(
    'WP_BASE_URL',
    defaultValue: 'https://blog.nishiki.icu',
  );

  static bool get hasValidBaseUrl =>
      wordpressBaseUrl.startsWith('http://') ||
      wordpressBaseUrl.startsWith('https://');

  static const String aiProxyBaseUrl = String.fromEnvironment(
    'AI_PROXY_BASE_URL',
    defaultValue: 'https://app.nishiki.tech',
  );

  static bool get hasAiProxy {
    final value = aiProxyBaseUrl.trim();
    if (value.isEmpty) {
      return false;
    }
    return value.startsWith('http://') ||
        value.startsWith('https://') ||
        value.startsWith('/');
  }

  static Uri resolveApiUri(String path) {
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    final base = aiProxyBaseUrl.trim();

    if (base.startsWith('http://') || base.startsWith('https://')) {
      final baseUri = Uri.parse(base.endsWith('/') ? base : '$base/');
      return baseUri.resolve(normalizedPath);
    }

    final relativeBase = base.startsWith('/') ? base : '/$base';
    final baseUri = Uri.base.resolve(
      relativeBase.endsWith('/') ? relativeBase : '$relativeBase/',
    );
    return baseUri.resolve(normalizedPath);
  }

  static Uri resolveWebSocketUri(String token) {
    final httpUri = resolveApiUri('/ws');
    final scheme = httpUri.scheme == 'https' ? 'wss' : 'ws';
    return httpUri.replace(
      scheme: scheme,
      queryParameters: {...httpUri.queryParameters, 'token': token},
    );
  }
}
