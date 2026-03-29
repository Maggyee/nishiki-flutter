// AI 摘要视图 — 展示文章的 AI 生成摘要
// 包含：加载动画、错误提示、核心摘要、关键要点、关键词标签、快捷提问跳转

import 'package:flutter/material.dart';

import '../models/ai_models.dart';
import '../theme/app_theme.dart';
import 'ai_chat_bubble.dart';
import 'ai_companion_widgets.dart' show AiThinkingAnimation;
import 'ai_markdown_text.dart';

/// AI 摘要视图组件，展示文章的 AI 分析结果
class AiSummaryView extends StatelessWidget {
  const AiSummaryView({
    super.key,
    required this.summary,
    required this.isLoading,
    required this.error,
    required this.isDark,
    required this.onRetry,
    required this.onQuickQuestion,
    this.contentMaxWidth = 720,
  });

  /// 当前摘要数据（可能为空表示尚未生成）
  final AiSummary? summary;

  /// 是否正在加载
  final bool isLoading;

  /// 错误信息
  final String? error;

  /// 是否深色模式
  final bool isDark;

  /// 重试/重新生成回调
  final VoidCallback onRetry;

  /// 快捷提问回调 — 切换到对话 Tab 并发送消息
  final void Function(String question) onQuickQuestion;

  /// 内容区域最大宽度
  final double contentMaxWidth;

  @override
  Widget build(BuildContext context) {
    // 加载中状态
    if (isLoading) {
      return _buildLoadingState();
    }

    // 错误状态
    if (error != null) {
      return _buildErrorState();
    }

    // 摘要内容
    if (summary != null) {
      return _buildSummaryContent();
    }

    return const SizedBox.shrink();
  }

  // ==================== 加载中状态 ====================
  Widget _buildLoadingState() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AiThinkingAnimation(isDark: isDark),
          const SizedBox(height: 16),
          Text(
            'AI 正在阅读文章...',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? AppTheme.darkModeSecondary : AppTheme.lightText,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 错误状态 ====================
  Widget _buildErrorState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentMaxWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 40,
                color: isDark
                    ? const Color(0xFFFF6B6B)
                    : const Color(0xFFE53E3E),
              ),
              const SizedBox(height: 12),
              Text(
                error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: isDark ? AppTheme.darkModeText : AppTheme.darkText,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('重新生成'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== 摘要正文 ====================
  Widget _buildSummaryContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 核心摘要
              if (summary!.summary.isNotEmpty) ...[
                _buildSectionTitle('核心摘要'),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.primaryColor.withValues(alpha: 0.08)
                        : AppTheme.primaryLight.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: AiMarkdownText(
                    summary!.summary,
                    isDark: isDark,
                    baseStyle: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: isDark ? AppTheme.darkModeText : AppTheme.darkText,
                    ),
                  ),
                ),
              ],

              // 关键要点
              if (summary!.keyPoints.isNotEmpty) ...[
                const SizedBox(height: 20),
                _buildSectionTitle('关键要点'),
                const SizedBox(height: 8),
                ...List.generate(summary!.keyPoints.length, (i) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 序号徽章
                        Container(
                          width: 22,
                          height: 22,
                          margin: const EdgeInsets.only(top: 2),
                          decoration: BoxDecoration(
                            color:
                                AppTheme.primaryColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: AiMarkdownText(
                            summary!.keyPoints[i],
                            isDark: isDark,
                            baseStyle: TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              color: isDark
                                  ? AppTheme.darkModeText
                                  : AppTheme.darkText,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],

              // 关键词标签
              if (summary!.keywords.isNotEmpty) ...[
                const SizedBox(height: 20),
                _buildSectionTitle('关键词'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: summary!.keywords.map((kw) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppTheme.surfaceDark
                            : const Color(0xFFF0F4F8),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '#$kw',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],

              // 快捷提问区域 — 引导用户进入对话
              const SizedBox(height: 20),
              Text(
                '想深入了解？试试这些问题',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color:
                      isDark ? AppTheme.darkModeSecondary : AppTheme.lightText,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AiQuickAction(
                    label: '解释核心概念',
                    icon: Icons.lightbulb_outline,
                    onTap: () =>
                        onQuickQuestion('请帮我解释这篇文章中的核心概念'),
                  ),
                  AiQuickAction(
                    label: '实际应用场景',
                    icon: Icons.cases_outlined,
                    onTap: () =>
                        onQuickQuestion('这篇文章的内容有哪些实际应用场景？'),
                  ),
                  AiQuickAction(
                    label: '延伸阅读建议',
                    icon: Icons.menu_book_outlined,
                    onTap: () => onQuickQuestion(
                        '读完这篇文章后，你有什么延伸阅读的建议吗？'),
                  ),
                ],
              ),

              // 重新生成按钮
              const SizedBox(height: 16),
              Center(
                child: TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('重新生成摘要'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primaryColor,
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 小节标题组件
  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: isDark ? AppTheme.darkModeText : AppTheme.darkText,
      ),
    );
  }
}
