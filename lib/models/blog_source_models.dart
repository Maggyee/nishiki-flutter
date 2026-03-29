// 博客站点源相关数据模型
// 包含：BlogSourceMode（单站点/聚合枚举）、BlogSiteSource（站点实体）、BlogSiteGroup（站点组合实体）

// ===== 博客数据源模式枚举 =====
enum BlogSourceMode { single, aggregate }

/// 站点实体 — 表示一个博客站点（支持 WordPress 和 RSS）
class BlogSiteSource {
  const BlogSiteSource({
    required this.baseUrl,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.sourceType = 'wordpress',
    this.feedUrl,
    this.siteUrl,
  });

  /// 站点根地址（唯一标识）
  final String baseUrl;

  /// 用户自定义的站点名称
  final String name;

  /// 来源类型：'wordpress' | 'rss'（默认 wordpress）
  final String sourceType;

  /// RSS Feed 实际地址（仅 rss 类型使用）
  final String? feedUrl;

  /// 站点主页地址（可选，用于界面跳转展示）
  final String? siteUrl;

  /// 创建时间
  final DateTime createdAt;

  /// 最后更新时间
  final DateTime updatedAt;

  /// 是否为 RSS 类型源
  bool get isRss => sourceType == 'rss';

  /// 提取域名作为简短标签（去除 www. 前缀）
  String get hostLabel {
    final host = Uri.tryParse(baseUrl)?.host;
    if (host != null && host.isNotEmpty) {
      return host.replaceFirst('www.', '');
    }
    return baseUrl.replaceFirst('https://', '').replaceFirst('http://', '');
  }

  /// 序列化为 JSON（包含新字段，旧后端忽略多余字段不影响）
  Map<String, dynamic> toJson() => {
    'baseUrl': baseUrl,
    'name': name,
    'sourceType': sourceType,
    if (feedUrl != null) 'feedUrl': feedUrl,
    if (siteUrl != null) 'siteUrl': siteUrl,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  /// 从 JSON 反序列化（兼容不含新字段的旧数据）
  factory BlogSiteSource.fromJson(Map<String, dynamic> json) {
    return BlogSiteSource(
      baseUrl: (json['baseUrl'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      sourceType: (json['sourceType'] as String?) ?? 'wordpress',
      feedUrl: json['feedUrl'] as String?,
      siteUrl: json['siteUrl'] as String?,
      createdAt:
          DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse((json['updatedAt'] as String?) ?? '') ??
          DateTime.now(),
    );
  }

  /// 从数据库行构建（SQLite 列名为 snake_case，兼容旧表无新字段的情况）
  factory BlogSiteSource.fromRow(Map<String, dynamic> row) {
    return BlogSiteSource(
      baseUrl: row['base_url'] as String,
      name: (row['name'] as String?) ?? '',
      sourceType: (row['source_type'] as String?) ?? 'wordpress',
      feedUrl: row['feed_url'] as String?,
      siteUrl: row['site_url'] as String?,
      createdAt:
          DateTime.tryParse((row['created_at'] as String?) ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse((row['updated_at'] as String?) ?? '') ??
          DateTime.now(),
    );
  }
}

/// 站点组合 — 将多个站点组合在一起进行聚合阅读
class BlogSiteGroup {
  const BlogSiteGroup({
    required this.id,
    required this.name,
    required this.sourceBaseUrls,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 组合唯一标识
  final String id;

  /// 组合名称
  final String name;

  /// 包含的站点 URL 列表
  final List<String> sourceBaseUrls;

  /// 创建时间
  final DateTime createdAt;

  /// 最后更新时间
  final DateTime updatedAt;

  /// 序列化为 JSON
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'sourceBaseUrls': sourceBaseUrls,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  /// 从 JSON 反序列化
  factory BlogSiteGroup.fromJson(Map<String, dynamic> json) {
    return BlogSiteGroup(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      sourceBaseUrls: ((json['sourceBaseUrls'] as List<dynamic>?) ?? const [])
          .whereType<String>()
          .toList(),
      createdAt:
          DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse((json['updatedAt'] as String?) ?? '') ??
          DateTime.now(),
    );
  }
}
