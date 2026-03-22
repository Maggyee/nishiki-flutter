import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';

class ProfileAnimatedEntry extends StatelessWidget {
  const ProfileAnimatedEntry({
    super.key,
    required this.animation,
    required this.delay,
    required this.child,
    this.slideOffset = const Offset(0, 0.05),
  });

  final Animation<double> animation;
  final double delay;
  final Widget child;
  final Offset slideOffset;

  @override
  Widget build(BuildContext context) {
    final begin = delay;
    final end = (delay + 0.4).clamp(0.0, 1.0);

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final curvedValue = Curves.easeOutCubic.transform(
          ((animation.value - begin) / (end - begin)).clamp(0.0, 1.0),
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
}

class ProfileAnimatedStatItem extends StatelessWidget {
  const ProfileAnimatedStatItem({
    super.key,
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
    required this.isDark,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final int count;
  final Color color;
  final bool isDark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: _PressableScale(
        onTap: onTap,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: count.toDouble()),
          duration: const Duration(milliseconds: 1200),
          curve: Curves.easeOutCubic,
          builder: (context, animatedCount, child) {
            return Padding(
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
            );
          },
        ),
      ),
    );
  }
}

class ProfileSettingsTileData {
  const ProfileSettingsTileData({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
}

class ProfileSettingsCard extends StatelessWidget {
  const ProfileSettingsCard({
    super.key,
    required this.isDark,
    required this.tiles,
  });

  final bool isDark;
  final List<ProfileSettingsTileData> tiles;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppTheme.cardDark : AppTheme.cardLight,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          boxShadow: isDark ? null : AppTheme.softShadow,
        ),
        child: Column(
          children: [
            for (int i = 0; i < tiles.length; i++) ...[
              _SettingsTileWidget(tile: tiles[i], isDark: isDark),
              if (i < tiles.length - 1)
                Padding(
                  padding: const EdgeInsets.only(left: 60),
                  child: Divider(
                    height: 1,
                    color: isDark ? AppTheme.surfaceDark : AppTheme.dividerColor,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class ThemeModeChip extends StatelessWidget {
  const ThemeModeChip({
    super.key,
    required this.isDark,
    required this.icon,
    required this.label,
  });

  final bool isDark;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: animation, child: child),
        );
      },
      child: Container(
        key: ValueKey(label),
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
            Icon(icon, size: 14, color: AppTheme.primaryColor),
            const SizedBox(width: 4),
            Text(
              label,
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
}

class FontScaleSlider extends StatelessWidget {
  const FontScaleSlider({
    super.key,
    required this.isDark,
    required this.fontScale,
    required this.onChanged,
  });

  final bool isDark;
  final double fontScale;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 130,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              fontSize: 11 * (fontScale < 1.0 ? 1.1 : 0.9),
              fontWeight: FontWeight.w600,
              color: fontScale <= 0.9
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
                value: fontScale,
                min: 0.8,
                max: 1.4,
                divisions: 3,
                onChanged: (value) {
                  final oldStep = (fontScale * 5).round();
                  final newStep = (value * 5).round();
                  if (oldStep != newStep) {
                    HapticFeedback.selectionClick();
                  }
                  onChanged(value);
                },
              ),
            ),
          ),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              fontSize: 16 * (fontScale > 1.2 ? 1.1 : 0.9),
              fontWeight: FontWeight.w700,
              color: fontScale >= 1.3
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

class TechChip extends StatelessWidget {
  const TechChip({
    super.key,
    required this.label,
    required this.isDark,
  });

  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
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

class _SettingsTileWidget extends StatelessWidget {
  const _SettingsTileWidget({
    required this.tile,
    required this.isDark,
  });

  final ProfileSettingsTileData tile;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return _PressableScale(
      onTap: tile.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: tile.iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(tile.icon, size: 20, color: tile.iconColor),
            ),
            const SizedBox(width: 14),
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

class _PressableScale extends StatefulWidget {
  const _PressableScale({
    required this.child,
    this.onTap,
  });

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<_PressableScale>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) {
      return widget.child;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: AnimatedBuilder(
        animation: _scaleAnim,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnim.value,
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}
