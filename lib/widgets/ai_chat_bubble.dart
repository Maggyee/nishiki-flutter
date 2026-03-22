import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/ai_models.dart';
import '../theme/app_theme.dart';
import 'ai_markdown_text.dart';

class AiChatBubble extends StatelessWidget {
  const AiChatBubble({
    super.key,
    required this.message,
  });

  final AiMessage message;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUser = message.role == AiMessageRole.user;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            _buildAiAvatar(isDark),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  constraints: const BoxConstraints(maxWidth: 520),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: _bubbleColor(isUser, isDark),
                    borderRadius: _bubbleBorderRadius(isUser),
                    boxShadow: isUser && !message.isError
                        ? [
                            BoxShadow(
                              color: AppTheme.primaryColor.withValues(alpha: 0.06),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: message.isError
                      ? _buildErrorContent(isDark)
                      : _buildTextContent(isUser, isDark),
                ),
                if (message.isStreaming && message.content.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: _TypingIndicator(isDark: isDark),
                  ),
              ],
            ),
          ),
          if (isUser) const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildAiAvatar(bool isDark) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6C63FF), Color(0xFF4ECDC4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Center(
        child: Icon(
          Icons.auto_awesome,
          color: Colors.white,
          size: 16,
        ),
      ),
    );
  }

  Color _bubbleColor(bool isUser, bool isDark) {
    if (message.isError) {
      return isDark
          ? const Color(0xFF3D1F1F)
          : const Color(0xFFFFF0F0);
    }
    if (isUser) {
      return isDark
          ? AppTheme.primaryColor.withValues(alpha: 0.22)
          : AppTheme.primaryLight.withValues(alpha: 0.9);
    }
    return isDark ? AppTheme.cardDark : const Color(0xFFF6F8FB);
  }

  BorderRadius _bubbleBorderRadius(bool isUser) {
    return BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isUser ? 18 : 8),
      bottomRight: Radius.circular(isUser ? 8 : 18),
    );
  }

  Widget _buildTextContent(bool isUser, bool isDark) {
    return AiMarkdownText(
      message.content,
      isDark: isDark,
      baseStyle: TextStyle(
        fontSize: 14,
        height: 1.6,
        color: isDark ? AppTheme.darkModeText : AppTheme.darkText,
      ),
    );
  }

  Widget _buildErrorContent(bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.error_outline_rounded,
          size: 16,
          color: isDark ? const Color(0xFFFF6B6B) : const Color(0xFFE53E3E),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            message.content,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: isDark ? const Color(0xFFFF6B6B) : const Color(0xFFE53E3E),
            ),
          ),
        ),
      ],
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator({required this.isDark});

  final bool isDark;

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with TickerProviderStateMixin {
  late final List<AnimationController> _dotControllers;
  late final List<Animation<double>> _dotAnims;

  @override
  void initState() {
    super.initState();
    _dotControllers = List.generate(3, (i) {
      return AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      );
    });

    _dotAnims = _dotControllers.map((ctrl) {
      return Tween<double>(begin: 0, end: -6).animate(
        CurvedAnimation(parent: ctrl, curve: Curves.easeInOut),
      );
    }).toList();

    for (int i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 150), () {
        if (mounted) {
          _dotControllers[i].repeat(reverse: true);
        }
      });
    }
  }

  @override
  void dispose() {
    for (final ctrl in _dotControllers) {
      ctrl.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: widget.isDark ? AppTheme.cardDark : const Color(0xFFF6F8FB),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          return AnimatedBuilder(
            animation: _dotAnims[i],
            builder: (context, _) {
              return Transform.translate(
                offset: Offset(0, _dotAnims[i].value),
                child: Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.symmetric(horizontal: 2.5),
                  decoration: BoxDecoration(
                    color: widget.isDark
                        ? AppTheme.darkModeSecondary
                        : AppTheme.lightText,
                    shape: BoxShape.circle,
                  ),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}

class AiQuickAction extends StatelessWidget {
  const AiQuickAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isDark
                ? AppTheme.cardDark.withValues(alpha: 0.46)
                : const Color(0xFFF8FAFD),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: AppTheme.primaryColor.withValues(alpha: 0.92),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: isDark ? AppTheme.darkModeText : AppTheme.darkText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
