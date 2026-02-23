import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config.dart';
import 'theme/app_theme.dart';
import 'home_screen.dart';
import 'services/bookmark_service.dart';
import 'services/settings_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  // 初始化核心服务
  await BookmarkService().init();
  await SettingsService().init();

  runApp(const NishikiApp());
}

/// 应用根组件 — 监听 SettingsService 的主题模式变化
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
    // 监听主题模式变化 — 当用户在 Profile 页切换时刷新整个 app
    _settings.themeMode.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    _settings.themeMode.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    setState(() {}); // 触发 MaterialApp 重建以应用新主题
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nishiki Blog',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _settings.themeMode.value, // 从设置服务读取主题模式
      home: const _BootstrapGate(),
    );
  }
}

/// 启动引导页 — 检查 WordPress URL 配置
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
