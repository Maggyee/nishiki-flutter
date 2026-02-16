import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// ============================================================
/// 书签 & 点赞 本地服务
/// 使用 SharedPreferences 将用户的收藏和点赞状态保存到本地
/// ============================================================
class BookmarkService {
  // 单例模式 — 全局只有一个实例
  static final BookmarkService _instance = BookmarkService._internal();
  factory BookmarkService() => _instance;
  BookmarkService._internal();

  // SharedPreferences 的 key
  static const _likedKey = 'liked_post_ids';       // 已点赞文章ID列表
  static const _savedKey = 'saved_post_ids';       // 已收藏文章ID列表
  static const _savedPostsKey = 'saved_posts_data'; // 已收藏文章的完整数据（用于离线展示）

  // 内存缓存 — 避免频繁读取磁盘
  Set<int> _likedIds = {};
  Set<int> _savedIds = {};
  bool _initialized = false;

  /// 初始化服务（从磁盘加载数据到内存）
  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();

    // 加载已点赞的文章ID
    final likedList = prefs.getStringList(_likedKey) ?? [];
    _likedIds = likedList.map((e) => int.tryParse(e) ?? 0).where((id) => id > 0).toSet();

    // 加载已收藏的文章ID
    final savedList = prefs.getStringList(_savedKey) ?? [];
    _savedIds = savedList.map((e) => int.tryParse(e) ?? 0).where((id) => id > 0).toSet();

    _initialized = true;
  }

  // ==================== 点赞功能 ====================

  /// 检查文章是否已点赞
  bool isLiked(int postId) => _likedIds.contains(postId);

  /// 切换点赞状态（点赞/取消点赞）
  Future<bool> toggleLike(int postId) async {
    await init();
    if (_likedIds.contains(postId)) {
      _likedIds.remove(postId);
    } else {
      _likedIds.add(postId);
    }
    await _saveLikedIds();
    return _likedIds.contains(postId);
  }

  /// 获取点赞总数（本地统计）
  int get likedCount => _likedIds.length;

  // ==================== 收藏/书签功能 ====================

  /// 检查文章是否已收藏
  bool isSaved(int postId) => _savedIds.contains(postId);

  /// 切换收藏状态（收藏/取消收藏），同时存储文章摘要数据
  Future<bool> toggleSave(int postId, {Map<String, dynamic>? postData}) async {
    await init();
    if (_savedIds.contains(postId)) {
      _savedIds.remove(postId);
      await _removeSavedPostData(postId);
    } else {
      _savedIds.add(postId);
      if (postData != null) {
        await _addSavedPostData(postId, postData);
      }
    }
    await _saveSavedIds();
    return _savedIds.contains(postId);
  }

  /// 获取所有收藏的文章ID
  Set<int> get savedPostIds => Set.unmodifiable(_savedIds);

  /// 获取所有收藏的文章数据（用于收藏列表展示）
  Future<List<Map<String, dynamic>>> getSavedPostsData() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_savedPostsKey);
    if (raw == null) return [];

    try {
      final List<dynamic> list = json.decode(raw);
      // 只返回当前仍在收藏列表中的文章
      return list
          .cast<Map<String, dynamic>>()
          .where((item) => _savedIds.contains(item['id']))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 获取收藏总数
  int get savedCount => _savedIds.length;

  // ==================== 私有方法 ====================

  /// 持久化已点赞的ID列表
  Future<void> _saveLikedIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _likedKey,
      _likedIds.map((id) => id.toString()).toList(),
    );
  }

  /// 持久化已收藏的ID列表
  Future<void> _saveSavedIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _savedKey,
      _savedIds.map((id) => id.toString()).toList(),
    );
  }

  /// 添加一条收藏文章的摘要数据
  Future<void> _addSavedPostData(int postId, Map<String, dynamic> postData) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_savedPostsKey);
    List<Map<String, dynamic>> list = [];

    if (raw != null) {
      try {
        list = (json.decode(raw) as List).cast<Map<String, dynamic>>();
      } catch (_) {}
    }

    // 避免重复添加
    list.removeWhere((item) => item['id'] == postId);
    list.insert(0, postData); // 新收藏的排在最前面

    await prefs.setString(_savedPostsKey, json.encode(list));
  }

  /// 删除一条收藏文章的摘要数据
  Future<void> _removeSavedPostData(int postId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_savedPostsKey);
    if (raw == null) return;

    try {
      final list = (json.decode(raw) as List).cast<Map<String, dynamic>>();
      list.removeWhere((item) => item['id'] == postId);
      await prefs.setString(_savedPostsKey, json.encode(list));
    } catch (_) {}
  }
}
