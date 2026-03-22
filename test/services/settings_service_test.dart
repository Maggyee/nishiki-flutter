import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nishiki_flutter/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SettingsService persists theme, font scale, read count and clearAllData resets state', () async {
    SharedPreferences.setMockInitialValues({});
    final service = SettingsService();

    await service.init();
    expect(service.themeMode.value, ThemeMode.system);
    expect(service.fontScale.value, 1.0);
    expect(service.readCount, 0);

    await service.setThemeMode(ThemeMode.dark);
    await service.setFontScale(1.6);
    await service.markAsRead(21);
    await service.markAsRead(21);
    await service.markAsRead(22);

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
  });
}
