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
    defaultValue: 'https://blogapi.nishiki.icu',
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
}
