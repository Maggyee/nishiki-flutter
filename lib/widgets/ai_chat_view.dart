// AI 对话视图 — 展示 AI 问答对话界面
// 包含：空状态引导、消息列表、底部输入栏、发送按钮

import 'package:flutter/material.dart';

import '../models/ai_models.dart';
import '../theme/app_theme.dart';
import 'ai_chat_bubble.dart';

/// AI 对话视图组件 — 文章问答对话界面
class AiChatView extends StatelessWidget {
  const AiChatView({
    super.key,
    required this.messages,
    required this.isDark,
    required this.scrollController,
    required this.onSendPreset,
    this.contentMaxWidth = 720,
  });

  /// 对话消息列表
  final List<AiMessage> messages;

  /// 是否深色模式
  final bool isDark;

  /// 聊天列表的滚动控制器
  final ScrollController scrollController;

  /// 发送预设消息的回调
  final void Function(String message) onSendPreset;

  /// 内容区域最大宽度
  final double contentMaxWidth;

  @override
  Widget build(BuildContext context) {
    // 空状态 — 引导用户开始提问
    if (messages.isEmpty) {
      return _buildEmptyState();
    }

    // 对话列表
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: contentMaxWidth),
            child: AiChatBubble(message: messages[index]),
          ),
        );
      },
    );
  }

  // ==================== 空状态引导 ====================
  Widget _buildEmptyState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // AI 欢迎图标
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF6C63FF).withValues(alpha: 0.12),
                      const Color(0xFF4ECDC4).withValues(alpha: 0.12),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  size: 36,
                  color: Color(0xFF6C63FF),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '有什么想问的吗？',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppTheme.darkModeText : AppTheme.darkText,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '我已经阅读了这篇文章，可以回答你的任何问题',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color:
                      isDark ? AppTheme.darkModeSecondary : AppTheme.lightText,
                ),
              ),
              const SizedBox(height: 20),
              // 推荐提问按钮
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  AiQuickAction(
                    label: '文章讲了什么？',
                    icon: Icons.article_outlined,
                    onTap: () => onSendPreset('这篇文章主要讲了什么？'),
                  ),
                  AiQuickAction(
                    label: '有哪些重点？',
                    icon: Icons.star_outline,
                    onTap: () => onSendPreset('这篇文章有哪些重点内容？'),
                  ),
                  AiQuickAction(
                    label: '作者的观点是？',
                    icon: Icons.person_outline,
                    onTap: () =>
                        onSendPreset('作者在这篇文章中的核心观点是什么？'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// AI 对话输入栏组件 — 底部输入框 + 发送按钮
class AiChatInputBar extends StatelessWidget {
  const AiChatInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isDark,
    required this.isSending,
    required this.onSend,
    this.contentMaxWidth = 720,
  });

  /// 文本控制器
  final TextEditingController controller;

  /// 输入框焦点
  final FocusNode focusNode;

  /// 是否深色模式
  final bool isDark;

  /// 是否正在发送中
  final bool isSending;

  /// 发送回调
  final VoidCallback onSend;

  /// 内容区域最大宽度
  final double contentMaxWidth;

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        8,
        8 +
            (bottomPadding > 0
                ? bottomPadding
                : MediaQuery.of(context).padding.bottom),
      ),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : Colors.white,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentMaxWidth),
          child: Row(
            children: [
              // 输入框
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 100),
                  decoration: BoxDecoration(
                    color:
                        isDark ? AppTheme.cardDark : const Color(0xFFF0F4F8),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
                    style: TextStyle(
                      fontSize: 14,
                      color:
                          isDark ? AppTheme.darkModeText : AppTheme.darkText,
                    ),
                    decoration: InputDecoration(
                      hintText: '输入你的问题...',
                      hintStyle: TextStyle(
                        fontSize: 14,
                        color: isDark
                            ? AppTheme.darkModeSecondary
                            : AppTheme.lightText,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 发送按钮
              _buildSendButton(),
            ],
          ),
        ),
      ),
    );
  }

  /// 发送按钮 — 渐变背景 + 加载指示器
  Widget _buildSendButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isSending ? null : onSend,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: isSending
                ? null
                : const LinearGradient(
                    colors: [Color(0xFF6C63FF), Color(0xFF4ECDC4)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            color: isSending
                ? (isDark ? AppTheme.surfaceDark : AppTheme.dividerColor)
                : null,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: isSending
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: isDark
                          ? AppTheme.darkModeSecondary
                          : AppTheme.lightText,
                    ),
                  )
                : const Icon(
                    Icons.arrow_upward_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
          ),
        ),
      ),
    );
  }
}
