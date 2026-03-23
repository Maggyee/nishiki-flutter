import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config.dart';
import 'home_screen.dart';
import 'services/blog_source_service.dart';
import 'services/bookmark_service.dart';
import 'services/auth_service.dart';
import 'services/local_database_service.dart';
import 'services/settings_service.dart';
import 'services/sync_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  await LocalDatabaseService().init();
  await AuthService().init();
  await BlogSourceService().init();
  await BookmarkService().init();
  await SettingsService().init();
  await SyncService().init();
  if (AuthService().isSignedIn) {
    await SyncService().bootstrap();
    await SyncService().pushPendingChanges();
    await SyncService().connectRealtime();
  }

  runApp(const NishikiApp());
}

class NishikiApp extends StatefulWidget {
  const NishikiApp({super.key});

  @override
  State<NishikiApp> createState() => _NishikiAppState();
}

class _NishikiAppState extends State<NishikiApp> {
  final _settings = SettingsService();

  @override
  void initState() {
    super.initState();
    _settings.themeMode.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    _settings.themeMode.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nishiki 博客',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _settings.themeMode.value,
      home: const _BootstrapGate(),
    );
  }
}

class _BootstrapGate extends StatelessWidget {
  const _BootstrapGate();

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.hasValidBaseUrl) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight,
                    borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                  ),
                  child: const Icon(
                    Icons.link_off_rounded,
                    size: 48,
                    color: AppTheme.primaryColor,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  '需要配置 WordPress',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  '请使用以下命令启动应用：\n'
                  'flutter run --dart-define=WP_BASE_URL=https://your-site.com',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return const HomeScreen();
  }
}
