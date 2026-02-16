import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ============================================================
/// Nishiki Blog 全局主题配置
/// 设计理念：现代极简 + 高级感 + 沉浸式阅读
/// 主色调：薄荷绿 #1abc9c，搭配深灰文字和柔和背景
/// ============================================================

class AppTheme {
  // ==================== 品牌色彩 ====================
  // 主色调 — 薄荷绿，来自 Stitch 设计稿
  static const Color primaryColor = Color(0xFF4F95DD);
  // 深色变体 — 用于强调和暗色模式的主色
  static const Color primaryDark = Color(0xFF2F6FAF);
  // 浅色变体 — 用于背景和卡片
  static const Color primaryLight = Color(0xFFDDEEFF);

  // ==================== 中性色 ====================
  static const Color darkText = Color(0xFF1A1A2E);
  static const Color mediumText = Color(0xFF424B63);
  static const Color lightText = Color(0xFF56607A);
  static const Color dividerColor = Color(0xFFE2E8F0);
  static const Color scaffoldLight = Color(0xFFF8F9FC);
  static const Color cardLight = Color(0xFFFFFFFF);

  // ==================== 深色模式色彩 ====================
  static const Color scaffoldDark = Color(0xFF0D1117);
  static const Color surfaceDark = Color(0xFF161B22);
  static const Color cardDark = Color(0xFF1C2128);
  static const Color darkModeText = Color(0xFFE6EDF3);
  static const Color darkModeSecondary = Color(0xFF8B949E);

  // ==================== 渐变色 ====================
  // 用于 Hero 卡片和头部背景的渐变
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4F95DD), Color(0xFF3F82CA), Color(0xFF2F6FAF)],
  );

  // 用于文章卡片悬浮叠加层
  static const LinearGradient cardOverlayGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Colors.transparent, Color(0xCC000000)],
  );

  // ==================== 圆角 ====================
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 24.0;

  // ==================== 间距 ====================
  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 16.0;
  static const double spacingLg = 24.0;
  static const double spacingXl = 32.0;

  // ==================== 阴影 ====================
  // 柔和阴影 — 让卡片有"漂浮"感
  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 20,
          offset: const Offset(0, 4),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.02),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ];

  // 强调阴影 — 用于选中或悬浮状态
  static List<BoxShadow> get elevatedShadow => [
        BoxShadow(
          color: primaryColor.withValues(alpha: 0.15),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  // ==================== 浅色主题 ====================
  static ThemeData get lightTheme {
    final base = ThemeData(
      brightness: Brightness.light,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: Brightness.light,
        primary: primaryColor,
        onPrimary: Colors.white,
        surface: cardLight,
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: scaffoldLight,
      // 使用 Inter 字体 — 现代、可读性极高
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        // 超大标题 — 用于 Hero 区域
        displayLarge: GoogleFonts.inter(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          color: darkText,
          height: 1.2,
          letterSpacing: -0.5,
        ),
        // 大标题 — 用于页面标题
        headlineLarge: GoogleFonts.inter(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: darkText,
          height: 1.3,
          letterSpacing: -0.3,
        ),
        // 中标题 — 用于文章标题
        headlineMedium: GoogleFonts.inter(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: darkText,
          height: 1.3,
        ),
        // 小标题 — 用于区块标题
        titleLarge: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: darkText,
          height: 1.4,
        ),
        titleMedium: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: darkText,
        ),
        titleSmall: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: mediumText,
        ),
        // 正文 — 阅读舒适
        bodyLarge: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: darkText,
          height: 1.7,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: mediumText,
          height: 1.6,
        ),
        bodySmall: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: mediumText,
          height: 1.5,
        ),
        // 标签文字
        labelLarge: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: primaryDark,
        ),
        labelMedium: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: mediumText,
        ),
        labelSmall: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: primaryDark,
          letterSpacing: 0.5,
        ),
      ),
      // AppBar 主题 — 透明背景，无阴影
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: scaffoldLight,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: darkText,
        ),
        iconTheme: const IconThemeData(color: darkText),
      ),
      // 卡片主题 — 柔和阴影 + 圆角
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
        color: cardLight,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
      ),
      // 搜索栏主题
      searchBarTheme: SearchBarThemeData(
        elevation: WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(Colors.white),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
            side: BorderSide(color: dividerColor, width: 1.5),
          ),
        ),
        padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: spacingMd),
        ),
        hintStyle: WidgetStatePropertyAll(
          GoogleFonts.inter(fontSize: 14, color: lightText),
        ),
      ),
      // Chip（分类标签）主题
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFEAF2FB),
        selectedColor: primaryDark,
        labelStyle: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: darkText,
        ),
        secondaryLabelStyle: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        checkmarkColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        side: const BorderSide(color: Color(0xFFB9CEE5), width: 1.0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      // 底部导航栏主题
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        indicatorColor: primaryLight,
        labelTextStyle: WidgetStatePropertyAll(
          GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: primaryColor, size: 24);
          }
          return const IconThemeData(color: lightText, size: 24);
        }),
      ),
      // 分割线
      dividerTheme: const DividerThemeData(
        color: dividerColor,
        thickness: 1,
        space: 0,
      ),
    );
  }

  // ==================== 深色主题 ====================
  static ThemeData get darkTheme {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: Brightness.dark,
        primary: primaryColor,
        surface: surfaceDark,
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: scaffoldDark,
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: darkModeText,
        displayColor: darkModeText,
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: scaffoldDark,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: darkModeText,
        ),
        iconTheme: const IconThemeData(color: darkModeText),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
        color: cardDark,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceDark,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        indicatorColor: primaryColor.withValues(alpha: 0.2),
        labelTextStyle: WidgetStatePropertyAll(
          GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: darkModeText),
        ),
      ),
    );
  }
}
