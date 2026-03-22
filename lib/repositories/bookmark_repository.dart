import '../data/bookmark_local_data_source.dart';

abstract class BookmarkRepository {
  Future<void> init();

  bool isLiked(int postId, {String? sourceBaseUrl});

  Future<bool> toggleLike(
    int postId, {
    String? sourceBaseUrl,
    Map<String, dynamic>? postData,
  });

  int get likedCount;

  Future<List<Map<String, dynamic>>> getLikedPostsData();

  bool isSaved(int postId, {String? sourceBaseUrl});

  Future<bool> toggleSave(
    int postId, {
    String? sourceBaseUrl,
    Map<String, dynamic>? postData,
  });

  Set<int> get savedPostIds;

  Future<List<Map<String, dynamic>>> getSavedPostsData();

  int get savedCount;

  Future<void> clearAll();
}

class LocalBookmarkRepository implements BookmarkRepository {
  LocalBookmarkRepository({BookmarkLocalDataSource? dataSource})
    : _dataSource = dataSource ?? BookmarkLocalDataSource();

  final BookmarkLocalDataSource _dataSource;

  @override
  Future<void> init() => _dataSource.init();

  @override
  bool isLiked(int postId, {String? sourceBaseUrl}) =>
      _dataSource.isLiked(postId, sourceBaseUrl: sourceBaseUrl);

  @override
  Future<bool> toggleLike(
    int postId, {
    String? sourceBaseUrl,
    Map<String, dynamic>? postData,
  }) => _dataSource.toggleLike(
    postId,
    sourceBaseUrl: sourceBaseUrl,
    postData: postData,
  );

  @override
  int get likedCount => _dataSource.likedCount;

  @override
  Future<List<Map<String, dynamic>>> getLikedPostsData() =>
      _dataSource.getLikedPostsData();

  @override
  bool isSaved(int postId, {String? sourceBaseUrl}) =>
      _dataSource.isSaved(postId, sourceBaseUrl: sourceBaseUrl);

  @override
  Future<bool> toggleSave(
    int postId, {
    String? sourceBaseUrl,
    Map<String, dynamic>? postData,
  }) => _dataSource.toggleSave(
    postId,
    sourceBaseUrl: sourceBaseUrl,
    postData: postData,
  );

  @override
  Set<int> get savedPostIds => _dataSource.savedPostIds;

  @override
  Future<List<Map<String, dynamic>>> getSavedPostsData() =>
      _dataSource.getSavedPostsData();

  @override
  int get savedCount => _dataSource.savedCount;

  @override
  Future<void> clearAll() => _dataSource.clearAll();
}
