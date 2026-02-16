class AppConfig {
  static const String wordpressBaseUrl = String.fromEnvironment(
    'WP_BASE_URL',
    defaultValue: 'https://blog.nishiki.icu',
  );

  static bool get hasValidBaseUrl =>
      wordpressBaseUrl.startsWith('http://') ||
      wordpressBaseUrl.startsWith('https://');
}
