// AI 伴读面板 — 底部抽屉式交互面板（壳层）
// 职责：状态管理 + Header + TabBar + 子视图组装
// 子组件：AiSummaryView（摘要视图）、AiChatView + AiChatInputBar（对话视图）

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/wp_models.dart';
import '../models/ai_models.dart';
import '../services/ai_service.dart';
import '../theme/app_theme.dart';
import 'ai_summary_view.dart';
import 'ai_chat_view.dart';

/// ============================================================
/// AI 伴读面板 — 底部抽屉式交互面板
/// 功能：一键总结 + 文章问答对话
/// 设计：底部弹出式面板 + 渐变动画
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

  /// 从缓存恢复摘要和对话历史
  Future<void> _restorePersistedState() async {
    final cachedSummary = await _aiService.getStoredSummary(
      widget.post.id,
      sourceBaseUrl: widget.post.sourceBaseUrl,
    );
    final cachedMessages = await _aiService.getChatHistory(
      widget.post.id,
      sourceBaseUrl: widget.post.sourceBaseUrl,
    );

    if (!mounted) return;

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

    _scrollToBottom();

    try {
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

  /// 快捷提问 — 从摘要视图切换到对话 Tab 并发送预设问题
  void _handleQuickQuestion(String question) {
    setState(() => _currentTab = 1);
    _sendMessage(question);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                  ? AiSummaryView(
                      summary: _summary,
                      isLoading: _summaryLoading,
                      error: _summaryError,
                      isDark: isDark,
                      onRetry: _generateSummary,
                      onQuickQuestion: _handleQuickQuestion,
                      contentMaxWidth: _contentMaxWidth,
                    )
                  : AiChatView(
                      messages: _messages,
                      isDark: isDark,
                      scrollController: _chatScrollController,
                      onSendPreset: _sendMessage,
                      contentMaxWidth: _contentMaxWidth,
                    ),
            ),
            // ——— 对话输入框（仅在对话 Tab 显示） ———
            if (_currentTab == 1)
              AiChatInputBar(
                controller: _inputController,
                focusNode: _inputFocusNode,
                isDark: isDark,
                isSending: _isSending,
                onSend: _sendMessage,
                contentMaxWidth: _contentMaxWidth,
              ),
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
              Text(
                'AI 伴读助手',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppTheme.darkModeText : AppTheme.darkText,
                ),
              ),
              const Spacer(),
              // 清空对话按钮
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
              padding:
                  const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
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
}
