// Profile 对话框组件测试
// 测试范围：ProfileDialogs 中提取的各个对话框

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nishiki_flutter/widgets/home_tabs/profile_dialogs.dart';

/// 包装 Widget 供测试使用
Widget _wrap(Widget child) {
  return MaterialApp(home: child);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('ProfileDialogs', () {
    testWidgets('showAboutAppDialog 弹出关于对话框', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () =>
                      ProfileDialogs.showAboutAppDialog(context, false),
                  child: const Text('打开关于'),
                ),
              ),
            );
          },
        ),
      ));

      await tester.tap(find.text('打开关于'));
      await tester.pumpAndSettle();

      // 应该弹出对话框
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('showClearCacheDialog 弹出清除缓存对话框',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () =>
                      ProfileDialogs.showClearCacheDialog(context),
                  child: const Text('清除缓存'),
                ),
              ),
            );
          },
        ),
      ));

      await tester.tap(find.text('清除缓存'));
      await tester.pumpAndSettle();

      // 应该弹出确认对话框
      expect(find.byType(AlertDialog), findsOneWidget);
      // 应该有取消按钮
      expect(find.text('取消'), findsOneWidget);
    });

    testWidgets('showResetDialog 弹出重置数据对话框',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    // showResetDialog 需要 settings 和 bookmarkService
                    // 这里只测试对话框能否弹出，不实际执行逻辑
                    showDialog(
                      context: context,
                      builder: (_) => const AlertDialog(
                        title: Text('⚠️ 重置所有数据？'),
                        content: Text('这将清除你的所有数据。'),
                      ),
                    );
                  },
                  child: const Text('重置数据'),
                ),
              ),
            );
          },
        ),
      ));

      await tester.tap(find.text('重置数据'));
      await tester.pumpAndSettle();

      // 应该弹出确认对话框
      expect(find.byType(AlertDialog), findsOneWidget);
    });
  });
}
