import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/blog_source_service.dart';
import '../../services/bookmark_service.dart';
import '../../services/settings_service.dart';
import '../../theme/app_theme.dart';

/// Profile Tab 中的对话框合集
/// 包含：打开博客、清缓存、重置数据、关于应用
class ProfileDialogs {
  ProfileDialogs._(); // 私有构造，仅提供静态方法

  /// 打开博客网站
  static Future<void> launchBlogUrl(
    BuildContext context,
    BlogSourceService blogSource,
  ) async {
    HapticFeedback.lightImpact();
    final url = Uri.parse(blogSource.currentSource);
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('无法打开浏览器'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  /// 清除缓存对话框
  static void showClearCacheDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除缓存？'),
        content: const Text('将清除文章缓存和图片缓存。你的收藏和点赞数据不会受到影响。'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('✅ 缓存已清除'),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            },
            child: const Text('清除'),
          ),
        ],
      ),
    );
  }

  /// 重置全部数据对话框
  static void showResetDialog(
    BuildContext context,
    SettingsService settings,
    BookmarkService bookmarkService,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('⚠️ 重置所有数据？'),
        content: const Text('这将清除你的所有收藏、点赞、阅读记录和设置。\n\n此操作不可逆！'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await settings.clearAllData();
              await bookmarkService.init();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('✅ 所有数据已重置'),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('确认重置'),
          ),
        ],
      ),
    );
  }

  /// 关于应用对话框
  static void showAboutAppDialog(BuildContext context, bool isDark) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            // 应用图标
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: AppTheme.heroGradient,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryColor.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Center(
                child: Text(
                  'N',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Nishiki Blog',
              style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'v1.0.0',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? AppTheme.darkModeSecondary : AppTheme.lightText,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '一个精致的 WordPress 博客阅读器，\n使用 Flutter 构建。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: isDark
                    ? AppTheme.darkModeSecondary
                    : AppTheme.mediumText,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                _buildTechChip('Flutter', isDark),
                _buildTechChip('WordPress API', isDark),
                _buildTechChip('Material 3', isDark),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
        actions: [
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
          ),
        ],
      ),
    );
  }

  /// 技术栈标签
  static Widget _buildTechChip(String label, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? AppTheme.primaryColor.withValues(alpha: 0.12)
            : AppTheme.primaryLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppTheme.primaryColor,
        ),
      ),
    );
  }
}
