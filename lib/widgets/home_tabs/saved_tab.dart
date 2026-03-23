import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../models/wp_models.dart';
import '../../screens/article_detail_screen.dart';
import '../../services/bookmark_service.dart';
import '../../services/wp_api_service.dart';
import '../../theme/app_theme.dart';

/// 收藏 Tab — 收藏文章列表（支持滑动取消收藏）
class SavedTab extends StatelessWidget {
  const SavedTab({
    super.key,
    required this.savedPosts,
    required this.savedLoading,
    required this.onRefresh,
    required this.onPostsChanged,
    required this.onGoToTab,
  });

  // 收藏文章列表
  final List<WpPost> savedPosts;
  // 是否正在加载
  final bool savedLoading;
  // 刷新回调
  final Future<void> Function() onRefresh;
  // 收藏列表数据变化时通知父级
  final VoidCallback onPostsChanged;
  // 跳转到指定 Tab 的回调
  final void Function(int tabIndex) onGoToTab;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 加载中状态
    if (savedLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // 空状态 — 引导页
    if (savedPosts.isEmpty) {
      return _buildEmptyState(context, isDark);
    }

    // 有收藏内容
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: savedPosts.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildHeader(context, isDark);
          }
          if (index == 1) {
            return const SizedBox(height: 8);
          }
          final post = savedPosts[index - 2];
          return _SavedCard(
            post: post,
            isDark: isDark,
            onPostsChanged: onPostsChanged,
          );
        },
      ),
    );
  }

  /// 空状态引导页
  Widget _buildEmptyState(BuildContext context, bool isDark) {
    return Center(
      key: const ValueKey('saved.empty_state'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark
                    ? AppTheme.primaryColor.withValues(alpha: 0.15)
                    : AppTheme.primaryLight,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.bookmark_outline_rounded,
                size: 56,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '暂无收藏文章',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: isDark ? AppTheme.darkModeText : AppTheme.darkText,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '在文章详情页点击书签图标 🔖\n即可将喜欢的文章收藏到这里',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.6,
                color: isDark
                    ? AppTheme.darkModeSecondary
                    : AppTheme.lightText,
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              key: const ValueKey('saved.empty_state.cta'),
              onPressed: () => onGoToTab(0),
              icon: const Icon(Icons.explore_outlined, size: 18),
              label: const Text('去发现文章'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 收藏页顶部标题区域
  Widget _buildHeader(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '我的收藏',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? AppTheme.darkModeText
                            : AppTheme.darkText,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '共 ${savedPosts.length} 篇文章',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? AppTheme.darkModeSecondary
                        : AppTheme.lightText,
                  ),
                ),
              ],
            ),
          ),
          if (savedPosts.isNotEmpty)
            TextButton.icon(
              onPressed: () => _showClearSavedDialog(context),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('清空'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.redAccent,
                textStyle: const TextStyle(fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }

  /// 清空收藏确认对话框
  void _showClearSavedDialog(BuildContext context) {
    final bookmarkService = BookmarkService();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空收藏？'),
        content: const Text('确定要清空所有收藏的文章吗？此操作不可撤销。'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              for (final post in savedPosts) {
                await bookmarkService.toggleSave(post.id);
              }
              onPostsChanged();
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }
}

/// 收藏卡片 — 支持滑动取消收藏
class _SavedCard extends StatelessWidget {
  const _SavedCard({
    required this.post,
    required this.isDark,
    required this.onPostsChanged,
  });

  final WpPost post;
  final bool isDark;
  final VoidCallback onPostsChanged;

  @override
  Widget build(BuildContext context) {
    final bookmarkService = BookmarkService();
    final api = WpApiService();

    return Dismissible(
      key: ValueKey('saved_${post.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.delete_outline_rounded,
              color: Colors.redAccent,
              size: 24,
            ),
            SizedBox(height: 4),
            Text(
              '取消收藏',
              style: TextStyle(
                color: Colors.redAccent,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      confirmDismiss: (direction) async {
        await bookmarkService.toggleSave(
          post.id,
          sourceBaseUrl: post.sourceBaseUrl,
        );
        return true;
      },
      onDismissed: (_) {
        onPostsChanged();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已取消收藏：${post.title}'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            action: SnackBarAction(
              label: '撤销',
              onPressed: () async {
                await bookmarkService.toggleSave(
                  post.id,
                  sourceBaseUrl: post.sourceBaseUrl,
                  postData: post.toSummaryMap(),
                );
                onPostsChanged();
              },
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Material(
          color: isDark ? AppTheme.cardDark : AppTheme.cardLight,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            onTap: () => _openSavedPost(context, api),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                boxShadow: isDark ? null : AppTheme.softShadow,
              ),
              child: Row(
                children: [
                  _buildThumbnail(),
                  const SizedBox(width: 14),
                  _buildContent(context),
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(
                      Icons.bookmark_rounded,
                      color: AppTheme.primaryColor,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 打开收藏文章（如果内容为空则先从网络加载）
  Future<void> _openSavedPost(BuildContext context, WpApiService api) async {
    if (post.contentHtml.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('加载文章内容中...'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 1),
        ),
      );
      try {
        final freshPost = await api.fetchPostById(
          post.id,
          sourceBaseUrl: post.sourceBaseUrl,
        );
        if (freshPost != null && context.mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ArticleDetailScreen(post: freshPost),
            ),
          );
          onPostsChanged();
        }
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('无法加载文章，请检查网络连接'),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      }
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ArticleDetailScreen(post: post),
        ),
      );
      onPostsChanged();
    }
  }

  /// 左侧缩略图
  Widget _buildThumbnail() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: post.featuredImageUrl != null
          ? CachedNetworkImage(
              imageUrl: post.featuredImageUrl!,
              width: 80,
              height: 80,
              fit: BoxFit.cover,
              memCacheWidth: 160,
              memCacheHeight: 160,
              maxWidthDiskCache: 320,
              fadeInDuration: const Duration(milliseconds: 120),
              placeholder: (context, url) => Container(
                width: 80,
                height: 80,
                color: isDark
                    ? AppTheme.surfaceDark
                    : AppTheme.dividerColor,
              ),
              errorWidget: (context, url, error) => Container(
                width: 80,
                height: 80,
                color: AppTheme.primaryLight,
                child: const Icon(
                  Icons.image_outlined,
                  color: AppTheme.primaryColor,
                ),
              ),
            )
          : Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: AppTheme.heroGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  post.title.isNotEmpty ? post.title[0] : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
    );
  }

  /// 右侧内容区域
  Widget _buildContent(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (post.categories.isNotEmpty)
            Text(
              post.categories.first.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: AppTheme.primaryColor,
              ),
            ),
          if (post.categories.isNotEmpty)
            const SizedBox(height: 4),
          Text(
            post.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                post.author,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? AppTheme.darkModeSecondary
                      : AppTheme.lightText,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Container(
                  width: 3,
                  height: 3,
                  decoration: const BoxDecoration(
                    color: AppTheme.lightText,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Text(
                '${post.date.month}月${post.date.day}日',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? AppTheme.darkModeSecondary
                      : AppTheme.lightText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
