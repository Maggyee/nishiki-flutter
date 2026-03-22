import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class ArticleDetailActionBar extends StatelessWidget {
  const ArticleDetailActionBar({
    super.key,
    required this.isDark,
    required this.isLiked,
    required this.isSaved,
    required this.onLike,
    required this.onSave,
    required this.onShare,
  });

  final bool isDark;
  final bool isLiked;
  final bool isSaved;
  final VoidCallback onLike;
  final VoidCallback onSave;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 1,
          color: isDark ? AppTheme.surfaceDark : AppTheme.dividerColor,
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _BouncingActionButton(
              icon: isLiked
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              label: isLiked ? '已赞' : '点赞',
              isActive: isLiked,
              activeColor: const Color(0xFFFF4B6E),
              onTap: onLike,
              isDark: isDark,
            ),
            const SizedBox(width: 36),
            _BouncingActionButton(
              icon: isSaved
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_outline_rounded,
              label: isSaved ? '已收藏' : '收藏',
              isActive: isSaved,
              activeColor: AppTheme.primaryColor,
              onTap: onSave,
              isDark: isDark,
            ),
            const SizedBox(width: 36),
            _BouncingActionButton(
              icon: Icons.share_outlined,
              label: '分享',
              isActive: false,
              activeColor: AppTheme.primaryColor,
              onTap: onShare,
              isDark: isDark,
            ),
          ],
        ),
      ],
    );
  }
}

class _BouncingActionButton extends StatefulWidget {
  const _BouncingActionButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.activeColor,
    required this.onTap,
    required this.isDark,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final Color activeColor;
  final VoidCallback onTap;
  final bool isDark;

  @override
  State<_BouncingActionButton> createState() => _BouncingActionButtonState();
}

class _BouncingActionButtonState extends State<_BouncingActionButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _jumpController;
  late Animation<double> _jumpAnim;

  @override
  void initState() {
    super.initState();
    _jumpController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _jumpAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: -14.0).chain(
          CurveTween(curve: Curves.easeOutCubic),
        ),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: -14.0, end: 0.0).chain(
          CurveTween(curve: Curves.bounceOut),
        ),
        weight: 65,
      ),
    ]).animate(_jumpController);
  }

  @override
  void dispose() {
    _jumpController.dispose();
    super.dispose();
  }

  void _handleTap() {
    widget.onTap();
    _jumpController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.isActive;
    final activeColor = widget.activeColor;
    final isDark = widget.isDark;

    final buttonContent = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isActive
                ? activeColor.withValues(alpha: 0.15)
                : (isDark ? AppTheme.surfaceDark : AppTheme.primaryLight),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isActive
                  ? activeColor.withValues(alpha: 0.5)
                  : Colors.transparent,
              width: 1.5,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: activeColor.withValues(alpha: 0.3),
                      blurRadius: 12,
                      spreadRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: AnimatedScale(
            scale: isActive ? 1.05 : 1.0,
            duration: const Duration(milliseconds: 400),
            curve: Curves.elasticOut,
            child: Icon(
              widget.icon,
              size: 24,
              color: isActive ? activeColor : AppTheme.primaryColor,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
            color: isActive ? activeColor : AppTheme.lightText,
          ),
        ),
      ],
    );

    return AnimatedBuilder(
      animation: _jumpAnim,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _jumpAnim.value),
          child: child,
        );
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
          onTap: _handleTap,
          child: buttonContent,
        ),
      ),
    );
  }
}
