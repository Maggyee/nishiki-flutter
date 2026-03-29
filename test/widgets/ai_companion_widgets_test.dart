// AI 伴读面板相关组件测试
// 测试范围：AiSummaryView、AiChatView、AiChatInputBar、AiThinkingAnimation

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nishiki_flutter/models/ai_models.dart';
import 'package:nishiki_flutter/widgets/ai_summary_view.dart';
import 'package:nishiki_flutter/widgets/ai_chat_view.dart';
import 'package:nishiki_flutter/widgets/ai_companion_widgets.dart';

/// 构建测试用的 AiSummary 数据
AiSummary _sampleSummary() {
  return AiSummary(
    summary: '这是一篇关于 Flutter 状态管理的文章',
    keyPoints: ['要点一：Provider', '要点二：Riverpod'],
    keywords: ['Flutter', '状态管理'],
  );
}

/// 包装 Widget 供测试使用
Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  // ==================== AiSummaryView 测试 ====================
  group('AiSummaryView', () {
    testWidgets('显示加载状态', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        AiSummaryView(
          summary: null,
          isLoading: true,
          error: null,
          isDark: false,
          onRetry: () {},
          onQuickQuestion: (_) {},
        ),
      ));

      // 应该显示加载动画和加载文字
      expect(find.byType(AiThinkingAnimation), findsOneWidget);
      expect(find.text('AI 正在阅读文章...'), findsOneWidget);
    });

    testWidgets('显示错误状态和重试按钮', (WidgetTester tester) async {
      bool retried = false;

      await tester.pumpWidget(_wrap(
        AiSummaryView(
          summary: null,
          isLoading: false,
          error: '网络错误',
          isDark: false,
          onRetry: () => retried = true,
          onQuickQuestion: (_) {},
        ),
      ));

      // 应该显示错误信息
      expect(find.text('网络错误'), findsOneWidget);
      // 应该有重试按钮
      expect(find.text('重新生成'), findsOneWidget);

      // 点击重试按钮
      await tester.tap(find.text('重新生成'));
      expect(retried, isTrue);
    });

    testWidgets('显示摘要内容', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        SingleChildScrollView(
          child: AiSummaryView(
            summary: _sampleSummary(),
            isLoading: false,
            error: null,
            isDark: false,
            onRetry: () {},
            onQuickQuestion: (_) {},
          ),
        ),
      ));

      // 应该显示小节标题
      expect(find.text('核心摘要'), findsOneWidget);
      expect(find.text('关键要点'), findsOneWidget);
      expect(find.text('关键词'), findsOneWidget);

      // 应该显示关键词标签
      expect(find.text('#Flutter'), findsOneWidget);
      expect(find.text('#状态管理'), findsOneWidget);
    });

    testWidgets('快捷提问按钮触发回调', (WidgetTester tester) async {
      String? receivedQuestion;

      await tester.pumpWidget(_wrap(
        SingleChildScrollView(
          child: AiSummaryView(
            summary: _sampleSummary(),
            isLoading: false,
            error: null,
            isDark: false,
            onRetry: () {},
            onQuickQuestion: (q) => receivedQuestion = q,
          ),
        ),
      ));

      // 点击"解释核心概念"快捷按钮
      await tester.tap(find.text('解释核心概念'));
      expect(receivedQuestion, contains('核心概念'));
    });
  });

  // ==================== AiChatView 测试 ====================
  group('AiChatView', () {
    testWidgets('空状态显示引导信息', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        AiChatView(
          messages: const [],
          isDark: false,
          scrollController: ScrollController(),
          onSendPreset: (_) {},
        ),
      ));

      // 应该显示欢迎提示文字
      expect(find.text('有什么想问的吗？'), findsOneWidget);
      // 应该显示推荐提问按钮
      expect(find.text('文章讲了什么？'), findsOneWidget);
      expect(find.text('有哪些重点？'), findsOneWidget);
      expect(find.text('作者的观点是？'), findsOneWidget);
    });

    testWidgets('空状态预设按钮触发回调', (WidgetTester tester) async {
      String? presetMessage;

      await tester.pumpWidget(_wrap(
        AiChatView(
          messages: const [],
          isDark: false,
          scrollController: ScrollController(),
          onSendPreset: (msg) => presetMessage = msg,
        ),
      ));

      await tester.tap(find.text('文章讲了什么？'));
      expect(presetMessage, contains('主要讲了什么'));
    });

    testWidgets('有消息时显示消息列表', (WidgetTester tester) async {
      final messages = [
        AiMessage(
          id: '1',
          content: '你好',
          role: AiMessageRole.user,
        ),
        AiMessage(
          id: '2',
          content: '你好！有什么可以帮你的吗？',
          role: AiMessageRole.assistant,
        ),
      ];

      await tester.pumpWidget(_wrap(
        AiChatView(
          messages: messages,
          isDark: false,
          scrollController: ScrollController(),
          onSendPreset: (_) {},
        ),
      ));

      // 应该渲染消息列表而不是空状态
      expect(find.text('有什么想问的吗？'), findsNothing);
      expect(find.byType(ListView), findsOneWidget);
    });
  });

  // ==================== AiChatInputBar 测试 ====================
  group('AiChatInputBar', () {
    testWidgets('渲染输入框和发送按钮', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        AiChatInputBar(
          controller: TextEditingController(),
          focusNode: FocusNode(),
          isDark: false,
          isSending: false,
          onSend: () {},
        ),
      ));

      // 应该有输入框
      expect(find.byType(TextField), findsOneWidget);
      // 应该有 placeholder
      expect(find.text('输入你的问题...'), findsOneWidget);
    });

    testWidgets('发送中显示加载指示器', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        AiChatInputBar(
          controller: TextEditingController(),
          focusNode: FocusNode(),
          isDark: false,
          isSending: true,
          onSend: () {},
        ),
      ));

      // 应该显示 loading indicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  // ==================== AiThinkingAnimation 测试 ====================
  group('AiThinkingAnimation', () {
    testWidgets('渲染动画组件不报错', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        const AiThinkingAnimation(isDark: false),
      ));

      await tester.pump(const Duration(milliseconds: 100));
      // 应该正常渲染 auto_awesome 图标
      expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
