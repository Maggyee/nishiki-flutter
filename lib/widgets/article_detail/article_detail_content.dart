import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:html/dom.dart' as html;

import '../../models/wp_models.dart';
import '../../theme/app_theme.dart';
import 'article_detail_app_bar.dart';

class ArticleDetailContent extends StatelessWidget {
  const ArticleDetailContent({
    super.key,
    required this.post,
    required this.hasImage,
    required this.isDark,
    required this.fontScale,
    required this.onOpenInBrowser,
    required this.bottomActions,
  });

  final WpPost post;
  final bool hasImage;
  final bool isDark;
  final double fontScale;
  final Future<void> Function(String url) onOpenInBrowser;
  final Widget bottomActions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      transform: hasImage ? Matrix4.translationValues(0, -24, 0) : null,
      decoration: hasImage
          ? BoxDecoration(
              color: isDark ? AppTheme.scaffoldDark : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppTheme.radiusXl),
              ),
            )
          : null,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, hasImage ? 28 : 20, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!hasImage && post.categories.isNotEmpty) ...[
                  ArticleDetailCategoryChips(
                    categories: post.categories,
                    onDark: false,
                  ),
                  const SizedBox(height: 16),
                ],
                if (hasImage && post.categories.isNotEmpty)
                  const SizedBox(height: 4),
                Text(
                  post.title,
                  style: theme.textTheme.headlineLarge?.copyWith(
                    fontSize: 26 * fontScale,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                    letterSpacing: -0.5,
                    color: isDark ? AppTheme.darkModeText : AppTheme.darkText,
                  ),
                ),
                const SizedBox(height: 18),
                ArticleDetailMetaPanel(
                  post: post,
                  isDark: isDark,
                  onOpenInBrowser: onOpenInBrowser,
                ),
                const SizedBox(height: 24),
                Container(
                  height: 1,
                  color: isDark ? AppTheme.surfaceDark : AppTheme.dividerColor,
                ),
                const SizedBox(height: 24),
                SelectionArea(
                  child: Html(
                    data: post.contentHtml,
                    style: _buildHtmlStyles(isDark, fontScale),
                    extensions: [
                      ImageExtension(
                        builder: (context) => _HtmlNetworkImage(
                          src: context.attributes['src'] ?? '',
                          alt: context.attributes['alt'] ?? '',
                          width:
                              context.style?.width?.value ??
                              _tryParseDimension(context.attributes['width']),
                          height:
                              context.style?.height?.value ??
                              _tryParseDimension(context.attributes['height']),
                          isDark: isDark,
                        ),
                      ),
                      TagExtension(
                        tagsToExtend: {'pre'},
                        builder: (context) => _HtmlCodeBlock(
                          code: _extractCodeBlockText(context.element),
                          isDark: isDark,
                          fontScale: fontScale,
                        ),
                      ),
                      TagExtension(
                        tagsToExtend: {'table'},
                        builder: (context) => _HtmlTableWidget(
                          element: context.element,
                          isDark: isDark,
                          fontScale: fontScale,
                        ),
                      ),
                      TagWrapExtension(
                        tagsToWrap: {'table'},
                        builder: (child) {
                          return child;
                        },
                      ),
                    ],
                    onLinkTap: (url, _, _) {
                      if (url == null || url.isEmpty) return;
                      HapticFeedback.selectionClick();
                      onOpenInBrowser(url);
                    },
                  ),
                ),
                const SizedBox(height: 40),
                bottomActions,
                const SizedBox(height: 16),
                if (post.link.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton.icon(
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        onOpenInBrowser(post.link);
                      },
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text('在浏览器中查看原文'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.primaryColor,
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HtmlTableWidget extends StatelessWidget {
  const _HtmlTableWidget({
    required this.element,
    required this.isDark,
    required this.fontScale,
  });

  final html.Element? element;
  final bool isDark;
  final double fontScale;

  @override
  Widget build(BuildContext context) {
    final rows = _extractRows(element);
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 640;
    final horizontalPadding = isCompact ? 14.0 : 20.0;
    final verticalPadding = isCompact ? 12.0 : 18.0;
    final borderColor = isDark ? AppTheme.surfaceDark : AppTheme.dividerColor;
    final headerBackground = isDark ? AppTheme.cardDark : AppTheme.primaryLight;
    final rowBackground = isDark ? AppTheme.surfaceDark : Colors.white;

    return Container(
      margin: const EdgeInsets.only(top: 16, bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        boxShadow: isDark ? null : AppTheme.softShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: IntrinsicWidth(
            child: Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              defaultColumnWidth: const IntrinsicColumnWidth(),
              children: List.generate(rows.length, (rowIndex) {
                final row = rows[rowIndex];
                final isHeader = rowIndex == 0 && row.isHeader;

                return TableRow(
                  decoration: BoxDecoration(
                    color: isHeader ? headerBackground : rowBackground,
                  ),
                  children: List.generate(row.cells.length, (cellIndex) {
                    final cell = row.cells[cellIndex];
                    final isFirstColumn = cellIndex == 0;
                    final showRightBorder = cellIndex < row.cells.length - 1;

                    return Container(
                      constraints: BoxConstraints(
                        minWidth: isFirstColumn
                            ? (isCompact ? 84 : 96)
                            : (isCompact ? 120 : 140),
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                        vertical: verticalPadding,
                      ),
                      decoration: BoxDecoration(
                        border: Border(
                          right: showRightBorder
                              ? BorderSide(color: borderColor, width: 1)
                              : BorderSide.none,
                          bottom: rowIndex < rows.length - 1
                              ? BorderSide(color: borderColor, width: 1)
                              : BorderSide.none,
                        ),
                      ),
                      child: Text(
                        cell.text,
                        softWrap: true,
                        style: TextStyle(
                          fontSize: (isCompact ? 15 : 17) * fontScale,
                          height: isCompact ? 1.55 : 1.7,
                          fontWeight: isHeader || isFirstColumn
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isDark
                              ? AppTheme.darkModeText
                              : AppTheme.darkText,
                        ),
                      ),
                    );
                  }),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _HtmlTableRowData {
  const _HtmlTableRowData({required this.cells, required this.isHeader});

  final List<_HtmlTableCellData> cells;
  final bool isHeader;
}

class _HtmlTableCellData {
  const _HtmlTableCellData(this.text);

  final String text;
}

List<_HtmlTableRowData> _extractRows(html.Element? tableElement) {
  if (tableElement == null) {
    return const [];
  }

  final rows = <_HtmlTableRowData>[];
  final trElements = tableElement.querySelectorAll('tr');

  for (final row in trElements) {
    final cellElements = row.children
        .where((child) => child.localName == 'th' || child.localName == 'td')
        .toList();

    if (cellElements.isEmpty) {
      continue;
    }

    final isHeader = cellElements.every((cell) => cell.localName == 'th');
    final cells = cellElements
        .map((cell) => _HtmlTableCellData(_extractCellText(cell)))
        .toList();

    rows.add(_HtmlTableRowData(cells: cells, isHeader: isHeader));
  }

  return rows;
}

String _extractCellText(html.Element cell) {
  final raw = cell.innerHtml
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), ' ');

  return raw
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
      .trim();
}

class _HtmlNetworkImage extends StatelessWidget {
  const _HtmlNetworkImage({
    required this.src,
    required this.alt,
    required this.width,
    required this.height,
    required this.isDark,
  });

  final String src;
  final String alt;
  final double? width;
  final double? height;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    if (src.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;
        final resolvedWidth = width == null || width!.isNaN || width! <= 0
            ? maxWidth
            : width!.clamp(0, maxWidth).toDouble();
        final resolvedHeight = height == null || height!.isNaN || height! <= 0
            ? null
            : height;
        final maxImageHeight = MediaQuery.of(context).size.height * 0.58;

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.cardDark : Colors.white,
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            border: Border.all(
              color: isDark ? AppTheme.surfaceMutedDark : AppTheme.dividerColor,
            ),
            boxShadow: isDark ? null : AppTheme.softShadow,
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: resolvedHeight ?? maxImageHeight,
            ),
            child: Image.network(
              src,
              width: resolvedWidth,
              height: resolvedHeight,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) {
                  return child;
                }

                return _HtmlImagePlaceholder(
                  width: resolvedWidth,
                  height: resolvedHeight ?? 220,
                  isDark: isDark,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return _HtmlImagePlaceholder(
                  width: resolvedWidth,
                  height: resolvedHeight ?? 140,
                  isDark: isDark,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      alt.isNotEmpty ? alt : '图片加载失败',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isDark
                            ? AppTheme.darkModeSecondary
                            : AppTheme.mediumText,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _HtmlImagePlaceholder extends StatelessWidget {
  const _HtmlImagePlaceholder({
    required this.width,
    required this.height,
    required this.isDark,
    required this.child,
  });

  final double width;
  final double height;
  final bool isDark;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isDark ? AppTheme.cardDark : AppTheme.primaryLight,
      ),
      child: child,
    );
  }
}

class _HtmlCodeBlock extends StatelessWidget {
  const _HtmlCodeBlock({
    required this.code,
    required this.isDark,
    required this.fontScale,
  });

  final String code;
  final bool isDark;
  final double fontScale;

  @override
  Widget build(BuildContext context) {
    if (code.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final background = isDark ? AppTheme.cardDark : const Color(0xFFF8FAFC);
    final borderColor = isDark
        ? AppTheme.surfaceMutedDark
        : AppTheme.dividerColor;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: borderColor),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            code,
            style: TextStyle(
              fontSize: 14 * fontScale,
              height: 1.7,
              color: isDark ? AppTheme.darkModeText : AppTheme.darkText,
              fontFamily: 'Consolas',
              fontFamilyFallback: const [
                'Cascadia Code',
                'SFMono-Regular',
                'Menlo',
                'Monaco',
                'Courier New',
                'monospace',
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ArticleDetailAuthorRow extends StatelessWidget {
  const ArticleDetailAuthorRow({
    super.key,
    required this.post,
    required this.isDark,
  });

  final WpPost post;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: AppTheme.heroGradient,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              post.author.isNotEmpty ? post.author[0].toUpperCase() : '?',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                post.author,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: isDark ? AppTheme.darkModeText : AppTheme.darkText,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${_formatFullDate(post.date)} · ${post.readMinutes} 分钟阅读',
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
      ],
    );
  }
}

class ArticleDetailMetaPanel extends StatelessWidget {
  const ArticleDetailMetaPanel({
    super.key,
    required this.post,
    required this.isDark,
    required this.onOpenInBrowser,
  });

  final WpPost post;
  final bool isDark;
  final Future<void> Function(String url) onOpenInBrowser;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.cardDark : AppTheme.surfaceMutedLight,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(
          color: isDark ? const Color(0xFF2B3442) : AppTheme.dividerColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ArticleDetailAuthorRow(post: post, isDark: isDark),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ArticleMetaChip(
                icon: Icons.public_rounded,
                label: _formatSourceLabel(post.sourceBaseUrl),
                isDark: isDark,
              ),
              _ArticleMetaChip(
                icon: Icons.schedule_rounded,
                label: '${post.readMinutes} 分钟阅读',
                isDark: isDark,
              ),
              _ArticleMetaChip(
                icon: Icons.event_outlined,
                label: _formatFullDate(post.date),
                isDark: isDark,
              ),
            ],
          ),
          if (post.link.isNotEmpty) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () {
                HapticFeedback.selectionClick();
                onOpenInBrowser(post.link);
              },
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('查看原文来源'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ArticleMetaChip extends StatelessWidget {
  const _ArticleMetaChip({
    required this.icon,
    required this.label,
    required this.isDark,
  });

  final IconData icon;
  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceMutedDark : Colors.white,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: isDark ? AppTheme.darkModeSecondary : AppTheme.mediumText,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

Map<String, Style> _buildHtmlStyles(bool isDark, double fontScale) {
  return {
    'body': Style(
      margin: Margins.zero,
      lineHeight: const LineHeight(2.0),
      letterSpacing: 0.3,
      fontSize: FontSize(17 * fontScale),
      color: isDark ? AppTheme.darkModeText : AppTheme.darkText,
    ),
    'h1': Style(
      margin: Margins.only(top: 32, bottom: 14),
      fontSize: FontSize(26 * fontScale),
      fontWeight: FontWeight.w800,
      color: isDark ? AppTheme.darkModeText : AppTheme.darkText,
    ),
    'h2': Style(
      margin: Margins.only(top: 32, bottom: 16),
      padding: HtmlPaddings.only(left: 12),
      border: const Border(
        left: BorderSide(color: AppTheme.primaryColor, width: 4),
      ),
      fontSize: FontSize(22 * fontScale),
      fontWeight: FontWeight.w700,
      color: isDark ? AppTheme.darkModeText : AppTheme.darkText,
    ),
    'h3': Style(
      margin: Margins.only(top: 20, bottom: 8),
      fontSize: FontSize(19 * fontScale),
      fontWeight: FontWeight.w600,
      color: isDark ? AppTheme.darkModeText : AppTheme.darkText,
    ),
    'p': Style(margin: Margins.only(bottom: 16)),
    'blockquote': Style(
      padding: HtmlPaddings.only(left: 16, top: 12, bottom: 12, right: 12),
      margin: Margins.only(top: 16, bottom: 16),
      backgroundColor: isDark ? AppTheme.cardDark : AppTheme.primaryLight,
      border: const Border(
        left: BorderSide(color: AppTheme.primaryColor, width: 3),
      ),
      fontStyle: FontStyle.italic,
    ),
    'a': Style(
      color: AppTheme.primaryColor,
      textDecoration: TextDecoration.none,
    ),
    'img': Style(margin: Margins.only(top: 16, bottom: 16)),
    'ul': Style(margin: Margins.only(bottom: 16)),
    'ol': Style(margin: Margins.only(bottom: 16)),
    'li': Style(
      margin: Margins.only(bottom: 8),
      lineHeight: const LineHeight(1.6),
    ),
    'code': Style(
      backgroundColor: isDark
          ? AppTheme.surfaceMutedDark
          : const Color(0xFFF1F5F9),
      padding: HtmlPaddings.symmetric(horizontal: 6, vertical: 2),
      fontSize: FontSize(14 * fontScale),
      fontFamily: 'Consolas',
    ),
    'pre': Style(
      margin: Margins.only(top: 16, bottom: 16),
      padding: HtmlPaddings.zero,
      backgroundColor: Colors.transparent,
    ),
  };
}

double? _tryParseDimension(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return null;
  }

  final value = raw.trim().replaceAll('px', '');
  return double.tryParse(value);
}

String _extractCodeBlockText(html.Element? element) {
  if (element == null) {
    return '';
  }

  final codeElement = element.querySelector('code');
  final textSource = codeElement ?? element;
  return textSource.text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .trimRight();
}

String _formatSourceLabel(String sourceBaseUrl) {
  final uri = Uri.tryParse(sourceBaseUrl.trim());
  return uri?.host.isNotEmpty == true
      ? uri!.host
      : sourceBaseUrl.replaceFirst(RegExp(r'^https?://'), '');
}

String _formatFullDate(DateTime date) {
  return '${date.year}年${date.month}月${date.day}日';
}
