import 'package:flutter/material.dart';

/// ================================================================
/// 按压缩放反馈组件 — 按下时轻微缩小，松开后弹回
/// 提供类似 iOS 原生的触摸反馈体验
/// ================================================================
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const PressableScale({super.key, required this.child, this.onTap});

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale>
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
    // 按下缩小到 0.97，松开恢复 1.0
    _scaleAnim = Tween<double>(
      begin: 1.0,
      end: 0.97,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 如果没有 onTap，不添加手势交互
    if (widget.onTap == null) {
      return widget.child;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _ctrl.forward(), // 按下 → 缩小
      onTapUp: (_) {
        _ctrl.reverse(); // 松开 → 恢复
        widget.onTap?.call();
      },
      onTapCancel: () => _ctrl.reverse(), // 取消 → 恢复
      child: AnimatedBuilder(
        animation: _scaleAnim,
        builder: (context, child) {
          return Transform.scale(scale: _scaleAnim.value, child: child);
        },
        child: widget.child,
      ),
    );
  }
}
