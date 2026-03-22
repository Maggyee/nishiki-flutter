import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../models/wp_models.dart';
import '../services/bookmark_service.dart';
import '../services/settings_service.dart';
import '../services/wp_api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/article_detail/article_detail_action_bar.dart';
import '../widgets/article_detail/article_detail_ai_fab.dart';
import '../widgets/article_detail/article_detail_app_bar.dart';
import '../widgets/article_detail/article_detail_content.dart';
import '../widgets/ai_companion_panel.dart';

/// ============================================================
/// 文章详情页 — 沉浸式阅读体验 v3
/// 功能完善：
/// - ❤️ Like   — 点赞功能（本地存储 + 心跳动画）
/// - 🔖 Save   — 收藏功能（本地存储 + 书签列表）
/// - 🔗 Share  — 分享功能（系统分享 / 复制链接）
/// - 📖 阅读进度指示条
/// - 🖼️ 有图/无图 自适应 AppBar
/// ============================================================
class ArticleDetailScreen extends StatefulWidget {
  const ArticleDetailScreen({super.key, required this.post});

  final WpPost post;

  @override
  State<ArticleDetailScreen> createState() => _ArticleDetailScreenState();
}

class _ArticleDetailScreenState extends State<ArticleDetailScreen>
    with TickerProviderStateMixin {
  final _api = WpApiService();
  // 滚动控制器 — 用于计算阅读进度
  final _scrollController = ScrollController();
  final ValueNotifier<double> _readProgress = ValueNotifier<double>(0.0);

  // 收藏服务实例
  final _bookmarkService = BookmarkService();
  // 设置服务实例
  final _settingsService = SettingsService();
  late WpPost _currentPost;
  bool _isRefreshingPost = false;

  // 点赞 & 收藏状态
  bool _isLiked = false;
  bool _isSaved = false;

  // 动画控制器 — 收藏弹跳动画
  late AnimationController _saveAnimController;

  // AI 伴读按钮的脉冲呼吸动画
  late AnimationController _aiFabPulseCtrl;
  late Animation<double> _aiFabPulseAnim;
  late Animation<double> _saveScaleAnim;

  // 是否有特色图片
  bool get _hasImage =>
      _currentPost.featuredImageUrl != null &&
      _currentPost.featuredImageUrl!.isNotEmpty;

  bool _dragStartedFromLeftEdge = false;
  double _edgeDragDistance = 0.0;

  bool get _showBackToTop => _readProgress.value >= 0.18;

  @override
  void initState() {
    super.initState();
    _currentPost = widget.post;
    _scrollController.addListener(_updateProgress);
    // 监听字体大小变化
    _settingsService.fontScale.addListener(_onFontScaleChanged);

    // 初始化收藏动画（向上弹跳效果）
    _saveAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _saveScaleAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.0,
          end: 1.25,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.25,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.bounceOut)),
        weight: 60,
      ),
    ]).animate(_saveAnimController);

    // AI 伴读按钮的脉冲呼吸动画 — 吸引用户注意
    _aiFabPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _aiFabPulseAnim = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _aiFabPulseCtrl, curve: Curves.easeInOut),
    );
    // 只在配置了 API Key 时启动动画
    if (AppConfig.hasAiProxy) {
      _aiFabPulseCtrl.repeat(reverse: true);
    }

    // 加载本地存储状态
    _loadLocalState();
    _settingsService.markAsRead(_currentPost);
    _hydratePostDetail();
  }

  /// 从本地存储读取点赞和收藏状态
  Future<void> _loadLocalState() async {
    await _bookmarkService.init();
    if (mounted) {
      setState(() {
        _isLiked = _bookmarkService.isLiked(
          _currentPost.id,
          sourceBaseUrl: _currentPost.sourceBaseUrl,
        );
        _isSaved = _bookmarkService.isSaved(
          _currentPost.id,
          sourceBaseUrl: _currentPost.sourceBaseUrl,
        );
      });
    }
  }

  Future<void> _hydratePostDetail() async {
    if (_currentPost.contentHtml.isEmpty) {
      final cachedPost = await _api.getCachedPostById(
        widget.post.id,
        sourceBaseUrl: widget.post.sourceBaseUrl,
      );
      if (cachedPost != null && cachedPost.contentHtml.isNotEmpty && mounted) {
        setState(() {
          _currentPost = cachedPost;
        });
        _settingsService.markAsRead(cachedPost);
      }
    }

    if (_isRefreshingPost) return;
    _isRefreshingPost = true;
    try {
      final refreshedPost = await _api.fetchPostById(
        widget.post.id,
        sourceBaseUrl: widget.post.sourceBaseUrl,
      );
      if (refreshedPost != null && mounted) {
        setState(() {
          _currentPost = refreshedPost;
        });
        _settingsService.markAsRead(refreshedPost);
      }
    } catch (_) {
      // Keep showing the current article snapshot when refresh fails.
    } finally {
      _isRefreshingPost = false;
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateProgress);
    _settingsService.fontScale.removeListener(_onFontScaleChanged);
    _scrollController.dispose();
    _readProgress.dispose();
    _saveAnimController.dispose();
    _aiFabPulseCtrl.dispose();
    super.dispose();
  }

  void _onFontScaleChanged() {
    if (mounted) setState(() {});
  }

  /// 计算当前阅读进度（0.0 - 1.0）
  void _updateProgress() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll <= 0) return;
    final next = (_scrollController.offset / maxScroll).clamp(0.0, 1.0);
    if ((next - _readProgress.value).abs() >= 0.01) {
      _readProgress.value = next;
    }
  }

  // ==================== 点赞逻辑 ====================
  Future<void> _handleLike() async {
    // 触觉反馈
    HapticFeedback.lightImpact();

    // 切换本地存储状态
    final nowLiked = await _bookmarkService.toggleLike(
      _currentPost.id,
      sourceBaseUrl: _currentPost.sourceBaseUrl,
      postData: _currentPost.toSummaryMap(),
    );

    if (mounted) {
      setState(() => _isLiked = nowLiked);

      // 显示简短提示
      _showFeedbackSnack(
        icon: nowLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        message: nowLiked ? '已点赞' : '已取消点赞',
        color: nowLiked ? const Color(0xFFFF4B6E) : null,
      );
    }
  }

  // ==================== 收藏逻辑 ====================
  Future<void> _handleSave() async {
    // 触觉反馈
    HapticFeedback.mediumImpact();

    // 切换本地存储状态，同时传入文章摘要数据
    final nowSaved = await _bookmarkService.toggleSave(
      _currentPost.id,
      sourceBaseUrl: _currentPost.sourceBaseUrl,
      postData: _currentPost.toSummaryMap(),
    );

    if (mounted) {
      setState(() => _isSaved = nowSaved);
      _saveAnimController.forward(from: 0.0);

      _showFeedbackSnack(
        icon: nowSaved
            ? Icons.bookmark_rounded
            : Icons.bookmark_outline_rounded,
        message: nowSaved ? '已添加到收藏' : '已从收藏中移除',
        color: nowSaved ? AppTheme.primaryColor : null,
      );
    }
  }

  // ==================== 分享逻辑 ====================
  Future<void> _handleShare() async {
    HapticFeedback.lightImpact();

    final shareUrl = _currentPost.link.isNotEmpty
        ? _currentPost.link
        : 'https://blog.nishiki.icu'; // 降级 URL

    final shareText = '${_currentPost.title}\n\n$shareUrl';

    try {
      // 使用系统分享面板
      await Share.share(shareText, subject: _currentPost.title);
    } catch (_) {
      // Web 环境或分享失败时，回退为复制链接
      await Clipboard.setData(ClipboardData(text: shareUrl));
      if (mounted) {
        _showFeedbackSnack(
          icon: Icons.check_circle_outline_rounded,
          message: '链接已复制到剪贴板',
          color: AppTheme.primaryColor,
        );
      }
    }
  }

  /// 显示操作反馈
  void _showFeedbackSnack({
    required IconData icon,
    required String message,
    Color? color,
  }) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color ?? Colors.white, size: 20),
            const SizedBox(width: 10),
            Text(message, style: const TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        duration: const Duration(seconds: 2),
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? AppTheme.cardDark
            : const Color(0xFF2D3142),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      // 只在有图时才让内容延伸到 AppBar 后面
      extendBodyBehindAppBar: _hasImage,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: _handleHorizontalDragStart,
        onHorizontalDragUpdate: _handleHorizontalDragUpdate,
        onHorizontalDragEnd: _handleHorizontalDragEnd,
        child: Stack(
          children: [
            // ==================== 主内容 ====================
            CustomScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              slivers: [
                // 根据是否有特色图片，使用不同的 AppBar 样式
                _hasImage
                    ? ArticleDetailImageAppBar(
                        post: _currentPost,
                        isSaved: _isSaved,
                        saveScaleAnimation: _saveScaleAnim,
                        onBack: _handleBack,
                        onSave: _handleSave,
                        onShare: _handleShare,
                      )
                    : ArticleDetailCleanAppBar(
                        isDark: isDark,
                        isSaved: _isSaved,
                        saveScaleAnimation: _saveScaleAnim,
                        onBack: _handleBack,
                        onSave: _handleSave,
                        onShare: _handleShare,
                      ),

                // 文章内容区域
                SliverToBoxAdapter(
                  child: ArticleDetailContent(
                    post: _currentPost,
                    hasImage: _hasImage,
                    isDark: isDark,
                    fontScale: _settingsService.fontScale.value,
                    onOpenInBrowser: _openInBrowser,
                    bottomActions: _buildBottomActions(isDark),
                  ),
                ),
              ],
            ),

            // ==================== 阅读进度条 ====================
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: ValueListenableBuilder<double>(
                  valueListenable: _readProgress,
                  builder: (context, progress, _) {
                    if (progress <= 0.001) return const SizedBox.shrink();
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        height: 4,
                        width: MediaQuery.of(context).size.width * progress,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              AppTheme.primaryColor,
                              AppTheme.primaryDark,
                            ],
                          ),
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(4),
                            bottomRight: Radius.circular(4),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryColor.withValues(
                                alpha: 0.28,
                              ),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // ==================== AI 伴读悬浮按钮 ====================
            if (AppConfig.hasAiProxy)
              Positioned(
                right: 20,
                bottom: 24 + MediaQuery.of(context).padding.bottom,
                child: _buildAiFab(isDark),
              ),
            Positioned(
              left: 20,
              bottom: 24 + MediaQuery.of(context).padding.bottom,
              child: ValueListenableBuilder<double>(
                valueListenable: _readProgress,
                builder: (context, progress, _) {
                  return AnimatedSlide(
                    duration: const Duration(milliseconds: 180),
                    offset: _showBackToTop ? Offset.zero : const Offset(0, 1.4),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: _showBackToTop ? 1 : 0,
                      child: FilledButton.icon(
                        onPressed: _showBackToTop ? _scrollToTop : null,
                        icon: const Icon(Icons.vertical_align_top_rounded),
                        label: Text('${(progress * 100).round()}%'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          backgroundColor: isDark
                              ? AppTheme.cardDark
                              : Colors.white,
                          foregroundColor: isDark
                              ? AppTheme.darkModeText
                              : AppTheme.darkText,
                          side: BorderSide(
                            color: isDark
                                ? const Color(0xFF2B3442)
                                : AppTheme.dividerColor,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 底部操作栏（带动画） ====================
  Widget _buildBottomActions(bool isDark) {
    return ArticleDetailActionBar(
      isDark: isDark,
      isLiked: _isLiked,
      isSaved: _isSaved,
      onLike: _handleLike,
      onSave: _handleSave,
      onShare: _handleShare,
    );
  }

  /// 在浏览器中打开原文链接
  Future<void> _openInBrowser(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        // Web 环境可能不支持 launchUrl，回退为复制链接
        await Clipboard.setData(ClipboardData(text: url));
        if (mounted) {
          _showFeedbackSnack(
            icon: Icons.check_circle_outline_rounded,
            message: '链接已复制到剪贴板',
            color: AppTheme.primaryColor,
          );
        }
      }
    }
  }

  // ==================== AI 伴读悬浮按钮 ====================
  /// 构建 AI 伴读悬浮按钮 — 带渐变色和脉冲呼吸动画
  Widget _buildAiFab(bool isDark) {
    return ArticleDetailAiFab(animation: _aiFabPulseAnim, onTap: _openAiPanel);
  }

  /// 打开 AI 伴读底部面板
  void _openAiPanel() {
    HapticFeedback.mediumImpact();
    // 打开面板时暂停 FAB 动画
    _aiFabPulseCtrl.stop();
    _aiFabPulseCtrl.value = 0.0; // 重置为原始大小

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6, // 初始高度为屏幕 60%
        minChildSize: 0.3, // 最小高度为屏幕 30%
        maxChildSize: 0.9, // 最大高度为屏幕 90%
        builder: (context, scrollController) {
          return AiCompanionPanel(post: _currentPost);
        },
      ),
    ).then((_) {
      // 面板关闭后恢复 FAB 脉冲动画
      if (mounted && AppConfig.hasAiProxy) {
        _aiFabPulseCtrl.repeat(reverse: true);
      }
    });
  }

  void _handleBack() {
    HapticFeedback.selectionClick();
    Navigator.of(context).maybePop();
  }

  Future<void> _scrollToTop() async {
    HapticFeedback.selectionClick();
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _handleHorizontalDragStart(DragStartDetails details) {
    _dragStartedFromLeftEdge = details.globalPosition.dx <= 24;
    _edgeDragDistance = 0.0;
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_dragStartedFromLeftEdge) return;
    _edgeDragDistance += details.primaryDelta ?? 0.0;
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    if (!_dragStartedFromLeftEdge) return;

    final velocity = details.primaryVelocity ?? 0.0;
    final shouldPop = _edgeDragDistance > 88 || velocity > 900;

    if (shouldPop && mounted && Navigator.of(context).canPop()) {
      HapticFeedback.mediumImpact();
      Navigator.of(context).maybePop();
    }

    _dragStartedFromLeftEdge = false;
    _edgeDragDistance = 0.0;
  }
}
