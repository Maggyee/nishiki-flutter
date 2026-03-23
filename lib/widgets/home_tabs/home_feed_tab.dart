import 'package:flutter/material.dart';

import '../../models/wp_models.dart';
import '../../screens/article_detail_screen.dart';
import '../../services/wp_api_service.dart';
import '../../theme/app_theme.dart';
import '../article_card.dart';

/// 首页 Tab — 今日精选 + 热门推荐
class HomeFeedTab extends StatelessWidget {
  const HomeFeedTab({
    super.key,
    required this.posts,
    required this.loading,
    required this.error,
    required this.apiError,
    required this.scopeLabel,
    required this.isAggregateMode,
    required this.onRefresh,
    required this.onOpenPost,
    required this.onManageSources,
    required this.onBuildFeed,
  });

  // 文章数据
  final List<WpPost> posts;
  // 加载状态
  final bool loading;
  // 错误信息
  final String? error;
  // API 错误详情
  final WpApiException? apiError;
  // 当前数据源范围标签
  final String scopeLabel;
  // 是否为聚合模式
  final bool isAggregateMode;
  // 下拉刷新回调
  final Future<void> Function() onRefresh;
  // 打开文章详情回调
  final Future<void> Function(WpPost post) onOpenPost;
  // 打开站点管理回调
  final VoidCallback onManageSources;
  // 构建文章列表的代理方法（因为 Feed 在多个 Tab 中共用逻辑）
  final Widget Function({required String sectionTitle, bool skipFirst}) onBuildFeed;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          // 标题区域
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text('今日精选', style: Theme.of(context).textTheme.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '来自你 WordPress 站点的最新文章',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          // 数据源 Chip
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: Icon(
                    isAggregateMode
                        ? Icons.hub_rounded
                        : Icons.language_rounded,
                    size: 18,
                  ),
                  label: Text(scopeLabel),
                  onDeleted: onManageSources,
                  deleteIcon: const Icon(Icons.tune_rounded, size: 18),
                ),
              ],
            ),
          ),
          // Hero 精选卡片
          _buildHomeHero(context),
          // 热门推荐列表
          onBuildFeed(sectionTitle: '热门推荐', skipFirst: true),
        ],
      ),
    );
  }

  /// 精选推荐 Hero 卡片
  Widget _buildHomeHero(BuildContext context) {
    if (loading) {
      return _buildHeroSkeleton(context);
    }
    if (error != null || posts.isEmpty) {
      return const SizedBox.shrink();
    }

    final featured = posts.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Text(
            '精选推荐',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        HeroArticleCard(
          post: featured,
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ArticleDetailScreen(post: featured),
              ),
            );
          },
        ),
      ],
    );
  }

  /// Hero 骨架屏加载占位
  Widget _buildHeroSkeleton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        height: 220,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          color: Theme.of(context).brightness == Brightness.dark
              ? AppTheme.cardDark
              : Colors.white,
          border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}
