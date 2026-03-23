import 'package:flutter/material.dart';

/// AI 思考中旋转动画组件 — 渐变旋转的 AI 图标
class AiThinkingAnimation extends StatefulWidget {
  const AiThinkingAnimation({super.key, required this.isDark});

  /// 是否为深色模式
  final bool isDark;

  @override
  State<AiThinkingAnimation> createState() => _AiThinkingAnimationState();
}

class _AiThinkingAnimationState extends State<AiThinkingAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(); // 无限旋转
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.rotate(
          angle: _controller.value * 6.28318, // 2π 完整旋转
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF6C63FF).withValues(alpha: 0.2),
                  const Color(0xFF4ECDC4).withValues(alpha: 0.2),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
              child: Icon(
                Icons.auto_awesome,
                size: 28,
                color: Color(0xFF6C63FF),
              ),
            ),
          ),
        );
      },
    );
  }
}
