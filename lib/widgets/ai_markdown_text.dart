import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AiMarkdownText extends StatelessWidget {
  const AiMarkdownText(
    this.data, {
    super.key,
    required this.isDark,
    this.baseStyle,
  });

  final String data;
  final bool isDark;
  final TextStyle? baseStyle;

  @override
  Widget build(BuildContext context) {
    final defaultStyle = (baseStyle ??
            TextStyle(
              fontSize: 14,
              height: 1.6,
              color: isDark ? AppTheme.darkModeText : AppTheme.darkText,
            ))
        .copyWith(
      color: baseStyle?.color ??
          (isDark ? AppTheme.darkModeText : AppTheme.darkText),
    );

    final blocks = _parseBlocks(data);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          _buildBlock(blocks[i], defaultStyle),
          if (i != blocks.length - 1)
            SizedBox(
              height: blocks[i].type == _BlockType.heading ? 12 : 11,
            ),
        ],
      ],
    );
  }

  Widget _buildBlock(_MarkdownBlock block, TextStyle defaultStyle) {
    switch (block.type) {
      case _BlockType.heading:
        return Text.rich(
          TextSpan(
            children: _parseInline(
              block.text,
              defaultStyle.copyWith(
                fontSize: (defaultStyle.fontSize ?? 14) + 2,
                fontWeight: FontWeight.w700,
                height: 1.45,
                color: isDark ? AppTheme.darkModeText : AppTheme.darkText,
              ),
            ),
          ),
        );
      case _BlockType.bullet:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.58),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: _parseInline(
                    block.text,
                    defaultStyle.copyWith(height: 1.72),
                  ),
                ),
              ),
            ),
          ],
        );
      case _BlockType.paragraph:
        return Text.rich(
          TextSpan(
            children: _parseInline(
              block.text,
              defaultStyle.copyWith(height: 1.72),
            ),
          ),
        );
    }
  }

  List<_MarkdownBlock> _parseBlocks(String input) {
    final normalized = input.replaceAll('\r\n', '\n').trim();
    if (normalized.isEmpty) {
      return const [];
    }

    final lines = normalized.split('\n');
    final blocks = <_MarkdownBlock>[];
    final paragraphBuffer = <String>[];

    void flushParagraph() {
      if (paragraphBuffer.isEmpty) return;
      blocks.add(
        _MarkdownBlock(
          type: _BlockType.paragraph,
          text: paragraphBuffer.join('\n').trim(),
        ),
      );
      paragraphBuffer.clear();
    }

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        flushParagraph();
        continue;
      }

      if (line.startsWith('#')) {
        flushParagraph();
        blocks.add(
          _MarkdownBlock(
            type: _BlockType.heading,
            text: line.replaceFirst(RegExp(r'^#+\s*'), ''),
          ),
        );
        continue;
      }

      if (line.startsWith('- ') ||
          line.startsWith('* ') ||
          RegExp(r'^\d+\.\s+').hasMatch(line)) {
        flushParagraph();
        blocks.add(
          _MarkdownBlock(
            type: _BlockType.bullet,
            text: line
                .replaceFirst(RegExp(r'^[-*]\s+'), '')
                .replaceFirst(RegExp(r'^\d+\.\s+'), ''),
          ),
        );
        continue;
      }

      paragraphBuffer.add(line);
    }

    flushParagraph();
    return blocks;
  }

  List<InlineSpan> _parseInline(String input, TextStyle style) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*');
    var start = 0;

    for (final match in pattern.allMatches(input)) {
      if (match.start > start) {
        spans.add(
          TextSpan(
            text: _cleanInlineText(input.substring(start, match.start)),
            style: style,
          ),
        );
      }
      spans.add(
        TextSpan(
          text: _cleanInlineText(match.group(1) ?? ''),
          style: style.copyWith(
            fontWeight: FontWeight.w700,
            color: style.color?.withValues(alpha: 0.96),
          ),
        ),
      );
      start = match.end;
    }

    if (start < input.length) {
      spans.add(
        TextSpan(
          text: _cleanInlineText(input.substring(start)),
          style: style,
        ),
      );
    }

    if (spans.isEmpty) {
      spans.add(TextSpan(text: _cleanInlineText(input), style: style));
    }

    return spans;
  }

  String _cleanInlineText(String input) {
    return input.replaceAll('**', '').replaceAll('*', '').trimRight();
  }
}

enum _BlockType {
  paragraph,
  heading,
  bullet,
}

class _MarkdownBlock {
  const _MarkdownBlock({
    required this.type,
    required this.text,
  });

  final _BlockType type;
  final String text;
}
