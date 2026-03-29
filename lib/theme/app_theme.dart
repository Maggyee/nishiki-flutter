import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppTheme {
  static String? get appFontFamily {
    if (kIsWeb) {
      return 'NotoSansSCSubset';
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
        return 'Microsoft YaHei';
      case TargetPlatform.macOS:
      case TargetPlatform.iOS:
        return 'PingFang SC';
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
        return null;
      case TargetPlatform.linux:
        return 'Noto Sans SC';
    }
  }

  static const List<String> appFontFallback = [
    'Microsoft YaHei',
    'PingFang SC',
    'Hiragino Sans GB',
    'Source Han Sans SC',
    'Noto Sans SC',
    'Noto Sans JP',
    'SimHei',
    'Arial Unicode MS',
    'sans-serif',
  ];

  static const Color primaryColor = Color(0xFF4F95DD);
  static const Color primaryDark = Color(0xFF2F6FAF);
  static const Color primaryLight = Color(0xFFDDEEFF);

  static const Color darkText = Color(0xFF1A1A2E);
  static const Color mediumText = Color(0xFF424B63);
  static const Color lightText = Color(0xFF56607A);
  static const Color dividerColor = Color(0xFFE2E8F0);
  static const Color dividerStrong = Color(0xFFCBD5E1);
  static const Color scaffoldLight = Color(0xFFF8F9FC);
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color surfaceMutedLight = Color(0xFFF1F5F9);

  static const Color scaffoldDark = Color(0xFF0D1117);
  static const Color surfaceDark = Color(0xFF161B22);
  static const Color cardDark = Color(0xFF1C2128);
  static const Color surfaceMutedDark = Color(0xFF202734);
  static const Color darkModeText = Color(0xFFE6EDF3);
  static const Color darkModeSecondary = Color(0xFF8B949E);

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4F95DD), Color(0xFF3F82CA), Color(0xFF2F6FAF)],
  );

  static const LinearGradient cardOverlayGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Colors.transparent, Color(0xCC000000)],
  );

  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 24.0;

  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 16.0;
  static const double spacingLg = 24.0;
  static const double spacingXl = 32.0;

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

  static ThemeData get lightTheme {
    final base = ThemeData(
      brightness: Brightness.light,
      useMaterial3: true,
      fontFamily: appFontFamily,
      fontFamilyFallback: appFontFallback,
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
      textTheme: _buildLightTextTheme(base.textTheme),
      appBarTheme: _lightAppBarTheme,
      cardTheme: _cardTheme(cardLight),
      inputDecorationTheme: _lightInputDecorationTheme,
      filledButtonTheme: _filledButtonTheme,
      outlinedButtonTheme: _lightOutlinedButtonTheme,
      textButtonTheme: _lightTextButtonTheme,
      snackBarTheme: _lightSnackBarTheme,
      searchBarTheme: SearchBarThemeData(
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: const WidgetStatePropertyAll(Colors.white),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
            side: const BorderSide(color: dividerColor, width: 1.5),
          ),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: spacingMd),
        ),
        hintStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 14, color: lightText),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFEAF2FB),
        selectedColor: primaryDark,
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: darkText,
        ),
        secondaryLabelStyle: const TextStyle(
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
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        indicatorColor: primaryLight,
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: primaryColor, size: 22);
          }
          return const IconThemeData(color: lightText, size: 22);
        }),
      ),
      dividerTheme: const DividerThemeData(
        color: dividerColor,
        thickness: 1,
        space: 0,
      ),
    );
  }

  static ThemeData get darkTheme {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      fontFamily: appFontFamily,
      fontFamilyFallback: appFontFallback,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: Brightness.dark,
        primary: primaryColor,
        surface: surfaceDark,
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: scaffoldDark,
      textTheme: _buildDarkTextTheme(base.textTheme),
      appBarTheme: _darkAppBarTheme,
      cardTheme: _cardTheme(cardDark),
      inputDecorationTheme: _darkInputDecorationTheme,
      filledButtonTheme: _filledButtonTheme,
      outlinedButtonTheme: _darkOutlinedButtonTheme,
      textButtonTheme: _darkTextButtonTheme,
      snackBarTheme: _darkSnackBarTheme,
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        backgroundColor: surfaceDark,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        indicatorColor: primaryColor.withValues(alpha: 0.2),
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: darkModeText,
          ),
        ),
      ),
    );
  }

  static TextTheme _buildLightTextTheme(TextTheme base) {
    return base.copyWith(
      displayLarge: const TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: darkText,
        height: 1.2,
        letterSpacing: -0.5,
      ),
      headlineLarge: const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: darkText,
        height: 1.3,
        letterSpacing: -0.3,
      ),
      headlineMedium: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: darkText,
        height: 1.3,
      ),
      titleLarge: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: darkText,
        height: 1.4,
      ),
      titleMedium: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: darkText,
      ),
      titleSmall: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: mediumText,
      ),
      bodyLarge: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: darkText,
        height: 1.7,
      ),
      bodyMedium: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: mediumText,
        height: 1.6,
      ),
      bodySmall: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: mediumText,
        height: 1.5,
      ),
      labelLarge: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: primaryDark,
      ),
      labelMedium: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: mediumText,
      ),
      labelSmall: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: primaryDark,
        letterSpacing: 0.5,
      ),
    );
  }

  static TextTheme _buildDarkTextTheme(TextTheme base) {
    return _buildLightTextTheme(
      base,
    ).apply(bodyColor: darkModeText, displayColor: darkModeText);
  }

  static AppBarTheme get _lightAppBarTheme => const AppBarTheme(
    elevation: 0,
    scrolledUnderElevation: 0.5,
    backgroundColor: scaffoldLight,
    surfaceTintColor: Colors.transparent,
    centerTitle: false,
    titleTextStyle: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: darkText,
    ),
    iconTheme: IconThemeData(color: darkText),
  );

  static AppBarTheme get _darkAppBarTheme => const AppBarTheme(
    elevation: 0,
    scrolledUnderElevation: 0.5,
    backgroundColor: scaffoldDark,
    surfaceTintColor: Colors.transparent,
    centerTitle: false,
    titleTextStyle: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: darkModeText,
    ),
    iconTheme: IconThemeData(color: darkModeText),
  );

  static CardThemeData _cardTheme(Color color) => CardThemeData(
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusLg),
    ),
    color: color,
    surfaceTintColor: Colors.transparent,
    margin: EdgeInsets.zero,
  );

  static InputDecorationTheme get _lightInputDecorationTheme =>
      InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        hintStyle: const TextStyle(fontSize: 14, color: lightText),
        prefixIconColor: mediumText,
        suffixIconColor: mediumText,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: spacingMd,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: dividerColor, width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: dividerColor, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: primaryColor, width: 1.6),
        ),
      );

  static InputDecorationTheme get _darkInputDecorationTheme =>
      InputDecorationTheme(
        filled: true,
        fillColor: surfaceMutedDark,
        hintStyle: const TextStyle(fontSize: 14, color: darkModeSecondary),
        prefixIconColor: darkModeSecondary,
        suffixIconColor: darkModeSecondary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: spacingMd,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: Color(0xFF30363D), width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: Color(0xFF30363D), width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: primaryColor, width: 1.6),
        ),
      );

  static FilledButtonThemeData get _filledButtonTheme => FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: primaryColor,
      foregroundColor: Colors.white,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMd),
      ),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    ),
  );

  static OutlinedButtonThemeData get _lightOutlinedButtonTheme =>
      OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: darkText,
          side: const BorderSide(color: dividerStrong),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      );

  static OutlinedButtonThemeData get _darkOutlinedButtonTheme =>
      OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: darkModeText,
          side: const BorderSide(color: Color(0xFF3B4453)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      );

  static TextButtonThemeData get _lightTextButtonTheme => TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: primaryDark,
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
    ),
  );

  static TextButtonThemeData get _darkTextButtonTheme => TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: primaryColor,
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
    ),
  );

  static SnackBarThemeData get _lightSnackBarTheme => SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    elevation: 0,
    backgroundColor: const Color(0xFF1F2937),
    contentTextStyle: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: Colors.white,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusMd),
    ),
  );

  static SnackBarThemeData get _darkSnackBarTheme => SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    elevation: 0,
    backgroundColor: cardDark,
    contentTextStyle: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: darkModeText,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusMd),
    ),
  );
}
