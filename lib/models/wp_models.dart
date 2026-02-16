import 'package:html/parser.dart' as html_parser;

String htmlToText(String? source) {
  if (source == null || source.isEmpty) {
    return '';
  }
  return html_parser.parse(source).documentElement?.text.trim() ?? '';
}

class WpCategory {
  const WpCategory({required this.id, required this.name});

  final int id;
  final String name;

  factory WpCategory.fromJson(Map<String, dynamic> json) {
    return WpCategory(
      id: json['id'] as int,
      name: (json['name'] as String?) ?? 'Unknown',
    );
  }
}

class WpPost {
  const WpPost({
    required this.id,
    required this.title,
    required this.excerpt,
    required this.contentHtml,
    required this.author,
    required this.date,
    required this.featuredImageUrl,
    required this.categories,
    required this.link,
  });

  final int id;
  final String title;
  final String excerpt;
  final String contentHtml;
  final String author;
  final DateTime date;
  final String? featuredImageUrl;
  final List<String> categories;
  final String link; // 文章原始链接（用于分享）

  /// 转换为简要 Map（用于本地收藏存储，不含完整 HTML 内容）
  Map<String, dynamic> toSummaryMap() {
    return {
      'id': id,
      'title': title,
      'excerpt': excerpt,
      'author': author,
      'date': date.toIso8601String(),
      'featuredImageUrl': featuredImageUrl,
      'categories': categories,
      'link': link,
    };
  }

  /// 从本地存储的简要 Map 恢复
  factory WpPost.fromSummaryMap(Map<String, dynamic> map) {
    return WpPost(
      id: map['id'] as int,
      title: (map['title'] as String?) ?? 'Untitled',
      excerpt: (map['excerpt'] as String?) ?? '',
      contentHtml: '', // 本地缓存不存储完整内容
      author: (map['author'] as String?) ?? 'Unknown',
      date: DateTime.tryParse((map['date'] as String?) ?? '') ?? DateTime.now(),
      featuredImageUrl: map['featuredImageUrl'] as String?,
      categories: ((map['categories'] as List<dynamic>?) ?? []).cast<String>(),
      link: (map['link'] as String?) ?? '',
    );
  }

  factory WpPost.fromJson(Map<String, dynamic> json) {
    final embedded = json['_embedded'] as Map<String, dynamic>?;
    final authorList = embedded?['author'] as List<dynamic>?;
    final mediaList = embedded?['wp:featuredmedia'] as List<dynamic>?;
    final termLists = embedded?['wp:term'] as List<dynamic>?;

    final categoryNames = <String>[];
    if (termLists != null) {
      for (final termList in termLists) {
        if (termList is List) {
          for (final term in termList) {
            if (term is Map<String, dynamic> && term['taxonomy'] == 'category') {
              final name = term['name'] as String?;
              if (name != null && name.isNotEmpty) {
                categoryNames.add(name);
              }
            }
          }
        }
      }
    }

    final title = htmlToText((json['title'] as Map<String, dynamic>?)?['rendered'] as String?);
    final excerpt = htmlToText((json['excerpt'] as Map<String, dynamic>?)?['rendered'] as String?);
    final contentHtml = ((json['content'] as Map<String, dynamic>?)?['rendered'] as String?) ?? '';
    final author = (authorList != null && authorList.isNotEmpty)
        ? ((authorList.first as Map<String, dynamic>)['name'] as String? ?? 'Unknown author')
        : 'Unknown author';
    final featuredImageUrl = (mediaList != null && mediaList.isNotEmpty)
        ? ((mediaList.first as Map<String, dynamic>)['source_url'] as String?)
        : null;
    // 获取文章原始链接
    final link = (json['link'] as String?) ?? '';

    return WpPost(
      id: json['id'] as int,
      title: title.isEmpty ? 'Untitled' : title,
      excerpt: excerpt,
      contentHtml: contentHtml,
      author: author,
      date: DateTime.tryParse((json['date'] as String?) ?? '') ?? DateTime.now(),
      featuredImageUrl: featuredImageUrl,
      categories: categoryNames,
      link: link,
    );
  }
}
