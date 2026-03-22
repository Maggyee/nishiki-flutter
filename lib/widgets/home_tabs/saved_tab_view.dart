import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../models/wp_models.dart';
import '../../theme/app_theme.dart';

class SavedTabView extends StatelessWidget {
  const SavedTabView({
    super.key,
    required this.isDark,
    required this.savedLoading,
    required this.savedPosts,
    required this.onRefresh,
    required this.onGoToDiscover,
    required this.onClearAll,
    required this.onRemovePost,
    required this.onUndoRemove,
    required this.onOpenPost,
    required this.formatDate,
  });

  final bool isDark;
  final bool savedLoading;
  final List<WpPost> savedPosts;
  final Future<void> Function() onRefresh;
  final VoidCallback onGoToDiscover;
  final VoidCallback onClearAll;
  final Future<void> Function(WpPost post) onRemovePost;
  final Future<void> Function(WpPost post) onUndoRemove;
  final Future<void> Function(WpPost post) onOpenPost;
  final String Function(DateTime date) formatDate;

  @override
  Widget build(BuildContext context) {
    if (savedLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (savedPosts.isEmpty) {
      return Center(
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
                  color:
                      isDark ? AppTheme.darkModeSecondary : AppTheme.lightText,
                ),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: onGoToDiscover,
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

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: savedPosts.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
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
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
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
                      onPressed: onClearAll,
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

          if (index == 1) {
            return const SizedBox(height: 8);
          }

          final post = savedPosts[index - 2];
          return _SavedPostCard(
            post: post,
            isDark: isDark,
            formatDate: formatDate,
            onOpenPost: onOpenPost,
            onRemovePost: onRemovePost,
            onUndoRemove: onUndoRemove,
          );
        },
      ),
    );
  }
}

class _SavedPostCard extends StatelessWidget {
  const _SavedPostCard({
    required this.post,
    required this.isDark,
    required this.formatDate,
    required this.onOpenPost,
    required this.onRemovePost,
    required this.onUndoRemove,
  });

  final WpPost post;
  final bool isDark;
  final String Function(DateTime date) formatDate;
  final Future<void> Function(WpPost post) onOpenPost;
  final Future<void> Function(WpPost post) onRemovePost;
  final Future<void> Function(WpPost post) onUndoRemove;

  @override
  Widget build(BuildContext context) {
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
            Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 24),
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
      confirmDismiss: (_) async {
        await onRemovePost(post);
        return true;
      },
      onDismissed: (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已取消收藏：${post.title}'),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            action: SnackBarAction(
              label: '撤销',
              onPressed: () async {
                await onUndoRemove(post);
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
            onTap: () => onOpenPost(post),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                boxShadow: isDark ? null : AppTheme.softShadow,
              ),
              child: Row(
                children: [
                  ClipRRect(
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
                            fadeInDuration:
                                const Duration(milliseconds: 120),
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
                  ),
                  const SizedBox(width: 14),
                  Expanded(
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
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
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
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
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
                              formatDate(post.date),
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
                  ),
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
}
