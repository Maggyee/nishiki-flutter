import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/wp_models.dart';
import '../theme/app_theme.dart';

class HeroArticleCard extends StatelessWidget {
  const HeroArticleCard({super.key, required this.post, required this.onTap});

  final WpPost post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          height: 276,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: AppTheme.elevatedShadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (post.featuredImageUrl != null)
                  CachedNetworkImage(
                    imageUrl: post.featuredImageUrl!,
                    fit: BoxFit.cover,
                  )
                else
                  Container(
                    decoration: const BoxDecoration(
                      gradient: AppTheme.heroGradient,
                    ),
                  ),
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x22000000), Color(0xD9000000)],
                      stops: [0.15, 1.0],
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  top: 18,
                  child: Row(
                    children: [
                      if (post.categories.isNotEmpty)
                        _MetaPill(
                          label: post.categories.first,
                          foreground: Colors.white,
                          background: Colors.white.withValues(alpha: 0.16),
                        ),
                      const Spacer(),
                      _MetaPill(
                        label: '${post.readMinutes} 分钟',
                        foreground: Colors.white,
                        background: Colors.black.withValues(alpha: 0.24),
                        icon: Icons.schedule_rounded,
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                            ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        post.excerpt.isEmpty ? '继续阅读这篇文章' : post.excerpt,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.82),
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _MetaPill(
                            label: _sourceLabel(post.sourceBaseUrl),
                            foreground: Colors.white,
                            background: Colors.black.withValues(alpha: 0.24),
                            icon: Icons.language_rounded,
                          ),
                          _MetaPill(
                            label: post.author,
                            foreground: Colors.white,
                            background: Colors.white.withValues(alpha: 0.14),
                            icon: Icons.person_rounded,
                          ),
                          _MetaPill(
                            label: _formatDate(post.date),
                            foreground: Colors.white,
                            background: Colors.white.withValues(alpha: 0.14),
                            icon: Icons.calendar_today_rounded,
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

class ArticleCard extends StatelessWidget {
  const ArticleCard({
    super.key,
    required this.post,
    required this.onTap,
    this.highlightKeyword,
  });

  final WpPost post;
  final VoidCallback onTap;
  final String? highlightKeyword;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final showImage =
        post.featuredImageUrl != null && post.featuredImageUrl!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: isDark ? AppTheme.cardDark : AppTheme.cardLight,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? const Color(0xFF2B3442) : AppTheme.dividerColor,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (post.categories.isNotEmpty)
                              _MetaTag(label: post.categories.first),
                            _CompactMeta(
                              icon: Icons.schedule_rounded,
                              label: '${post.readMinutes} 分钟',
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _HighlightedText(
                          text: post.title,
                          keyword: highlightKeyword,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                height: 1.3,
                              ),
                        ),
                        const SizedBox(height: 8),
                        _HighlightedText(
                          text: post.excerpt.isEmpty
                              ? '暂无摘要，点击查看全文。'
                              : post.excerpt,
                          keyword: highlightKeyword,
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(height: 1.55),
                          maxLines: 3,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            _CompactMeta(
                              icon: Icons.language_rounded,
                              label: _sourceLabel(post.sourceBaseUrl),
                            ),
                            _CompactMeta(
                              icon: Icons.person_outline_rounded,
                              label: post.author,
                            ),
                            _CompactMeta(
                              icon: Icons.calendar_today_outlined,
                              label: _formatDate(post.date),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  _ArticlePreview(
                    imageUrl: post.featuredImageUrl,
                    title: post.title,
                    isDark: isDark,
                    visible: showImage,
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

class _ArticlePreview extends StatelessWidget {
  const _ArticlePreview({
    required this.imageUrl,
    required this.title,
    required this.isDark,
    required this.visible,
  });

  final String? imageUrl;
  final String title;
  final bool isDark;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final preview = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: visible
          ? CachedNetworkImage(
              imageUrl: imageUrl!,
              width: 104,
              height: 112,
              fit: BoxFit.cover,
            )
          : Container(
              width: 104,
              height: 112,
              decoration: BoxDecoration(
                gradient: AppTheme.heroGradient,
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.bottomLeft,
              padding: const EdgeInsets.all(12),
              child: Icon(
                Icons.auto_stories_rounded,
                color: Colors.white.withValues(alpha: 0.92),
              ),
            ),
    );

    return AnimatedOpacity(
      opacity: 1,
      duration: const Duration(milliseconds: 160),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: isDark ? null : AppTheme.softShadow,
        ),
        child: preview,
      ),
    );
  }
}

String _sourceLabel(String sourceBaseUrl) {
  final host = Uri.tryParse(sourceBaseUrl)?.host;
  if (host != null && host.isNotEmpty) {
    return host.replaceFirst('www.', '');
  }
  return sourceBaseUrl.replaceFirst('https://', '').replaceFirst('http://', '');
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.label,
    required this.foreground,
    required this.background,
    this.icon,
  });

  final String label;
  final Color foreground;
  final Color background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaTag extends StatelessWidget {
  const _MetaTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.primaryLight,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: AppTheme.primaryDark,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CompactMeta extends StatelessWidget {
  const _CompactMeta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: Theme.of(context).textTheme.bodySmall?.color,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _HighlightedText extends StatelessWidget {
  const _HighlightedText({
    required this.text,
    required this.keyword,
    required this.style,
    this.maxLines = 2,
  });

  final String text;
  final String? keyword;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final term = keyword?.trim();
    if (term == null || term.isEmpty) {
      return Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    final lowerText = text.toLowerCase();
    final lowerTerm = term.toLowerCase();
    final matchIndex = lowerText.indexOf(lowerTerm);
    if (matchIndex < 0) {
      return Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    final endIndex = matchIndex + term.length;
    return RichText(
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: style,
        children: [
          TextSpan(text: text.substring(0, matchIndex)),
          TextSpan(
            text: text.substring(matchIndex, endIndex),
            style: style?.copyWith(
              color: AppTheme.primaryColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          TextSpan(text: text.substring(endIndex)),
        ],
      ),
    );
  }
}

String _formatDate(DateTime date) => '${date.month}月${date.day}日';
