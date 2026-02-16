import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/wp_models.dart';
import '../theme/app_theme.dart';

/// ============================================================
/// 文章卡片组件 — 两种样式
/// 1. HeroArticleCard: 首篇精选大图卡片（带渐变叠加）
/// 2. ArticleCard: 普通文章列表卡片（紧凑横排布局）
/// ============================================================

// ==================== Hero 精选卡片 ====================
// 用于首页第一篇文章，大图 + 渐变叠层 + 白色文字
class HeroArticleCard extends StatelessWidget {
  const HeroArticleCard({
    super.key,
    required this.post,
    required this.onTap,
  });

  final WpPost post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingMd,
        vertical: AppTheme.spacingSm,
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 280,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            boxShadow: AppTheme.elevatedShadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 背景图片 — 带模糊占位加载效果
                if (post.featuredImageUrl != null)
                  CachedNetworkImage(
                    imageUrl: post.featuredImageUrl!,
                    fit: BoxFit.cover,
                    // 加载中占位 — 品牌色背景 + 脉冲动画
                    placeholder: (context, url) => Container(
                      decoration: const BoxDecoration(
                        gradient: AppTheme.heroGradient,
                      ),
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: Colors.white38,
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                    // 加载失败时显示渐变背景
                    errorWidget: (context, url, error) => Container(
                      decoration: const BoxDecoration(
                        gradient: AppTheme.heroGradient,
                      ),
                    ),
                  )
                else
                  // 无图片时的渐变背景
                  Container(
                    decoration: const BoxDecoration(
                      gradient: AppTheme.heroGradient,
                    ),
                  ),

                // 渐变叠加层 — 让底部文字可读
                Container(
                  decoration: const BoxDecoration(
                    gradient: AppTheme.cardOverlayGradient,
                  ),
                ),

                // 文字内容层
                Positioned(
                  left: AppTheme.spacingLg,
                  right: AppTheme.spacingLg,
                  bottom: AppTheme.spacingLg,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 分类标签 — 半透明胶囊形
                      if (post.categories.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(alpha: 0.9),
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusSm),
                          ),
                          child: Text(
                            post.categories.first.toUpperCase(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      const SizedBox(height: 10),

                      // 文章标题 — 大号粗体白色
                      Text(
                        post.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // 作者和阅读时间
                      Row(
                        children: [
                          // 作者头像占位
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: Colors.white24,
                            child: Text(
                              post.author.isNotEmpty
                                  ? post.author[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            post.author,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white70,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 12),
                          // 圆点分隔符
                          Container(
                            width: 4,
                            height: 4,
                            decoration: const BoxDecoration(
                              color: Colors.white38,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${_readTime(post.contentHtml)} min read',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== 普通文章卡片 ====================
// 紧凑的横排布局：左侧文字 + 右侧缩略图
class ArticleCard extends StatelessWidget {
  const ArticleCard({
    super.key,
    required this.post,
    required this.onTap,
  });

  final WpPost post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingMd,
        vertical: AppTheme.spacingSm,
      ),
      child: Material(
        color: isDark ? AppTheme.cardDark : AppTheme.cardLight,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          child: Container(
            padding: const EdgeInsets.all(AppTheme.spacingMd),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              // 只在浅色模式下添加柔和阴影
              boxShadow: isDark ? null : AppTheme.softShadow,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 左侧 — 文字内容区域（占比较大）
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 分类标签
                      if (post.categories.isNotEmpty)
                        Text(
                          post.categories.first.toUpperCase(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppTheme.primaryColor,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      if (post.categories.isNotEmpty)
                        const SizedBox(height: 6),

                      // 文章标题
                      Text(
                        post.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 6),

                      // 摘要
                      Text(
                        post.excerpt.isEmpty
                            ? 'No excerpt available.'
                            : post.excerpt,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 10),

                      // 底部元信息行 — 作者 · 时间 · 阅读时长
                      Row(
                        children: [
                          Text(
                            post.author,
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          _buildDot(),
                          Text(
                            _formatDate(post.date),
                            style: theme.textTheme.labelMedium,
                          ),
                          _buildDot(),
                          Text(
                            '${_readTime(post.contentHtml)} min',
                            style: theme.textTheme.labelMedium,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // 右侧 — 缩略图
                if (post.featuredImageUrl != null) ...[
                  const SizedBox(width: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    child: CachedNetworkImage(
                      imageUrl: post.featuredImageUrl!,
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppTheme.surfaceDark
                              : AppTheme.dividerColor,
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusMd),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryLight,
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusMd),
                        ),
                        child: const Icon(
                          Icons.image_outlined,
                          color: AppTheme.primaryColor,
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

  /// 构建圆点分隔符
  Widget _buildDot() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Container(
        width: 3,
        height: 3,
        decoration: const BoxDecoration(
          color: AppTheme.lightText,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ==================== 工具函数 ====================

/// 格式化日期为友好的短格式（如 "Feb 16"）
String _formatDate(DateTime date) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}';
}

/// 根据 HTML 内容估算阅读时长（分钟）
int _readTime(String html) {
  // 去掉 HTML 标签，只保留纯文字
  final words = html
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .length;
  // 按每分钟 220 词估算
  return (words / 220).ceil().clamp(1, 99);
}
