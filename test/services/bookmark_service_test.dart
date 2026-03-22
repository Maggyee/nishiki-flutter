import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nishiki_flutter/services/bookmark_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('BookmarkService toggles likes and saves summary data', () async {
    SharedPreferences.setMockInitialValues({});
    final service = BookmarkService();

    await service.clearAll();
    await service.init();

    expect(service.likedCount, 0);
    expect(service.savedCount, 0);
    expect(service.isLiked(11), isFalse);
    expect(service.isSaved(11), isFalse);

    final liked = await service.toggleLike(11);
    expect(liked, isTrue);
    expect(service.isLiked(11), isTrue);
    expect(service.likedCount, 1);

    final saved = await service.toggleSave(
      11,
      postData: {
        'id': 11,
        'title': 'Saved post',
        'excerpt': 'Summary',
        'author': 'Author',
        'date': '2026-03-17T00:00:00.000',
        'featuredImageUrl': null,
        'categories': ['Testing'],
        'link': 'https://example.com/11',
        'readMinutes': 3,
      },
    );

    expect(saved, isTrue);
    expect(service.isSaved(11), isTrue);
    expect(service.savedPostIds, contains(11));
    expect(service.savedCount, 1);

    final savedPosts = await service.getSavedPostsData();
    expect(savedPosts, hasLength(1));
    expect(savedPosts.first['id'], 11);
    expect(savedPosts.first['title'], 'Saved post');

    final unsaved = await service.toggleSave(11);
    expect(unsaved, isFalse);
    expect(service.isSaved(11), isFalse);
    expect(await service.getSavedPostsData(), isEmpty);
  });
}
