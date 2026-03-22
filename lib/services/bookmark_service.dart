import '../repositories/bookmark_repository.dart';

class BookmarkService implements BookmarkRepository {
  static final BookmarkService _instance = BookmarkService._internal();

  factory BookmarkService() => _instance;

  BookmarkService._internal({BookmarkRepository? repository})
    : _repository = repository ?? LocalBookmarkRepository();

  final BookmarkRepository _repository;

  @override
  Future<void> init() => _repository.init();

  @override
  bool isLiked(int postId, {String? sourceBaseUrl}) =>
      _repository.isLiked(postId, sourceBaseUrl: sourceBaseUrl);

  @override
  Future<bool> toggleLike(
    int postId, {
    String? sourceBaseUrl,
    Map<String, dynamic>? postData,
  }) => _repository.toggleLike(
    postId,
    sourceBaseUrl: sourceBaseUrl,
    postData: postData,
  );

  @override
  int get likedCount => _repository.likedCount;

  @override
  Future<List<Map<String, dynamic>>> getLikedPostsData() =>
      _repository.getLikedPostsData();

  @override
  bool isSaved(int postId, {String? sourceBaseUrl}) =>
      _repository.isSaved(postId, sourceBaseUrl: sourceBaseUrl);

  @override
  Future<bool> toggleSave(
    int postId, {
    String? sourceBaseUrl,
    Map<String, dynamic>? postData,
  }) => _repository.toggleSave(
    postId,
    sourceBaseUrl: sourceBaseUrl,
    postData: postData,
  );

  @override
  Set<int> get savedPostIds => _repository.savedPostIds;

  @override
  Future<List<Map<String, dynamic>>> getSavedPostsData() =>
      _repository.getSavedPostsData();

  @override
  int get savedCount => _repository.savedCount;

  @override
  Future<void> clearAll() => _repository.clearAll();
}
