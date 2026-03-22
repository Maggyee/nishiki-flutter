import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/wp_models.dart';
import '../models/ai_models.dart';
import '../services/ai_service.dart';
import '../theme/app_theme.dart';
import 'ai_chat_bubble.dart';
import 'ai_markdown_text.dart';

/// ============================================================
/// AI 伴读面板 — 底部抽屉式交互面板
/// 功能：一键总结 + 文章问答对话
/// 设计：DraggableScrollableSheet + 毛玻璃效果
/// ============================================================
class AiCompanionPanel extends StatefulWidget {
  const AiCompanionPanel({
    super.key,
    required this.post,
  });

  final WpPost post; // 当前阅读的文章

  @override
  State<AiCompanionPanel> createState() => _AiCompanionPanelState();
}

class _AiCompanionPanelState extends State<AiCompanionPanel>
    with TickerProviderStateMixin {
  static const double _contentMaxWidth = 720;

  final AiService _aiService = AiService();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();

  // 面板当前显示的 Tab：0=摘要，1=对话
  int _currentTab = 0;

  // ——— 摘要相关状态 ———
  AiSummary? _summary;
  bool _summaryLoading = false;
  String? _summaryError;

  // ——— 对话相关状态 ———
  final List<AiMessage> _messages = [];
  bool _isSending = false;
  StreamSubscription<String>? _streamSubscription;

  // ——— 面板展开动画 ———
  late AnimationController _panelAnimController;
  late Animation<double> _panelSlideAnim;

  @override
  void initState() {
    super.initState();

    // 面板入场动画
    _panelAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _panelSlideAnim = CurvedAnimation(
      parent: _panelAnimController,
      curve: Curves.easeOutCubic,
    );
    _panelAnimController.forward();

    _restorePersistedState();
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _inputController.dispose();
    _chatScrollController.dispose();
    _inputFocusNode.dispose();
    _panelAnimController.dispose();
    super.dispose();
  }

  Future<void> _restorePersistedState() async {
    final cachedSummary = await _aiService.getStoredSummary(
      widget.post.id,
      sourceBaseUrl: widget.post.sourceBaseUrl,
    );
    final cachedMessages = await _aiService.getChatHistory(
      widget.post.id,
      sourceBaseUrl: widget.post.sourceBaseUrl,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _summary = cachedSummary;
      _messages
        ..clear()
        ..addAll(cachedMessages);
    });

    if (_summary == null) {
      _generateSummary();
    }
  }

  // ==================== 摘要生成 ====================
  Future<void> _generateSummary() async {
    if (_summaryLoading) return;

    setState(() {
      _summaryLoading = true;
      _summaryError = null;
    });

    try {
      final summary = await _aiService.summarizeArticle(widget.post);
      if (mounted) {
        setState(() {
          _summary = summary;
          _summaryLoading = false;
        });
        await _aiService.cacheSummary(
          widget.post.id,
          summary,
          sourceBaseUrl: widget.post.sourceBaseUrl,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _summaryError = e.toString();
          _summaryLoading = false;
        });
      }
    }
  }

  // ==================== 发送对话消息 ====================
  Future<void> _sendMessage([String? preset]) async {
    final text = preset ?? _inputController.text.trim();
    if (text.isEmpty || _isSending) return;

    // 触觉反馈
    HapticFeedback.lightImpact();

    // 清空输入框
    if (preset == null) _inputController.clear();

    // 添加用户消息
    final userMsg = AiMessage(
      id: AiMessage.generateId(),
      content: text,
      role: AiMessageRole.user,
    );

    // 创建 AI 回复占位（流式填充）
    final aiMsg = AiMessage(
      id: AiMessage.generateId(),
      content: '',
      role: AiMessageRole.assistant,
      isStreaming: true,
    );

    setState(() {
      _messages.add(userMsg);
      _messages.add(aiMsg);
      _isSending = true;
    });

    // 滚动到底部
    _scrollToBottom();

    try {
      // 获取流式响应
      final stream = _aiService.chatWithArticle(
        post: widget.post,
        userMessage: text,
        history: _messages.where((m) => m != aiMsg).toList(),
      );

      // 逐块追加 AI 的回复内容
      _streamSubscription = stream.listen(
        (chunk) {
          if (mounted) {
            setState(() {
              aiMsg.content += chunk;
            });
            _scrollToBottom();
          }
        },
        onDone: () {
          if (mounted) {
            setState(() {
              aiMsg.isStreaming = false;
              _isSending = false;
            });
            unawaited(
              _aiService.saveChatHistory(
                widget.post.id,
                _messages,
                sourceBaseUrl: widget.post.sourceBaseUrl,
              ),
            );
          }
        },
        onError: (error) {
          if (mounted) {
            setState(() {
              aiMsg.content = error.toString();
              aiMsg.isStreaming = false;
              aiMsg.isError = true;
              _isSending = false;
            });
            unawaited(
              _aiService.saveChatHistory(
                widget.post.id,
                _messages,
                sourceBaseUrl: widget.post.sourceBaseUrl,
              ),
            );
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          aiMsg.content = e.toString();
          aiMsg.isStreaming = false;
          aiMsg.isError = true;
          _isSending = false;
        });
        await _aiService.saveChatHistory(
          widget.post.id,
          _messages,
          sourceBaseUrl: widget.post.sourceBaseUrl,
        );
      }
    }
  }

  /// 平滑滚动到对话底部
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// 清空对话历史
  void _clearChat() {
    HapticFeedback.mediumImpact();
    _streamSubscription?.cancel();
    unawaited(
      _aiService.resetChat(
        widget.post.id,
        sourceBaseUrl: widget.post.sourceBaseUrl,
      ),
    );
    setState(() {
      _messages.clear();
      _isSending = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedBuilder(
      animation: _panelSlideAnim,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, (1 - _panelSlideAnim.value) * 300),
          child: Opacity(
            opacity: _panelSlideAnim.value,
            child: child,
          ),
        );
      },
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.scaffoldDark : Colors.white,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(24),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ——— 顶部拖拽手柄 + 标题 ———
            _buildHeader(isDark),

            // ——— Tab 切换栏 ———
            _buildTabBar(isDark),

            // ——— 内容区域 ———
            Flexible(
              child: _currentTab == 0
                  ? _buildSummaryView(isDark)
                  : _buildChatView(isDark),
            ),

            // ——— 对话输入框（仅在对话 Tab 显示） ———
            if (_currentTab == 1)
              _buildInputBar(isDark, bottomPadding),
          ],
        ),
      ),
    );
  }

  // ==================== 顶部标题栏 ====================
  Widget _buildHeader(bool isDark) {
    return Column(
      children: [
        // 拖拽手柄
        Container(
          margin: const EdgeInsets.only(top: 12),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: isDark ? AppTheme.surfaceDark : AppTheme.dividerColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
          child: Row(
            children: [
              // AI 图标 — 渐变背景
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6C63FF), Color(0xFF4ECDC4)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Icon(
                    Icons.auto_awesome,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // 标题文字
              Text(
                'AI 伴读助手',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppTheme.darkModeText : AppTheme.darkText,
                ),
              ),
              const Spacer(),
              // 清空对话按钮（仅在对话 Tab 且有消息时显示）
              if (_currentTab == 1 && _messages.isNotEmpty)
                IconButton(
                  tooltip: '清空对话',
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: isDark
                        ? AppTheme.darkModeSecondary
                        : AppTheme.lightText,
                    size: 20,
                  ),
                  onPressed: _clearChat,
                ),
              // 关闭按钮
              IconButton(
                tooltip: '关闭',
                icon: Icon(
                  Icons.close_rounded,
                  color: isDark
                      ? AppTheme.darkModeSecondary
                      : AppTheme.lightText,
                  size: 22,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==================== Tab 切换栏 ====================
  Widget _buildTabBar(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242A36) : const Color(0xFFEFF3F8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
          child: Row(
            children: [
              _buildTabItem(
                index: 0,
                icon: Icons.summarize_outlined,
                label: '一键总结',
                isDark: isDark,
              ),
              _buildTabItem(
                index: 1,
                icon: Icons.chat_outlined,
                label: '文章问答',
                isDark: isDark,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabItem({
    required int index,
    required IconData icon,
    required String label,
    required bool isDark,
  }) {
    final isSelected = _currentTab == index;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1.5),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              HapticFeedback.selectionClick();
              if (_currentTab != index) {
                setState(() => _currentTab = index);
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? (isDark ? const Color(0xFF2E3644) : Colors.white)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: Colors.black
                              .withValues(alpha: isDark ? 0.18 : 0.06),
                          blurRadius: isDark ? 10 : 8,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: isSelected ? 1 : 0.72,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      size: 17,
                      color: isSelected
                          ? AppTheme.primaryColor
                          : (isDark
                              ? AppTheme.darkModeSecondary
                              : const Color(0xFF7E8798)),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected
                            ? (isDark
                                ? AppTheme.darkModeText
                                : AppTheme.darkText)
                            : (isDark
                                ? AppTheme.darkModeSecondary
                                : const Color(0xFF6F7889)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==================== 摘要视图 ====================
  Widget _buildSummaryView(bool isDark) {
    // 加载中状态
    if (_summaryLoading) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // AI 思考中的动画
            _AiThinkingAnimation(isDark: isDark),
            const SizedBox(height: 16),
            Text(
              'AI 正在阅读文章...',
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? AppTheme.darkModeSecondary
                    : AppTheme.lightText,
              ),
            ),
          ],
        ),
      );
    }

    // 错误状态
    if (_summaryError != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 40,
                  color:
                      isDark ? const Color(0xFFFF6B6B) : const Color(0xFFE53E3E),
                ),
                const SizedBox(height: 12),
                Text(
                  _summaryError!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: isDark ? AppTheme.darkModeText : AppTheme.darkText,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _generateSummary,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('重新生成'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 摘要内容
    if (_summary != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            // 核心摘要
            if (_summary!.summary.isNotEmpty) ...[
              _buildSectionTitle('核心摘要', isDark),
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
                  _summary!.summary,
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
            if (_summary!.keyPoints.isNotEmpty) ...[
              const SizedBox(height: 20),
              _buildSectionTitle('关键要点', isDark),
              const SizedBox(height: 8),
              ...List.generate(_summary!.keyPoints.length, (i) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 序号标记
                      Container(
                        width: 22,
                        height: 22,
                        margin: const EdgeInsets.only(top: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.15),
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
                          _summary!.keyPoints[i],
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
            if (_summary!.keywords.isNotEmpty) ...[
              const SizedBox(height: 20),
              _buildSectionTitle('关键词', isDark),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _summary!.keywords.map((kw) {
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                color: isDark
                    ? AppTheme.darkModeSecondary
                    : AppTheme.lightText,
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
                  onTap: () {
                    setState(() => _currentTab = 1);
                    _sendMessage('请帮我解释这篇文章中的核心概念');
                  },
                ),
                AiQuickAction(
                  label: '实际应用场景',
                  icon: Icons.cases_outlined,
                  onTap: () {
                    setState(() => _currentTab = 1);
                    _sendMessage('这篇文章的内容有哪些实际应用场景？');
                  },
                ),
                AiQuickAction(
                  label: '延伸阅读建议',
                  icon: Icons.menu_book_outlined,
                  onTap: () {
                    setState(() => _currentTab = 1);
                    _sendMessage('读完这篇文章后，你有什么延伸阅读的建议吗？');
                  },
                ),
              ],
            ),

            // 重新生成按钮
            const SizedBox(height: 16),
            Center(
              child: TextButton.icon(
                onPressed: _generateSummary,
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

    return const SizedBox.shrink();
  }

  /// 小节标题组件
  Widget _buildSectionTitle(String title, bool isDark) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: isDark ? AppTheme.darkModeText : AppTheme.darkText,
      ),
    );
  }

  // ==================== 对话视图 ====================
  Widget _buildChatView(bool isDark) {
    // 空状态 — 引导用户开始提问
    if (_messages.isEmpty) {
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
                color: isDark
                    ? AppTheme.darkModeSecondary
                    : AppTheme.lightText,
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
                  onTap: () => _sendMessage('这篇文章主要讲了什么？'),
                ),
                AiQuickAction(
                  label: '有哪些重点？',
                  icon: Icons.star_outline,
                  onTap: () => _sendMessage('这篇文章有哪些重点内容？'),
                ),
                AiQuickAction(
                  label: '作者的观点是？',
                  icon: Icons.person_outline,
                  onTap: () =>
                      _sendMessage('作者在这篇文章中的核心观点是什么？'),
                ),
              ],
            ),
              ],
            ),
          ),
        ),
      );
    }

    // 对话列表
    return ListView.builder(
      controller: _chatScrollController,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
            child: AiChatBubble(message: _messages[index]),
          ),
        );
      },
    );
  }

  // ==================== 底部输入栏 ====================
  Widget _buildInputBar(bool isDark, double bottomPadding) {
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
          constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 100),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.cardDark : const Color(0xFFF0F4F8),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: TextField(
                    controller: _inputController,
                    focusNode: _inputFocusNode,
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? AppTheme.darkModeText : AppTheme.darkText,
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
              _buildSendButton(isDark),
            ],
          ),
        ),
      ),
    );
  }

  /// 发送按钮
  Widget _buildSendButton(bool isDark) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isSending ? null : () => _sendMessage(),
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: _isSending
                ? null
                : const LinearGradient(
                    colors: [Color(0xFF6C63FF), Color(0xFF4ECDC4)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            color: _isSending
                ? (isDark ? AppTheme.surfaceDark : AppTheme.dividerColor)
                : null,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: _isSending
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

// ==================== AI 思考动画组件 ====================
// 渐变旋转的 AI 图标，表示 AI 正在处理中

class _AiThinkingAnimation extends StatefulWidget {
  const _AiThinkingAnimation({required this.isDark});
  final bool isDark;

  @override
  State<_AiThinkingAnimation> createState() => _AiThinkingAnimationState();
}

class _AiThinkingAnimationState extends State<_AiThinkingAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.rotate(
          angle: _controller.value * 6.28318, // 2π 完整旋转
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF6C63FF).withValues(alpha: 0.2),
                  const Color(0xFF4ECDC4).withValues(alpha: 0.2),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
              child: Icon(
                Icons.auto_awesome,
                size: 28,
                color: Color(0xFF6C63FF),
              ),
            ),
          ),
        );
      },
    );
  }
}
