import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/wp_models.dart';
import '../../services/auth_service.dart';
import '../../services/blog_source_service.dart';
import '../../services/bookmark_service.dart';
import '../../services/settings_service.dart';
import '../../services/sync_service.dart';
import '../../theme/app_theme.dart';
import '../common/settings_tile.dart';
import 'login_sheet.dart';
import 'profile_dialogs.dart';

/// Profile Tab — 用户信息 + 阅读统计 + 设置 + 关于
class ProfileTab extends StatelessWidget {
  const ProfileTab({
    super.key,
    required this.avatarPulseAnim,
    required this.profileEnterCtrl,
    required this.onOpenStatPostsScreen,
    required this.onShowSourceManager,
    this.onLoginStateChanged,
  });

  // 头像呼吸脉冲动画
  final Animation<double> avatarPulseAnim;
  // Profile 入场动画控制器
  final AnimationController profileEnterCtrl;
  // 打开统计文章列表页面的回调
  final Future<void> Function({
    required String title,
    required String emptyTitle,
    required String emptySubtitle,
    required IconData emptyIcon,
    required Future<List<WpPost>> Function() loadPosts,
  }) onOpenStatPostsScreen;
  // 打开站点管理的回调
  final VoidCallback onShowSourceManager;
  // 登录状态变更回调（登录/登出后通知父组件刷新）
  final VoidCallback? onLoginStateChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final authService = AuthService();
    final bookmarkService = BookmarkService();
    final settings = SettingsService();
    final blogSource = BlogSourceService();
    final isSignedIn = authService.isSignedIn;

    final likedCount = bookmarkService.likedCount;
    final savedCount = bookmarkService.savedCount;
    final readCount = settings.readCount;
    final sourceHost = blogSource.currentScopeLabel;
    final fontScalePercent = (settings.fontScale.value * 100).round();

    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        // ===== 顶部渐变 Header 区域（带入场动画） =====
        _buildAnimatedEntry(
          delay: 0.0,
          child: _buildHeaderCard(context, isDark, sourceHost, fontScalePercent, settings, isSignedIn),
        ),

        // ===== 阅读统计卡片 =====
        _buildAnimatedEntry(
          delay: 0.1,
          child: _buildStatsCard(context, isDark, readCount, savedCount, likedCount, settings, bookmarkService),
        ),

        const SizedBox(height: 12),

        // ===== 阅读偏好设置标题 =====
        _buildAnimatedEntry(
          delay: 0.2,
          slideOffset: const Offset(-0.1, 0),
          child: _buildSectionTitle(isDark, '阅读偏好'),
        ),

        // ===== 阅读偏好设置项 =====
        _buildAnimatedEntry(
          delay: 0.25,
          child: SettingsCard(
            tiles: [
              SettingsTileData(
                icon: Icons.hub_rounded,
                iconColor: const Color(0xFF6366F1),
                title: '站点与组合',
                subtitle: blogSource.currentScopeLabel,
                onTap: () {
                  HapticFeedback.lightImpact();
                  onShowSourceManager();
                },
              ),
              SettingsTileData(
                icon: settings.themeModeIcon,
                iconColor: const Color(0xFF8B5CF6),
                title: '外观模式',
                subtitle: settings.themeModeName,
                trailing: _buildThemeModeChip(context, isDark, settings),
              ),
              SettingsTileData(
                icon: Icons.text_fields_rounded,
                iconColor: const Color(0xFF3B82F6),
                title: '阅读字体',
                subtitle: settings.fontScaleName,
                trailing: _buildFontScaleSlider(context, isDark, settings),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ===== 账号与同步标题 =====
        _buildAnimatedEntry(
          delay: 0.3,
          slideOffset: const Offset(-0.1, 0),
          child: _buildSectionTitle(isDark, '账号与同步'),
        ),

        // ===== 账号与同步设置项 =====
        _buildAnimatedEntry(
          delay: 0.33,
          child: SettingsCard(
            tiles: [
              if (!isSignedIn)
                SettingsTileData(
                  icon: Icons.login_rounded,
                  iconColor: const Color(0xFF10B981),
                  title: '登录 / 注册',
                  subtitle: '登录后多端同步收藏和阅读记录',
                  onTap: () async {
                    HapticFeedback.lightImpact();
                    final success = await LoginSheet.show(context);
                    if (success) {
                      onLoginStateChanged?.call();
                    }
                  },
                ),
              if (isSignedIn) ...[
                SettingsTileData(
                  icon: Icons.cloud_done_rounded,
                  iconColor: const Color(0xFF10B981),
                  title: '同步状态',
                  subtitle: '已登录：${authService.currentUser?.email ?? ""}',
                ),
                SettingsTileData(
                  icon: Icons.sync_rounded,
                  iconColor: const Color(0xFF3B82F6),
                  title: '立即同步',
                  subtitle: '手动同步所有数据',
                  onTap: () async {
                    HapticFeedback.lightImpact();
                    try {
                      await SyncService().reconcileLocalState();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('✅ 同步完成'),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('同步失败：$e'),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        );
                      }
                    }
                    onLoginStateChanged?.call();
                  },
                ),
                SettingsTileData(
                  icon: Icons.logout_rounded,
                  iconColor: const Color(0xFFEF4444),
                  title: '退出登录',
                  subtitle: '退出后数据仅保存在本地',
                  onTap: () async {
                    HapticFeedback.heavyImpact();
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('确认退出登录？'),
                        content: const Text('退出后数据将不再多端同步，但本地数据不会丢失。'),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                            ),
                            child: const Text('退出登录'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      try {
                        await SyncService().disposeRealtime();
                        await authService.logout();
                      } catch (_) {
                        await authService.clearSession();
                      }
                      onLoginStateChanged?.call();
                    }
                  },
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ===== 功能区标题 =====
        _buildAnimatedEntry(
          delay: 0.4,
          slideOffset: const Offset(-0.1, 0),
          child: _buildSectionTitle(isDark, '功能'),
        ),

        // ===== 功能设置项 =====
        _buildAnimatedEntry(
          delay: 0.45,
          child: SettingsCard(
            tiles: [
              SettingsTileData(
                icon: Icons.language_rounded,
                iconColor: const Color(0xFF10B981),
                title: '访问博客网站',
                subtitle: blogSource.currentScopeLabel,
                onTap: () => ProfileDialogs.launchBlogUrl(context, blogSource),
              ),
              SettingsTileData(
                icon: Icons.cleaning_services_rounded,
                iconColor: const Color(0xFFF59E0B),
                title: '清除缓存',
                subtitle: '清除文章缓存和图片缓存',
                onTap: () {
                  HapticFeedback.lightImpact();
                  ProfileDialogs.showClearCacheDialog(context);
                },
              ),
              SettingsTileData(
                icon: Icons.restart_alt_rounded,
                iconColor: const Color(0xFFEF4444),
                title: '重置所有数据',
                subtitle: '清除收藏、点赞和设置',
                onTap: () {
                  HapticFeedback.heavyImpact();
                  ProfileDialogs.showResetDialog(context, settings, bookmarkService);
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ===== 关于区标题 =====
        _buildAnimatedEntry(
          delay: 0.55,
          slideOffset: const Offset(-0.1, 0),
          child: _buildSectionTitle(isDark, '关于'),
        ),

        // ===== 关于设置项 =====
        _buildAnimatedEntry(
          delay: 0.6,
          child: SettingsCard(
            tiles: [
              SettingsTileData(
                icon: Icons.info_outline_rounded,
                iconColor: const Color(0xFF6366F1),
                title: '关于 Nishiki Blog',
                subtitle: 'v1.0.0 · Flutter 构建',
                onTap: () {
                  HapticFeedback.lightImpact();
                  ProfileDialogs.showAboutAppDialog(context, isDark);
                },
              ),
            ],
          ),
        ),

        // 底部版本标注
        _buildAnimatedEntry(
          delay: 0.7,
          child: Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Center(
              child: Text(
                'Nishiki 用 💙 制作',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? AppTheme.darkModeSecondary.withValues(alpha: 0.6)
                      : AppTheme.lightText.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ==================== 子区域构建 ====================

  /// 顶部渐变 Header 卡片（头像 + 名称 + 徽章）
  Widget _buildHeaderCard(
    BuildContext context,
    bool isDark,
    String sourceHost,
    int fontScalePercent,
    SettingsService settings,
    bool isSignedIn,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // 头像（带呼吸脉冲动画）
          AnimatedBuilder(
            animation: avatarPulseAnim,
            builder: (context, child) {
              return Transform.scale(
                scale: avatarPulseAnim.value,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.2),
                    border: Border.all(
                      color: Colors.white.withValues(
                        alpha:
                            0.3 +
                            0.2 * (avatarPulseAnim.value - 1.0) / 0.08,
                      ),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withValues(
                          alpha:
                              0.1 +
                              0.15 *
                                  (avatarPulseAnim.value - 1.0) /
                                  0.08,
                        ),
                        blurRadius: 16 * avatarPulseAnim.value,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/site_avatar.webp',
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Center(
                          child: Icon(
                            Icons.person_rounded,
                            size: 36,
                            color: Colors.white,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          Text(
            isSignedIn
                ? (AuthService().currentUser?.email ?? '阅读者')
                : '阅读者',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isSignedIn ? '☁️ 数据已云端同步' : sourceHost,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isSignedIn
                ? '你的收藏、阅读记录和设置正在多设备间自动同步。'
                : '登录后，收藏、阅读记录可在多设备间同步。',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 12,
              height: 1.45,
            ),
          ),
          // 未登录时显示快捷登录按钮
          if (!isSignedIn) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 34,
              child: FilledButton.icon(
                onPressed: () async {
                  HapticFeedback.lightImpact();
                  final success = await LoginSheet.show(context);
                  if (success) {
                    onLoginStateChanged?.call();
                  }
                },
                icon: const Icon(Icons.login_rounded, size: 16),
                label: const Text('登录 / 注册', style: TextStyle(fontSize: 13)),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
              ),
            ),
          ],
          if (isSignedIn) const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (isSignedIn)
                _buildProfileBadge(icon: Icons.cloud_done_rounded, label: '已同步'),
              _buildProfileBadge(icon: settings.themeModeIcon, label: settings.themeModeName),
              _buildProfileBadge(icon: Icons.text_fields_rounded, label: '$fontScalePercent% 字号'),
              _buildProfileBadge(icon: Icons.language_rounded, label: sourceHost),
            ],
          ),
        ],
      ),
    );
  }

  /// 阅读统计卡片
  Widget _buildStatsCard(
    BuildContext context,
    bool isDark,
    int readCount,
    int savedCount,
    int likedCount,
    SettingsService settings,
    BookmarkService bookmarkService,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.cardDark : AppTheme.cardLight,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          boxShadow: isDark ? null : AppTheme.softShadow,
        ),
        child: Row(
          children: [
            _buildAnimatedStatItem(
              context: context,
              icon: Icons.auto_stories_rounded,
              label: '已读',
              count: readCount,
              color: const Color(0xFF6FAEEB),
              isDark: isDark,
              onTap: () => onOpenStatPostsScreen(
                title: '已读文章',
                emptyTitle: '还没有已读记录',
                emptySubtitle: '打开文章后会自动记录到这里。',
                emptyIcon: Icons.auto_stories_rounded,
                loadPosts: () async {
                  await settings.init();
                  return settings.getReadPosts();
                },
              ),
            ),
            _buildDivider(isDark),
            _buildAnimatedStatItem(
              context: context,
              icon: Icons.bookmark_rounded,
              label: '收藏',
              count: savedCount,
              color: const Color(0xFFFFB347),
              isDark: isDark,
              onTap: () => onOpenStatPostsScreen(
                title: '收藏文章',
                emptyTitle: '还没有收藏文章',
                emptySubtitle: '在文章详情页点击收藏后，会显示在这里。',
                emptyIcon: Icons.bookmark_rounded,
                loadPosts: () async {
                  await bookmarkService.init();
                  final data = await bookmarkService.getSavedPostsData();
                  return data.map((d) => WpPost.fromSummaryMap(d)).toList();
                },
              ),
            ),
            _buildDivider(isDark),
            _buildAnimatedStatItem(
              context: context,
              icon: Icons.favorite_rounded,
              label: '点赞',
              count: likedCount,
              color: const Color(0xFFFF6B8A),
              isDark: isDark,
              onTap: () => onOpenStatPostsScreen(
                title: '点赞文章',
                emptyTitle: '还没有点赞文章',
                emptySubtitle: '在文章详情页点赞后，会显示在这里。',
                emptyIcon: Icons.favorite_rounded,
                loadPosts: () async {
                  await bookmarkService.init();
                  final data = await bookmarkService.getLikedPostsData();
                  return data.map((d) => WpPost.fromSummaryMap(d)).toList();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 辅助组件 ====================

  /// 统计项分隔线
  Widget _buildDivider(bool isDark) {
    return Container(
      width: 1,
      height: 40,
      color: isDark ? AppTheme.surfaceDark : AppTheme.dividerColor,
    );
  }

  /// 统计项（带计数动画）
  Widget _buildAnimatedStatItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    required int count,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: count.toDouble()),
        duration: const Duration(milliseconds: 1200),
        curve: Curves.easeOutCubic,
        builder: (context, animatedCount, child) {
          return InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 20, color: color),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${animatedCount.toInt()}',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: isDark ? AppTheme.darkModeText : AppTheme.darkText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? AppTheme.darkModeSecondary
                          : AppTheme.lightText,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Profile 区域标题
  Widget _buildSectionTitle(bool isDark, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: isDark ? AppTheme.darkModeSecondary : AppTheme.lightText,
        ),
      ),
    );
  }

  /// Profile 徽章
  Widget _buildProfileBadge({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// 通用入场动画包装器
  Widget _buildAnimatedEntry({
    required double delay,
    required Widget child,
    Offset slideOffset = const Offset(0, 0.05),
  }) {
    final begin = delay;
    final end = (delay + 0.4).clamp(0.0, 1.0);

    return AnimatedBuilder(
      animation: profileEnterCtrl,
      builder: (context, _) {
        final curvedValue = Curves.easeOutCubic.transform(
          ((profileEnterCtrl.value - begin) / (end - begin)).clamp(0.0, 1.0),
        );
        return Opacity(
          opacity: curvedValue,
          child: FractionalTranslation(
            translation: Offset(
              slideOffset.dx * (1 - curvedValue),
              slideOffset.dy * (1 - curvedValue),
            ),
            child: child,
          ),
        );
      },
    );
  }

  /// 主题模式切换 Chip
  Widget _buildThemeModeChip(BuildContext context, bool isDark, SettingsService settings) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: animation, child: child),
        );
      },
      child: Container(
        key: ValueKey(settings.themeModeName),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isDark
              ? AppTheme.primaryColor.withValues(alpha: 0.15)
              : AppTheme.primaryLight,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(settings.themeModeIcon, size: 14, color: AppTheme.primaryColor),
            const SizedBox(width: 4),
            Text(
              settings.themeModeName,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 字体大小滑块
  Widget _buildFontScaleSlider(BuildContext context, bool isDark, SettingsService settings) {
    return SizedBox(
      width: 130,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              fontSize: 11 * (settings.fontScale.value < 1.0 ? 1.1 : 0.9),
              fontWeight: FontWeight.w600,
              color: settings.fontScale.value <= 0.9
                  ? AppTheme.primaryColor
                  : (isDark ? AppTheme.darkModeText : AppTheme.darkText),
            ),
            child: const Text('A'),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                activeTrackColor: AppTheme.primaryColor,
                inactiveTrackColor: isDark
                    ? AppTheme.surfaceDark
                    : AppTheme.dividerColor,
                thumbColor: AppTheme.primaryColor,
                overlayColor: AppTheme.primaryColor.withValues(alpha: 0.1),
              ),
              child: Slider(
                value: settings.fontScale.value,
                min: 0.8,
                max: 1.4,
                divisions: 3,
                onChanged: (value) async {
                  final oldStep = (settings.fontScale.value * 5).round();
                  final newStep = (value * 5).round();
                  if (oldStep != newStep) {
                    HapticFeedback.selectionClick();
                  }
                  await settings.setFontScale(value);
                },
              ),
            ),
          ),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              fontSize: 16 * (settings.fontScale.value > 1.2 ? 1.1 : 0.9),
              fontWeight: FontWeight.w700,
              color: settings.fontScale.value >= 1.3
                  ? AppTheme.primaryColor
                  : (isDark ? AppTheme.darkModeText : AppTheme.darkText),
            ),
            child: const Text('A'),
          ),
        ],
      ),
    );
  }


}
