import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/wp_models.dart';
import '../../theme/app_theme.dart';

class ArticleDetailImageAppBar extends StatelessWidget {
  const ArticleDetailImageAppBar({
    super.key,
    required this.post,
    required this.isSaved,
    required this.saveScaleAnimation,
    required this.onBack,
    required this.onSave,
    required this.onShare,
  });

  final WpPost post;
  final bool isSaved;
  final Animation<double> saveScaleAnimation;
  final VoidCallback onBack;
  final VoidCallback onSave;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      stretch: false,
      title: null,
      backgroundColor: Colors.transparent,
      leading: Padding(
        padding: const EdgeInsets.all(8),
        child: _CircleButton(
          icon: Icons.arrow_back_rounded,
          semanticLabel: '返回',
          onTap: onBack,
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: AnimatedBuilder(
            animation: saveScaleAnimation,
            builder: (context, _) => _CircleButton(
              icon: isSaved
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_outline_rounded,
              semanticLabel: isSaved ? '取消收藏' : '收藏文章',
              onTap: onSave,
              iconScale: saveScaleAnimation.value,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
          child: _CircleButton(
            icon: Icons.share_rounded,
            semanticLabel: '分享文章',
            onTap: onShare,
          ),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [StretchMode.zoomBackground],
        background: Stack(
          fit: StackFit.expand,
          children: [
            Hero(
              tag: 'post_image_${post.id}',
              child: CachedNetworkImage(
                imageUrl: post.featuredImageUrl!,
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
            ),
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
            if (post.categories.isNotEmpty)
              Positioned(
                left: 20,
                bottom: 40,
                child: ArticleDetailCategoryChips(
                  categories: post.categories,
                  onDark: true,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ArticleDetailCleanAppBar extends StatelessWidget {
  const ArticleDetailCleanAppBar({
    super.key,
    required this.isDark,
    required this.isSaved,
    required this.saveScaleAnimation,
    required this.onBack,
    required this.onSave,
    required this.onShare,
  });

  final bool isDark;
  final bool isSaved;
  final Animation<double> saveScaleAnimation;
  final VoidCallback onBack;
  final VoidCallback onSave;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 0,
      toolbarHeight: 56,
      backgroundColor: isDark ? AppTheme.scaffoldDark : Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        tooltip: '返回',
        icon: Icon(
          Icons.arrow_back_rounded,
          color: isDark ? AppTheme.darkModeText : AppTheme.darkText,
        ),
        onPressed: onBack,
      ),
      actions: [
        IconButton(
          tooltip: isSaved ? '取消收藏' : '收藏文章',
          icon: AnimatedBuilder(
            animation: saveScaleAnimation,
            builder: (context, child) => Transform.scale(
              scale: saveScaleAnimation.value,
              child: Icon(
                isSaved
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_outline_rounded,
                color: isSaved
                    ? AppTheme.primaryColor
                    : (isDark ? AppTheme.darkModeText : AppTheme.darkText),
              ),
            ),
          ),
          onPressed: onSave,
        ),
        IconButton(
          tooltip: '分享文章',
          icon: Icon(
            Icons.share_rounded,
            color: isDark ? AppTheme.darkModeText : AppTheme.darkText,
          ),
          onPressed: onShare,
        ),
        const SizedBox(width: 4),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          color: isDark ? AppTheme.surfaceDark : AppTheme.dividerColor,
        ),
      ),
    );
  }
}

class ArticleDetailCategoryChips extends StatelessWidget {
  const ArticleDetailCategoryChips({
    super.key,
    required this.categories,
    required this.onDark,
  });

  final List<String> categories;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: categories.take(3).map((catName) {
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
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
    this.iconScale = 1.0,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;
  final double iconScale;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: semanticLabel,
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
    );
  }
}
