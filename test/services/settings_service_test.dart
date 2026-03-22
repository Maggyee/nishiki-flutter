import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nishiki_flutter/models/wp_models.dart';
import 'package:nishiki_flutter/services/settings_service.dart';

WpPost _post(int id) {
  return WpPost(
    sourceBaseUrl: 'https://example.com',
    id: id,
    title: 'Post $id',
    excerpt: 'Excerpt $id',
    contentHtml: '<p>Post $id</p>',
    author: 'Tester',
    date: DateTime(2026, 3, 1),
    featuredImageUrl: null,
    categories: const ['Test'],
    categoryIds: const [1],
    link: 'https://example.com/posts/$id',
    readMinutes: 1,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'SettingsService persists theme, font scale, read count and clearAllData resets state',
    () async {
      SharedPreferences.setMockInitialValues({});
      final service = SettingsService();

      await service.clearAllData();
      await service.init();
      expect(service.themeMode.value, ThemeMode.system);
      expect(service.fontScale.value, 1.0);
      expect(service.readCount, 0);

      await service.setThemeMode(ThemeMode.dark);
      await service.setFontScale(1.6);
      await service.markAsRead(_post(21));
      await service.markAsRead(_post(21));
      await service.markAsRead(_post(22));

      expect(service.themeMode.value, ThemeMode.dark);
      expect(service.fontScale.value, 1.4);
      expect(service.readCount, 2);
      expect(service.themeModeIcon, Icons.dark_mode_rounded);
      expect(service.themeModeName, isNotEmpty);
      expect(service.fontScaleName, isNotEmpty);

      await service.cycleThemeMode();
      expect(service.themeMode.value, ThemeMode.system);

      await service.clearAllData();
      expect(service.themeMode.value, ThemeMode.system);
      expect(service.fontScale.value, 1.0);
      expect(service.readCount, 0);
    },
  );
}
