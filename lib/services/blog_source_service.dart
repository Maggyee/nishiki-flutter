import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

enum BlogSourceMode { single, aggregate }

class BlogSourceService {
  BlogSourceService._internal();

  static final BlogSourceService _instance = BlogSourceService._internal();

  factory BlogSourceService() => _instance;

  static const String _legacyWordpressBaseUrlKey = 'wordpress_base_url';
  static const String _wordpressSourcesKey = 'wordpress_sources';
  static const String _selectedWordpressSourceKey = 'selected_wordpress_source';
  static const String _wordpressSourceModeKey = 'wordpress_source_mode';

  final ValueNotifier<String> baseUrl =
      ValueNotifier(AppConfig.wordpressBaseUrl.trim());
  final ValueNotifier<List<String>> sources =
      ValueNotifier<List<String>>(<String>[AppConfig.wordpressBaseUrl.trim()]);
  final ValueNotifier<BlogSourceMode> mode =
      ValueNotifier(BlogSourceMode.single);

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final migratedLegacySource =
        _normalizeIfValid(prefs.getString(_legacyWordpressBaseUrlKey));
    final storedSources = _readStoredSources(prefs);
    final initialSources = storedSources.isNotEmpty
        ? storedSources
        : <String>[
            migratedLegacySource ?? AppConfig.wordpressBaseUrl.trim(),
          ];

    final selectedSource = _normalizeIfValid(
          prefs.getString(_selectedWordpressSourceKey),
        ) ??
        initialSources.first;

    final storedMode = prefs.getString(_wordpressSourceModeKey);
    final initialMode = storedMode == 'aggregate'
        ? BlogSourceMode.aggregate
        : BlogSourceMode.single;

    sources.value = initialSources;
    baseUrl.value = initialSources.contains(selectedSource)
        ? selectedSource
        : initialSources.first;
    mode.value = initialMode;

    await _persistAll(prefs);
    _initialized = true;
  }

  List<String> get activeSources => mode.value == BlogSourceMode.aggregate
      ? List.unmodifiable(sources.value)
      : <String>[baseUrl.value];

  String get currentSource => baseUrl.value;

  Future<void> setBaseUrl(String url) async {
    final normalized = _validatedUrl(url);
    final nextSources = _mergeSources(sources.value, normalized);

    sources.value = nextSources;
    baseUrl.value = normalized;
    mode.value = BlogSourceMode.single;

    final prefs = await SharedPreferences.getInstance();
    await _persistAll(prefs);
  }

  Future<void> setSources(List<String> urls) async {
    final normalizedSources = urls
        .map(_validatedUrl)
        .toSet()
        .toList();

    if (normalizedSources.isEmpty) {
      throw const FormatException('请至少保留一个有效的博客地址');
    }

    sources.value = normalizedSources;
    if (!normalizedSources.contains(baseUrl.value)) {
      baseUrl.value = normalizedSources.first;
    }

    final prefs = await SharedPreferences.getInstance();
    await _persistAll(prefs);
  }

  Future<void> addSource(String url) async {
    final normalized = _validatedUrl(url);
    sources.value = _mergeSources(sources.value, normalized);

    final prefs = await SharedPreferences.getInstance();
    await _persistAll(prefs);
  }

  Future<void> removeSource(String url) async {
    final normalized = _validatedUrl(url);
    final nextSources = sources.value.where((item) => item != normalized).toList();
    if (nextSources.isEmpty) {
      throw const FormatException('请至少保留一个博客地址');
    }

    sources.value = nextSources;
    if (baseUrl.value == normalized) {
      baseUrl.value = nextSources.first;
    }
    if (mode.value == BlogSourceMode.aggregate && nextSources.length == 1) {
      mode.value = BlogSourceMode.single;
    }

    final prefs = await SharedPreferences.getInstance();
    await _persistAll(prefs);
  }

  Future<void> selectSource(String url) async {
    final normalized = _validatedUrl(url);
    final nextSources = _mergeSources(sources.value, normalized);
    sources.value = nextSources;
    baseUrl.value = normalized;

    final prefs = await SharedPreferences.getInstance();
    await _persistAll(prefs);
  }

  Future<void> setMode(BlogSourceMode nextMode) async {
    mode.value = nextMode;
    final prefs = await SharedPreferences.getInstance();
    await _persistAll(prefs);
  }

  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyWordpressBaseUrlKey);
    await prefs.remove(_wordpressSourcesKey);
    await prefs.remove(_selectedWordpressSourceKey);
    await prefs.remove(_wordpressSourceModeKey);

    final defaultSource = AppConfig.wordpressBaseUrl.trim();
    sources.value = <String>[defaultSource];
    baseUrl.value = defaultSource;
    mode.value = BlogSourceMode.single;
  }

  List<String> _readStoredSources(SharedPreferences prefs) {
    final raw = prefs.getString(_wordpressSourcesKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    try {
      final decoded = json.decode(raw) as List<dynamic>;
      return decoded
          .whereType<String>()
          .map(_normalizeIfValid)
          .whereType<String>()
          .toSet()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _persistAll(SharedPreferences prefs) async {
    await prefs.setString(_wordpressSourcesKey, json.encode(sources.value));
    await prefs.setString(_selectedWordpressSourceKey, baseUrl.value);
    await prefs.setString(
      _wordpressSourceModeKey,
      mode.value == BlogSourceMode.aggregate ? 'aggregate' : 'single',
    );
    await prefs.setString(_legacyWordpressBaseUrlKey, baseUrl.value);
  }

  List<String> _mergeSources(List<String> existing, String nextSource) {
    return <String>{...existing, nextSource}.toList();
  }

  String _validatedUrl(String value) {
    final normalized = _normalizeIfValid(value);
    if (normalized == null) {
      throw const FormatException('请输入有效的 http:// 或 https:// 地址');
    }
    return normalized;
  }

  String? _normalizeIfValid(String? value) {
    if (value == null) {
      return null;
    }

    final trimmed = value.trim();
    if (!_isValidUrl(trimmed)) {
      return null;
    }
    return _normalizeUrl(trimmed);
  }

  bool _isValidUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        (uri.host.isNotEmpty ||
            value.startsWith('http://127.0.0.1') ||
            value.startsWith('http://localhost'));
  }

  String _normalizeUrl(String value) {
    if (value.endsWith('/')) {
      return value.substring(0, value.length - 1);
    }
    return value;
  }
}
