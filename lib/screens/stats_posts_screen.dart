import 'package:flutter/material.dart';

import '../models/wp_models.dart';
import '../theme/app_theme.dart';
import '../widgets/article_card.dart';

class StatsPostsScreen extends StatefulWidget {
  const StatsPostsScreen({
    super.key,
    required this.title,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.emptyIcon,
    required this.loadPosts,
    required this.onOpenPost,
  });

  final String title;
  final String emptyTitle;
  final String emptySubtitle;
  final IconData emptyIcon;
  final Future<List<WpPost>> Function() loadPosts;
  final Future<void> Function(WpPost post) onOpenPost;

  @override
  State<StatsPostsScreen> createState() => _StatsPostsScreenState();
}

class _StatsPostsScreenState extends State<StatsPostsScreen> {
  List<WpPost> _posts = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  Future<void> _loadPosts() async {
    setState(() => _loading = true);
    final posts = await widget.loadPosts();
    if (!mounted) {
      return;
    }
    setState(() {
      _posts = posts;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _posts.isEmpty
          ? _EmptyStatsView(
              isDark: isDark,
              title: widget.emptyTitle,
              subtitle: widget.emptySubtitle,
              icon: widget.emptyIcon,
            )
          : RefreshIndicator(
              onRefresh: _loadPosts,
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: _posts.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                      child: Text(
                        '共 ${_posts.length} 篇',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    );
                  }

                  final post = _posts[index - 1];
                  return ArticleCard(
                    post: post,
                    onTap: () async {
                      await widget.onOpenPost(post);
                      if (mounted) {
                        await _loadPosts();
                      }
                    },
                  );
                },
              ),
            ),
    );
  }
}

class _EmptyStatsView extends StatelessWidget {
  const _EmptyStatsView({
    required this.isDark,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final bool isDark;
  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
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
              child: Icon(icon, size: 56, color: AppTheme.primaryColor),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: isDark ? AppTheme.darkModeText : AppTheme.darkText,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.6,
                color: isDark ? AppTheme.darkModeSecondary : AppTheme.lightText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
