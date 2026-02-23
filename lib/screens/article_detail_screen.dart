import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_html_table/flutter_html_table.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/wp_models.dart';
import '../theme/app_theme.dart';
import '../services/bookmark_service.dart';
import '../services/settings_service.dart';

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
  // 滚动控制器 — 用于计算阅读进度
  final _scrollController = ScrollController();
  final ValueNotifier<double> _readProgress = ValueNotifier<double>(0.0);

  // 收藏服务实例
  final _bookmarkService = BookmarkService();
  // 设置服务实例
  final _settingsService = SettingsService();

  // 点赞 & 收藏状态
  bool _isLiked = false;
  bool _isSaved = false;

  // 动画控制器 — 收藏弹跳动画
  late AnimationController _saveAnimController;
  late Animation<double> _saveScaleAnim;

  // 是否有特色图片
  bool get _hasImage =>
      widget.post.featuredImageUrl != null &&
      widget.post.featuredImageUrl!.isNotEmpty;

  @override
  void initState() {
    super.initState();
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
        tween: Tween<double>(begin: 1.0, end: 1.25).chain(
          CurveTween(curve: Curves.easeOutCubic),
        ),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.25, end: 1.0).chain(
          CurveTween(curve: Curves.bounceOut),
        ),
        weight: 60,
      ),
    ]).animate(_saveAnimController);

    // 加载本地存储状态
    _loadLocalState();
  }

  /// 从本地存储读取点赞和收藏状态
  Future<void> _loadLocalState() async {
    await _bookmarkService.init();
    if (mounted) {
      setState(() {
        _isLiked = _bookmarkService.isLiked(widget.post.id);
        _isSaved = _bookmarkService.isSaved(widget.post.id);
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateProgress);
    _settingsService.fontScale.removeListener(_onFontScaleChanged);
    _scrollController.dispose();
    _readProgress.dispose();
    _saveAnimController.dispose();
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
    final nowLiked = await _bookmarkService.toggleLike(widget.post.id);

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
      widget.post.id,
      postData: widget.post.toSummaryMap(),
    );

    if (mounted) {
      setState(() => _isSaved = nowSaved);
      _saveAnimController.forward(from: 0.0);

      _showFeedbackSnack(
        icon: nowSaved ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
        message: nowSaved ? '已添加到收藏' : '已从收藏中移除',
        color: nowSaved ? AppTheme.primaryColor : null,
      );
    }
  }

  // ==================== 分享逻辑 ====================
  Future<void> _handleShare() async {
    HapticFeedback.lightImpact();

    final shareUrl = widget.post.link.isNotEmpty
        ? widget.post.link
        : 'https://blog.nishiki.icu'; // 降级 URL

    final shareText = '${widget.post.title}\n\n$shareUrl';

    try {
      // 使用系统分享面板
      await Share.share(
        shareText,
        subject: widget.post.title,
      );
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
            Text(
              message,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
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
      body: Stack(
        children: [
          // ==================== 主内容 ====================
          CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            slivers: [
              // 根据是否有特色图片，使用不同的 AppBar 样式
              _hasImage ? _buildImageAppBar(theme) : _buildCleanAppBar(theme, isDark),

              // 文章内容区域
              SliverToBoxAdapter(
                child: _buildArticleContent(theme, isDark),
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
                          colors: [Color(0xFF1abc9c), Color(0xFF4EE2C0)],
                        ),
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(4),
                          bottomRight: Radius.circular(4),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF1abc9c).withValues(alpha: 0.4),
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
        ],
      ),
    );
  }

  // ==================== 有图时的大图 AppBar ====================
  Widget _buildImageAppBar(ThemeData theme) {
    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      stretch: false,
      title: null,
      backgroundColor: Colors.transparent,
      // 返回按钮 — 半透明毛玻璃风格
      leading: Padding(
        padding: const EdgeInsets.all(8),
        child: _buildCircleButton(
          icon: Icons.arrow_back_rounded,
          semanticLabel: 'Back',
          onTap: () => Navigator.of(context).pop(),
        ),
      ),
      // 右侧操作按钮
      actions: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: AnimatedBuilder(
            animation: _saveScaleAnim,
            builder: (context, _) => _buildCircleButton(
              icon: _isSaved ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
              semanticLabel: _isSaved ? 'Remove bookmark' : 'Bookmark article',
              onTap: _handleSave,
              iconScale: _saveScaleAnim.value,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
          child: _buildCircleButton(
            icon: Icons.share_rounded,
            semanticLabel: 'Share article',
            onTap: _handleShare,
          ),
        ),
      ],
      // 大图区域 — 视差效果
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [StretchMode.zoomBackground],
        background: Stack(
          fit: StackFit.expand,
          children: [
            // 背景图片
            CachedNetworkImage(
              imageUrl: widget.post.featuredImageUrl!,
              fit: BoxFit.cover,
              memCacheWidth: 1400,
              memCacheHeight: 900,
              maxWidthDiskCache: 1800,
              fadeInDuration: const Duration(milliseconds: 120),
              placeholder: (context, url) => Container(
                decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
                child: const Center(
                  child: CircularProgressIndicator(
                    color: Colors.white54,
                    strokeWidth: 2,
                  ),
                ),
              ),
              errorWidget: (context, url, error) => Container(
                decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
                child: const Center(
                  child: Icon(Icons.image_outlined, color: Colors.white38, size: 48),
                ),
              ),
            ),
            // 底部渐变遮罩
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.1),
                    Colors.black.withValues(alpha: 0.5),
                  ],
                  stops: const [0.4, 1.0],
                ),
              ),
            ),
            // 大图底部的分类标签
            if (widget.post.categories.isNotEmpty)
              Positioned(
                left: 20,
                bottom: 40,
                child: _buildCategoryChips(onDark: true),
              ),
          ],
        ),
      ),
    );
  }

  // ==================== 无图时的简洁 AppBar ====================
  Widget _buildCleanAppBar(ThemeData theme, bool isDark) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 0,
      toolbarHeight: 56,
      backgroundColor: isDark ? AppTheme.scaffoldDark : Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      // 返回按钮
      leading: IconButton(
        tooltip: 'Back',
        icon: Icon(
          Icons.arrow_back_rounded,
          color: isDark ? AppTheme.darkModeText : AppTheme.darkText,
        ),
        onPressed: () => Navigator.of(context).pop(),
      ),
      // 右侧操作按钮
      actions: [
        // 收藏按钮
        IconButton(
          tooltip: _isSaved ? 'Remove bookmark' : 'Bookmark article',
          icon: AnimatedBuilder(
            animation: _saveScaleAnim,
            builder: (context, child) => Transform.scale(
              scale: _saveScaleAnim.value,
              child: Icon(
                _isSaved ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
                color: _isSaved ? AppTheme.primaryColor : (isDark ? AppTheme.darkModeText : AppTheme.darkText),
              ),
            ),
          ),
          onPressed: _handleSave,
        ),
        // 分享按钮
        IconButton(
          tooltip: 'Share article',
          icon: Icon(
            Icons.share_rounded,
            color: isDark ? AppTheme.darkModeText : AppTheme.darkText,
          ),
          onPressed: _handleShare,
        ),
        const SizedBox(width: 4),
      ],
      // 底部精细分割线
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          color: isDark ? AppTheme.surfaceDark : AppTheme.dividerColor,
        ),
      ),
    );
  }

  // ==================== 文章内容主体 ====================
  Widget _buildArticleContent(ThemeData theme, bool isDark) {
    return Container(
      // 有图时上移覆盖大图底部，形成卡片上浮效果
      transform: _hasImage ? Matrix4.translationValues(0, -24, 0) : null,
      decoration: _hasImage
          ? BoxDecoration(
              color: isDark ? AppTheme.scaffoldDark : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppTheme.radiusXl),
              ),
            )
          : null,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              _hasImage ? 28 : 20,
              20,
              40,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 无图时在内容区顶部显示分类标签
            if (!_hasImage && widget.post.categories.isNotEmpty) ...[
              _buildCategoryChips(onDark: false),
              const SizedBox(height: 16),
            ],

            if (_hasImage && widget.post.categories.isNotEmpty)
              const SizedBox(height: 4),

            // ==================== 文章标题 ====================
            Text(
              widget.post.title,
              style: theme.textTheme.headlineLarge?.copyWith(
                fontSize: 26 * _settingsService.fontScale.value, // 标题也跟随缩放
                fontWeight: FontWeight.w800,
                height: 1.25,
                letterSpacing: -0.5,
                color: isDark ? AppTheme.darkModeText : AppTheme.darkText,
              ),
            ),

            const SizedBox(height: 20),

            // ==================== 作者信息行 ====================
            _buildAuthorRow(theme, isDark),

            const SizedBox(height: 24),

            // ==================== 分割线 ====================
            Container(
              height: 1,
              color: isDark ? AppTheme.surfaceDark : AppTheme.dividerColor,
            ),

            const SizedBox(height: 24),

            // ==================== 文章 HTML 内容 ====================
            // 使用 SelectionArea 包装使得文章文本可被用户自由框选复制
            SelectionArea(
              child: Html(
                data: widget.post.contentHtml,
                style: _buildHtmlStyles(isDark),
                extensions: [
                  const TableHtmlExtension(),
                ],
              ),
            ),

            const SizedBox(height: 40),

            // ==================== 底部操作栏 ====================
            _buildBottomActions(isDark),

            const SizedBox(height: 16),

            // ==================== 打开原文链接 ====================
            if (widget.post.link.isNotEmpty) ...[
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: () => _openInBrowser(widget.post.link),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('在浏览器中查看原文'),
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
          ],
        ),
      ),
        ),
      ),
    );
  }

  // ==================== 分类标签组 ====================
  Widget _buildCategoryChips({required bool onDark}) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: widget.post.categories.take(3).map((catName) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: onDark
                ? Colors.white.withValues(alpha: 0.2)
                : AppTheme.primaryLight,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            catName,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: onDark ? Colors.white : AppTheme.primaryColor,
            ),
          ),
        );
      }).toList(),
    );
  }

  // ==================== 作者信息行 ====================
  Widget _buildAuthorRow(ThemeData theme, bool isDark) {
    return Row(
      children: [
        // 作者头像 — 渐变圆角方块
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: AppTheme.heroGradient,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              widget.post.author.isNotEmpty
                  ? widget.post.author[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // 作者名 + 日期 + 阅读时长
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.post.author,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: isDark ? AppTheme.darkModeText : AppTheme.darkText,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${_formatFullDate(widget.post.date)} · ${_readTime(widget.post.contentHtml)} min read',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppTheme.darkModeSecondary : AppTheme.lightText,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==================== 底部操作栏（带动画） ====================
  Widget _buildBottomActions(bool isDark) {
    return Column(
      children: [
        // 分割线
        Container(
          height: 1,
          color: isDark ? AppTheme.surfaceDark : AppTheme.dividerColor,
        ),
        const SizedBox(height: 24),

        // 操作按钮行
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ❤️ 点赞按钮 — 带真实的物理跳动效果
            _BouncingActionButton(
              icon: _isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              label: _isLiked ? '已赞' : '点赞',
              isActive: _isLiked,
              activeColor: const Color(0xFFFF4B6E),
              onTap: _handleLike,
              isDark: isDark,
            ),
            const SizedBox(width: 36),
            // 🔖 收藏按钮 — 带真实的物理跳动效果
            _BouncingActionButton(
              icon: _isSaved ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
              label: _isSaved ? '已收藏' : '收藏',
              isActive: _isSaved,
              activeColor: AppTheme.primaryColor,
              onTap: _handleSave,
              isDark: isDark,
            ),
            const SizedBox(width: 36),
            // 🔗 分享按钮
            _BouncingActionButton(
              icon: Icons.share_outlined,
              label: '分享',
              isActive: false,
              activeColor: AppTheme.primaryColor,
              onTap: _handleShare,
              isDark: isDark,
            ),
          ],
        ),
      ],
    );
  }

  // ==================== HTML 样式定义 ====================
  Map<String, Style> _buildHtmlStyles(bool isDark) {
    return {
      'body': Style(
        margin: Margins.zero,
        lineHeight: const LineHeight(2.0),
        letterSpacing: 0.3,
        fontSize: FontSize(17 * _settingsService.fontScale.value),
        color: isDark ? AppTheme.darkModeText : AppTheme.darkText,
      ),
      'h1': Style(
        margin: Margins.only(top: 32, bottom: 14),
        fontSize: FontSize(26 * _settingsService.fontScale.value),
        fontWeight: FontWeight.w800,
        color: isDark ? AppTheme.darkModeText : AppTheme.darkText,
      ),
      'h2': Style(
        margin: Margins.only(top: 32, bottom: 16),
        padding: HtmlPaddings.only(left: 12),
        border: const Border(left: BorderSide(color: AppTheme.primaryColor, width: 4)),
        fontSize: FontSize(22 * _settingsService.fontScale.value),
        fontWeight: FontWeight.w700,
        color: isDark ? AppTheme.darkModeText : AppTheme.darkText,
      ),
      'h3': Style(
        margin: Margins.only(top: 20, bottom: 8),
        fontSize: FontSize(19 * _settingsService.fontScale.value),
        fontWeight: FontWeight.w600,
        color: isDark ? AppTheme.darkModeText : AppTheme.darkText,
      ),
      'p': Style(
        margin: Margins.only(bottom: 16),
      ),
      'blockquote': Style(
        padding: HtmlPaddings.only(left: 16, top: 12, bottom: 12, right: 12),
        margin: Margins.only(top: 16, bottom: 16),
        backgroundColor: isDark ? AppTheme.cardDark : AppTheme.primaryLight,
        border: const Border(
          left: BorderSide(
            color: AppTheme.primaryColor,
            width: 3,
          ),
        ),
        fontStyle: FontStyle.italic,
      ),
      'a': Style(
        color: AppTheme.primaryColor,
        textDecoration: TextDecoration.none,
      ),
      'img': Style(
        margin: Margins.only(top: 16, bottom: 16),
      ),
      'ul': Style(
        margin: Margins.only(bottom: 16),
      ),
      'ol': Style(
        margin: Margins.only(bottom: 16),
      ),
      'li': Style(
        margin: Margins.only(bottom: 8),
        lineHeight: const LineHeight(1.6),
      ),
      'code': Style(
        backgroundColor:
            isDark ? AppTheme.cardDark : const Color(0xFFF5F5F5),
        padding: HtmlPaddings.symmetric(horizontal: 6, vertical: 2),
        fontSize: FontSize(14 * _settingsService.fontScale.value),
      ),
      'pre': Style(
        backgroundColor:
            isDark ? AppTheme.cardDark : const Color(0xFFF5F5F5),
        padding: HtmlPaddings.all(16),
        margin: Margins.only(top: 16, bottom: 16),
      ),
      'table': Style(
        margin: Margins.only(top: 16, bottom: 16),
        backgroundColor: isDark ? AppTheme.surfaceDark : Colors.white,
      ),
      'th': Style(
        padding: HtmlPaddings.all(12),
        backgroundColor: isDark ? AppTheme.surfaceDark : const Color(0xFFF4F9F8),
        fontWeight: FontWeight.w700,
        border: Border(bottom: BorderSide(color: isDark ? AppTheme.surfaceDark : AppTheme.dividerColor, width: 1)),
      ),
      'td': Style(
        padding: HtmlPaddings.all(12),
        border: Border(bottom: BorderSide(color: isDark ? AppTheme.surfaceDark : AppTheme.dividerColor, width: 1)),
      ),
    };
  }

  // ==================== 通用组件 ====================

  /// 半透明圆形按钮（用在大图上方）
  Widget _buildCircleButton({
    required IconData icon,
    required String semanticLabel,
    required VoidCallback onTap,
    double iconScale = 1.0,
  }) {
    return Tooltip(
      message: semanticLabel,
      child: Semantics(
        button: true,
        label: semanticLabel,
        child: Material(
          color: Colors.black.withValues(alpha: 0.35),
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            splashColor: Colors.white.withValues(alpha: 0.12),
            highlightColor: Colors.white.withValues(alpha: 0.06),
            onTap: onTap,
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              child: Transform.scale(
                scale: iconScale,
                child: Icon(icon, color: Colors.white, size: 20),
              ),
            ),
          ),
        ),
      ),
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
}

// ==================== 工具函数 ====================

/// 格式化日期为完整格式（如 "Feb 16, 2026"）
String _formatFullDate(DateTime date) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

/// 估算阅读时长（按中英文混合计算）
int _readTime(String html) {
  // 移除 HTML 标签
  final text = html
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .trim();
  // 计算中文字符数（每个算一个"词"）
  final cjkCount = RegExp(r'[\u4e00-\u9fff\u3040-\u309f\u30a0-\u30ff]')
      .allMatches(text)
      .length;
  // 计算英文单词数
  final engWords = text
      .replaceAll(RegExp(r'[\u4e00-\u9fff\u3040-\u309f\u30a0-\u30ff]'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .length;
  // 中文阅读速度约 400 字/分，英文约 220 词/分
  final totalMinutes = (cjkCount / 400) + (engWords / 220);
  return totalMinutes.ceil().clamp(1, 99);
}

// ==================== 底部动作按钮的独立微动画组件 ====================
// 将按钮分离为 StatefulWidget 以提供物理层面的向上跳跃(Translate)效果
class _BouncingActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final Color activeColor;
  final VoidCallback onTap;
  final bool isDark;

  const _BouncingActionButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.activeColor,
    required this.onTap,
    required this.isDark,
  });

  @override
  State<_BouncingActionButton> createState() => _BouncingActionButtonState();
}

class _BouncingActionButtonState extends State<_BouncingActionButton> with SingleTickerProviderStateMixin {
  late AnimationController _jumpController;
  late Animation<double> _jumpAnim;

  @override
  void initState() {
    super.initState();
    // 快速的跳起、回弹周期
    _jumpController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );

    _jumpAnim = TweenSequence<double>([
      TweenSequenceItem(
        // 向上急速跳起 14 逻辑像素
        tween: Tween<double>(begin: 0.0, end: -14.0).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 35,
      ),
      TweenSequenceItem(
        // Q弹平滑落下
        tween: Tween<double>(begin: -14.0, end: 0.0).chain(CurveTween(curve: Curves.bounceOut)),
        weight: 65,
      ),
    ]).animate(_jumpController);
  }

  @override
  void dispose() {
    _jumpController.dispose();
    super.dispose();
  }

  void _handleTap() {
    widget.onTap();
    // 强制每次点击都从头播放跳跃动画
    _jumpController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.isActive;
    final activeColor = widget.activeColor;
    final isDark = widget.isDark;

    final buttonContent = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isActive
                ? activeColor.withValues(alpha: 0.15)
                : (isDark ? AppTheme.surfaceDark : AppTheme.primaryLight),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isActive ? activeColor.withValues(alpha: 0.5) : Colors.transparent, 
              width: 1.5,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: activeColor.withValues(alpha: 0.3),
                      blurRadius: 12,
                      spreadRadius: 4,
                      offset: const Offset(0, 2),
                    )
                  ]
                : [],
          ),
          child: AnimatedScale(
            scale: isActive ? 1.05 : 1.0,
            duration: const Duration(milliseconds: 400),
            curve: Curves.elasticOut,
            child: Icon(
              widget.icon,
              size: 24,
              color: isActive ? activeColor : AppTheme.primaryColor,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
            color: isActive ? activeColor : AppTheme.lightText,
          ),
        ),
      ],
    );

    // 用 AnimatedBuilder 将跳动位移量应用在整个按钮上
    return AnimatedBuilder(
      animation: _jumpAnim,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _jumpAnim.value),
          child: child,
        );
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
          onTap: _handleTap,
          child: buttonContent,
        ),
      ),
    );
  }
}
