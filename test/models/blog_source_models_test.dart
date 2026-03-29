// 博客站点源模型测试
// 测试范围：BlogSiteSource、BlogSiteGroup 的 JSON 序列化/反序列化

import 'package:flutter_test/flutter_test.dart';

import 'package:nishiki_flutter/models/blog_source_models.dart';

void main() {
  group('BlogSiteSource', () {
    test('fromJson 和 toJson 保持数据一致', () {
      final now = DateTime(2026, 3, 23, 12, 0);
      final source = BlogSiteSource(
        baseUrl: 'https://blog.example.com',
        name: '示例博客',
        createdAt: now,
        updatedAt: now,
      );

      // 序列化再反序列化
      final json = source.toJson();
      final restored = BlogSiteSource.fromJson(json);

      expect(restored.baseUrl, source.baseUrl);
      expect(restored.name, source.name);
    });

    test('fromRow 从数据库行解析', () {
      final row = <String, Object?>{
        'base_url': 'https://blog.nishiki.icu',
        'name': 'Nishiki 博客',
        'created_at': '2026-01-01T00:00:00.000',
        'updated_at': '2026-03-23T12:00:00.000',
      };

      final source = BlogSiteSource.fromRow(row);

      expect(source.baseUrl, 'https://blog.nishiki.icu');
      expect(source.name, 'Nishiki 博客');
    });

    test('fromRow 处理缺失字段', () {
      final row = <String, Object?>{
        'base_url': 'https://minimal.example.com',
      };

      final source = BlogSiteSource.fromRow(row);

      expect(source.baseUrl, 'https://minimal.example.com');
      // 缺失 name 默认为空字符串
      expect(source.name, isEmpty);
    });
  });

  group('BlogSiteGroup', () {
    test('fromJson 和 toJson 保持数据一致', () {
      final now = DateTime(2026, 3, 23, 12, 0);
      final group = BlogSiteGroup(
        id: 'group-1',
        name: '技术博客组',
        sourceBaseUrls: const [
          'https://a.example.com',
          'https://b.example.com',
        ],
        createdAt: now,
        updatedAt: now,
      );

      final json = group.toJson();
      final restored = BlogSiteGroup.fromJson(json);

      expect(restored.id, group.id);
      expect(restored.name, group.name);
      expect(restored.sourceBaseUrls, group.sourceBaseUrls);
    });

    test('fromJson 处理空 sourceBaseUrls', () {
      final json = <String, dynamic>{
        'id': 'group-empty',
        'name': '空组合',
        'sourceBaseUrls': <String>[],
      };

      final group = BlogSiteGroup.fromJson(json);

      expect(group.id, 'group-empty');
      expect(group.sourceBaseUrls, isEmpty);
    });
  });

  group('BlogSourceMode', () {
    test('枚举值正确', () {
      expect(BlogSourceMode.values.length, 2);
      expect(BlogSourceMode.values, contains(BlogSourceMode.single));
      expect(BlogSourceMode.values, contains(BlogSourceMode.aggregate));
    });
  });
}
