import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'pressable_scale.dart';

/// 设置项数据模型
class SettingsTileData {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const SettingsTileData({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });
}

/// 设置卡片容器（包含多个设置项）
class SettingsCard extends StatelessWidget {
  const SettingsCard({
    super.key,
    required this.tiles,
  });

  final List<SettingsTileData> tiles;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppTheme.cardDark : AppTheme.cardLight,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : AppTheme.dividerStrong.withValues(alpha: 0.65),
          ),
          boxShadow: isDark ? null : AppTheme.softShadow,
        ),
        child: Column(
          children: [
            for (int i = 0; i < tiles.length; i++) ...[
              _buildSettingsTileWidget(tiles[i], isDark),
              if (i < tiles.length - 1)
                Padding(
                  padding: const EdgeInsets.only(left: 60),
                  child: Divider(
                    height: 1,
                    color: isDark
                        ? AppTheme.surfaceDark
                        : AppTheme.dividerColor,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// 渲染单个设置项 Widget（带按压缩放反馈）
  Widget _buildSettingsTileWidget(SettingsTileData tile, bool isDark) {
    return PressableScale(
      onTap: tile.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // 彩色图标容器
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: tile.iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(tile.icon, size: 20, color: tile.iconColor),
            ),
            const SizedBox(width: 14),
            // 标题和副标题
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tile.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppTheme.darkModeText : AppTheme.darkText,
                    ),
                  ),
                  if (tile.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      tile.subtitle!,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? AppTheme.darkModeSecondary
                            : AppTheme.lightText,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // 右侧内容（自定义 trailing 或默认箭头）
            if (tile.trailing != null)
              tile.trailing!
            else if (tile.onTap != null)
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: isDark ? AppTheme.darkModeSecondary : AppTheme.lightText,
              ),
          ],
        ),
      ),
    );
  }
}
