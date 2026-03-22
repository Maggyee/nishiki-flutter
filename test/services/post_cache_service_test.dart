import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nishiki_flutter/models/wp_models.dart';
import 'package:nishiki_flutter/services/blog_source_service.dart';
import 'package:nishiki_flutter/services/local_database_service.dart';
import 'package:nishiki_flutter/services/post_cache_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final cache = PostCacheService();
  final database = LocalDatabaseService();
  final blogSource = BlogSourceService();

  WpPost buildPost({
    required int id,
    required List<int> categoryIds,
  }) {
    return WpPost(
      sourceBaseUrl: blogSource.baseUrl.value,
      id: id,
      title: 'Post $id',
      excerpt: 'Excerpt $id',
      contentHtml: '<p>Body $id</p>',
      author: 'Tester',
      date: DateTime.utc(2026, 3, id),
      featuredImageUrl: null,
      categories: categoryIds.map((value) => 'Category $value').toList(),
      categoryIds: categoryIds,
      link: 'https://example.com/posts/$id',
      readMinutes: 1,
    );
  }

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await blogSource.reset();
  });

  setUp(() async {
    await database.clearAllData();
  });

  tearDownAll(() async {
    await database.clearAllData();
    await database.close();
  });

  group('PostCacheService', () {
    test('stores post_categories rows for each cached post category', () async {
      await cache.cachePosts([
        buildPost(id: 1, categoryIds: const [2, 12]),
      ]);

      final db = await database.database;
      final rows = await db!.query(
        LocalDatabaseService.postCategoriesTable,
        orderBy: 'category_id ASC',
      );

      expect(rows, hasLength(2));
      expect(
        rows.map((row) => row['category_id']),
        orderedEquals(const [2, 12]),
      );
    });

    test('filters cached posts by exact category id via relation table', () async {
      await cache.cachePosts([
        buildPost(id: 1, categoryIds: const [2]),
        buildPost(id: 2, categoryIds: const [12]),
      ]);

      final category2Posts = await cache.getCachedPosts(categoryId: 2);
      final category12Posts = await cache.getCachedPosts(categoryId: 12);

      expect(category2Posts.map((post) => post.id), orderedEquals(const [1]));
      expect(category12Posts.map((post) => post.id), orderedEquals(const [2]));
    });
  });
}
