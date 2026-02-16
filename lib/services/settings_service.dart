import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ============================================================
/// 用户设置服务 — 管理应用全局偏好设置
/// 使用 SharedPreferences 持久化，ValueNotifier 通知 UI 刷新
/// ============================================================
class SettingsService {
  // 单例模式 — 全局唯一实例
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  // SharedPreferences 存储 key
  static const _themeModeKey = 'theme_mode';       // 主题模式
  static const _fontScaleKey = 'font_scale';       // 字体缩放比例
  static const _readCountKey = 'read_article_count'; // 已读文章计数

  // 可监听的状态通知器 — UI 层通过这些来响应设置变更
  final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.system);
  final ValueNotifier<double> fontScale = ValueNotifier(1.0); // 1.0 = 默认

  // 已读文章计数
  int _readCount = 0;
  int get readCount => _readCount;

  // 已读文章 ID 集合（避免重复计数）
  Set<int> _readPostIds = {};

  bool _initialized = false;

  /// 初始化 — 从本地存储加载所有设置
  Future<void> init() async {
    if (_initialized) return;

    final prefs = await SharedPreferences.getInstance();

    // 加载主题模式
    final themeIndex = prefs.getInt(_themeModeKey) ?? 0;
    themeMode.value = ThemeMode.values[themeIndex.clamp(0, 2)];

    // 加载字体缩放
    fontScale.value = prefs.getDouble(_fontScaleKey) ?? 1.0;

    // 加载已读计数
    _readCount = prefs.getInt(_readCountKey) ?? 0;

    // 加载已读文章 ID 列表
    final readIds = prefs.getStringList('read_post_ids') ?? [];
    _readPostIds = readIds.map((e) => int.tryParse(e) ?? 0).toSet();

    _initialized = true;
  }

  /// 切换主题模式（system → light → dark → system 循环）
  Future<void> cycleThemeMode() async {
    final next = switch (themeMode.value) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    await setThemeMode(next);
  }

  /// 设置主题模式
  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeModeKey, mode.index);
  }

  /// 设置字体缩放比例（范围 0.8 ~ 1.4）
  Future<void> setFontScale(double scale) async {
    fontScale.value = scale.clamp(0.8, 1.4);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontScaleKey, fontScale.value);
  }

  /// 记录一篇文章已读（去重）
  Future<void> markAsRead(int postId) async {
    if (_readPostIds.contains(postId)) return;
    _readPostIds.add(postId);
    _readCount = _readPostIds.length;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_readCountKey, _readCount);
    await prefs.setStringList(
      'read_post_ids',
      _readPostIds.map((e) => e.toString()).toList(),
    );
  }

  /// 清除所有缓存和设置数据
  Future<void> clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    // 重置为默认值
    themeMode.value = ThemeMode.system;
    fontScale.value = 1.0;
    _readCount = 0;
    _readPostIds = {};
  }

  /// 获取主题模式的中文名称
  String get themeModeName => switch (themeMode.value) {
    ThemeMode.system => '跟随系统',
    ThemeMode.light => '浅色模式',
    ThemeMode.dark => '深色模式',
  };

  /// 获取主题模式图标
  IconData get themeModeIcon => switch (themeMode.value) {
    ThemeMode.system => Icons.brightness_auto_rounded,
    ThemeMode.light => Icons.light_mode_rounded,
    ThemeMode.dark => Icons.dark_mode_rounded,
  };

  /// 获取字体大小档位名称
  String get fontScaleName {
    if (fontScale.value <= 0.85) return '小';
    if (fontScale.value <= 1.05) return '标准';
    if (fontScale.value <= 1.25) return '大';
    return '超大';
  }
}
