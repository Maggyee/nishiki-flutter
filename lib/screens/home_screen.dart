import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/wp_models.dart';
import '../services/blog_source_service.dart';
import '../services/content_api_service.dart';
import '../services/bookmark_service.dart';
import '../widgets/article_card.dart';
import 'article_detail_screen.dart';
import 'stats_posts_screen.dart';
import '../theme/app_theme.dart';
import '../config.dart';

// 拆分出的子组件
import '../widgets/home_tabs/home_feed_tab.dart';
import '../widgets/home_tabs/search_tab.dart';
import '../widgets/home_tabs/saved_tab.dart';
import '../widgets/home_tabs/profile_tab.dart';
import '../widgets/home_tabs/source_manager_sheet.dart';

/// 主页 — 承载 4 个 Tab 的壳层，管理全局状态和业务逻辑
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  // ===== 服务实例 =====
  final _api = ContentApiService();
  final _searchController = TextEditingController();
  final _bookmarkService = BookmarkService();
  final _blogSource = BlogSourceService();

  // ===== 文章和分类数据 =====
  List<WpPost> _posts = const [];
  List<WpCategory> _categories = const [];
  final List<String> _recentSearches = [];
  bool _categoriesLoading = false;

  // ===== 收藏文章数据 =====
  List<WpPost> _savedPosts = const [];
  bool _savedLoading = false;

  // ===== 加载状态 =====
  bool _loading = true;
  String? _error;
  ContentApiException? _apiError;

  // ===== Profile 页面动画控制器 =====
  late AnimationController _avatarPulseCtrl; // 头像呼吸脉冲
  late AnimationController _profileEnterCtrl; // 入场动画
  late Animation<double> _avatarPulseAnim; // 脉冲缩放动画

  // ===== Tab 状态 =====
  int _tabIndex = 0;
  int? _selectedCategoryId;
  Timer? _searchDebounce;
  int _searchRequestId = 0;
  static const int _pageSize = 12;
  int _currentPage = 1;
  bool _hasMore = true;
  bool _loadingMore = false;
  bool _isSearchContext = false;
  String _activeSearchTerm = '';
  int? _activeCategoryId;

  @override
  void initState() {
    super.initState();
    // 监听站点源状态变化
    _blogSource.baseUrl.addListener(_handleSourceStateChanged);
    _blogSource.mode.addListener(_handleSourceStateChanged);
    _blogSource.sourceEntries.addListener(_handleSourceStateChanged);
    _blogSource.groups.addListener(_handleSourceStateChanged);
    _blogSource.selectedGroupId.addListener(_handleSourceStateChanged);
    _loadInitial();

    // 头像呼吸脉冲动画（无限循环）
    _avatarPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _avatarPulseAnim = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _avatarPulseCtrl, curve: Curves.easeInOut),
    );

    // Profile 入场动画（一次性）
    _profileEnterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _syncProfilePulseForTab(_tabIndex);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _blogSource.baseUrl.removeListener(_handleSourceStateChanged);
    _blogSource.mode.removeListener(_handleSourceStateChanged);
    _blogSource.sourceEntries.removeListener(_handleSourceStateChanged);
    _blogSource.groups.removeListener(_handleSourceStateChanged);
    _blogSource.selectedGroupId.removeListener(_handleSourceStateChanged);
    _searchController.dispose();
    _avatarPulseCtrl.dispose();
    _profileEnterCtrl.dispose();
    super.dispose();
  }

  // ==================== 业务逻辑 ====================

  bool get _isAggregateMode =>
      _blogSource.mode.value == BlogSourceMode.aggregate;

  /// 站点源状态变化处理
  void _handleSourceStateChanged() {
    if (!mounted) return;
    setState(() {
      _selectedCategoryId = null;
      _categories = const [];
    });
    if (_tabIndex == 1 && !_isAggregateMode) {
      _loadCategoriesIfNeeded();
    }
    _loadInitial();
  }

  /// 延迟搜索（防抖）
  void _scheduleSearch({
    String? forcedTerm,
    Duration delay = const Duration(milliseconds: 280),
  }) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(delay, () {
      _search(forcedTerm);
    });
  }

  /// 控制 Profile Tab 的头像动画
  void _syncProfilePulseForTab(int tabIndex) {
    if (tabIndex == 3) {
      if (!_avatarPulseCtrl.isAnimating) {
        _avatarPulseCtrl.repeat(reverse: true);
      }
      return;
    }
    _avatarPulseCtrl.stop();
    _avatarPulseCtrl.value = 0.0;
  }

  void _preparePaginationContext({
    required bool isSearchContext,
    String searchTerm = '',
    int? categoryId,
  }) {
    _isSearchContext = isSearchContext;
    _activeSearchTerm = searchTerm;
    _activeCategoryId = categoryId;
    _currentPage = 1;
    _hasMore = true;
    _loadingMore = false;
  }

  Future<void> _loadMorePosts() async {
    if (_loading || _loadingMore || !_hasMore || _tabIndex == 2 || _tabIndex == 3) {
      return;
    }

    final requestId = _searchRequestId;
    if (mounted) {
      setState(() {
        _loadingMore = true;
      });
    } else {
      _loadingMore = true;
    }
    try {
      final nextPage = _currentPage + 1;
      final nextPosts = await _api.fetchPosts(
        search: _isSearchContext ? _activeSearchTerm : '',
        categoryId: _isSearchContext ? _activeCategoryId : null,
        page: nextPage,
      );

      if (!mounted || requestId != _searchRequestId) {
        return;
      }

      if (nextPosts.isEmpty) {
        setState(() {
          _hasMore = false;
        });
        return;
      }

      setState(() {
        _posts = [..._posts, ...nextPosts];
        _currentPage = nextPage;
        _hasMore = nextPosts.length >= _pageSize;
      });
    } catch (_) {
      // Keep current list and allow retry on next scroll.
    } finally {
      if (mounted) {
        setState(() {
          _loadingMore = false;
        });
      } else {
        _loadingMore = false;
      }
    }
  }

  bool _handleFeedScroll(ScrollNotification notification) {
    if (_tabIndex != 0 && _tabIndex != 1) {
      return false;
    }
    if (notification.metrics.extentAfter < 500) {
      _loadMorePosts();
    }
    return false;
  }

  /// 首次加载文章列表
  Future<void> _loadInitial() async {
    final requestId = ++_searchRequestId;
    _preparePaginationContext(isSearchContext: false);
    setState(() {
      _loading = true;
      _error = null;
      _apiError = null;
    });

    try {
      setState(() => _posts = const []);
      final posts = await _api.fetchPosts();
      if (!mounted || requestId != _searchRequestId) return;
      setState(() {
        _posts = posts;
        _loading = false;
        _hasMore = posts.length >= _pageSize;
      });
    } catch (e) {
      if (!mounted || requestId != _searchRequestId) return;
      setState(() {
        if (e is ContentApiException) {
          _apiError = e;
          _error = e.userMessage;
        } else {
          _error = e.toString();
        }
        _loading = false;
      });
    }
  }

  /// 懒加载分类列表
  Future<void> _loadCategoriesIfNeeded() async {
    if (_isAggregateMode) {
      if (mounted && _categories.isNotEmpty) {
        setState(() => _categories = const []);
      }
      return;
    }
    if (_categoriesLoading || _categories.isNotEmpty) return;
    _categoriesLoading = true;
    try {
      final categories = await _api.fetchCategories();
      if (!mounted) return;
      setState(() => _categories = categories);
    } catch (_) {
      // 分类加载失败不影响搜索功能
    } finally {
      _categoriesLoading = false;
    }
  }

  /// 加载收藏文章列表
  Future<void> _loadSavedPosts() async {
    setState(() => _savedLoading = true);
    try {
      await _bookmarkService.init();
      final savedData = await _bookmarkService.getSavedPostsData();
      if (mounted) {
        setState(() {
          _savedPosts = savedData
              .map((data) => WpPost.fromSummaryMap(data))
              .toList();
          _savedLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _savedLoading = false);
    }
  }

  /// 打开文章详情页
  Future<void> _openPostDetail(WpPost post) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ArticleDetailScreen(post: post)),
    );
    if (!mounted) return;
    setState(() {});
    if (_tabIndex == 2) await _loadSavedPosts();
  }

  /// 打开统计文章列表页面
  Future<void> _openStatPostsScreen({
    required String title,
    required String emptyTitle,
    required String emptySubtitle,
    required IconData emptyIcon,
    required Future<List<WpPost>> Function() loadPosts,
  }) async {
    HapticFeedback.selectionClick();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StatsPostsScreen(
          title: title,
          emptyTitle: emptyTitle,
          emptySubtitle: emptySubtitle,
          emptyIcon: emptyIcon,
          loadPosts: loadPosts,
          onOpenPost: _openPostDetail,
        ),
      ),
    );
    if (!mounted) return;
    setState(() {});
    if (_tabIndex == 2) await _loadSavedPosts();
  }

  /// 执行搜索
  Future<void> _search([String? forcedTerm]) async {
    final term = (forcedTerm ?? _searchController.text).trim();
    final requestId = ++_searchRequestId;

    if (term.isEmpty && _selectedCategoryId == null) {
      await _loadInitial();
      return;
    }

    _preparePaginationContext(
      isSearchContext: true,
      searchTerm: term,
      categoryId: _selectedCategoryId,
    );

    setState(() {
      _loading = true;
      _error = null;
      _apiError = null;
    });

    try {
      final posts = await _api.fetchPosts(
        search: term,
        categoryId: _selectedCategoryId,
      );

      if (!mounted || requestId != _searchRequestId) return;

      setState(() {
        _posts = posts;
        _loading = false;
        _hasMore = posts.length >= _pageSize;
      });

      if (term.isNotEmpty) {
        _recentSearches.remove(term);
        _recentSearches.insert(0, term);
        if (_recentSearches.length > 5) {
          _recentSearches.removeLast();
        }
      }
    } catch (e) {
      if (!mounted || requestId != _searchRequestId) return;
      setState(() {
        if (e is ContentApiException) {
          _apiError = e;
          _error = e.userMessage;
        } else {
          _error = e.toString();
        }
        _loading = false;
      });
    }
  }

  /// 切换 Tab
  void _goToTab(int tabIndex) {
    setState(() => _tabIndex = tabIndex);
    _syncProfilePulseForTab(tabIndex);
  }

  // ==================== UI 构建 ====================

  @override
  Widget build(BuildContext context) {
    // 根据当前 Tab 渲染对应子组件
    final body = switch (_tabIndex) {
      0 => HomeFeedTab(
          posts: _posts,
          loading: _loading,
          error: _error,
          apiError: _apiError,
          scopeLabel: _blogSource.currentScopeLabel,
          isAggregateMode: _isAggregateMode,
          onRefresh: _loadInitial,
          onOpenPost: _openPostDetail,
          onManageSources: () => SourceManagerSheet.show(context),
          onBuildFeed: _buildFeed,
        ),
      1 => SearchTab(
          searchController: _searchController,
          categories: _categories,
          recentSearches: _recentSearches,
          selectedCategoryId: _selectedCategoryId,
          isAggregateMode: _isAggregateMode,
          onSearch: _search,
          onScheduleSearch: ({String? forcedTerm, Duration delay = const Duration(milliseconds: 280)}) {
            _scheduleSearch(forcedTerm: forcedTerm, delay: delay);
          },
          onCategorySelected: (categoryId) {
            setState(() => _selectedCategoryId = categoryId);
            _scheduleSearch(delay: Duration.zero);
          },
          onBuildFeed: _buildFeed,
        ),
      2 => SavedTab(
          savedPosts: _savedPosts,
          savedLoading: _savedLoading,
          onRefresh: _loadSavedPosts,
          onPostsChanged: _loadSavedPosts,
          onGoToTab: _goToTab,
        ),
      _ => ProfileTab(
          avatarPulseAnim: _avatarPulseAnim,
          profileEnterCtrl: _profileEnterCtrl,
          onOpenStatPostsScreen: _openStatPostsScreen,
          onShowSourceManager: () => SourceManagerSheet.show(context),
          onLoginStateChanged: () {
            // 登录/登出后刷新界面
            if (mounted) setState(() {});
          },
        ),
    };

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 60,
        titleSpacing: 16,
        title: SizedBox(
          height: 28,
          child: Semantics(
            label: 'Nishiki 博客徽标',
            image: true,
            child: Image.asset(
              'assets/images/site_wordmark.png',
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
              errorBuilder: (context, error, stackTrace) {
                return const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Nishiki 博客'),
                );
              },
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: '站点与组合',
            onPressed: () => SourceManagerSheet.show(context),
            icon: const Icon(Icons.hub_outlined),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: () {
              if (_tabIndex == 2) {
                _loadSavedPosts();
              } else {
                _loadInitial();
              }
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: _handleFeedScroll,
        child: body,
      ),
      bottomNavigationBar: TooltipVisibility(
        visible: false,
        child: NavigationBar(
          key: const ValueKey('home.bottom_navigation'),
          selectedIndex: _tabIndex,
          onDestinationSelected: (value) {
            if (_tabIndex == value) return;
            setState(() => _tabIndex = value);
            _syncProfilePulseForTab(value);
            // 切换到收藏 tab 时自动刷新数据
            if (value == 2) _loadSavedPosts();
            // 切换到搜索 tab 时懒加载分类
            if (value == 1) _loadCategoriesIfNeeded();
            // 切换到 Profile 时播放入场动画
            if (value == 3) {
              _profileEnterCtrl.forward(from: 0.0);
            }
          },
          destinations: const [
            NavigationDestination(
              key: ValueKey('home.nav.home'),
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: '首页',
            ),
            NavigationDestination(
              key: ValueKey('home.nav.search'),
              icon: Icon(Icons.search_outlined),
              selectedIcon: Icon(Icons.search),
              label: '搜索',
            ),
            NavigationDestination(
              key: ValueKey('home.nav.saved'),
              icon: Icon(Icons.bookmark_outline),
              selectedIcon: Icon(Icons.bookmark),
              label: '收藏',
            ),
            NavigationDestination(
              key: ValueKey('home.nav.profile'),
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: '我的',
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 共用的 Feed 列表构建 ====================

  /// 构建文章 Feed 列表（首页和搜索 Tab 共用）
  Widget _buildFeed({required String sectionTitle, bool skipFirst = false}) {
    if (_loading) {
      return _buildFeedSkeleton(sectionTitle: sectionTitle);
    }

    if (_error != null) {
      return _buildErrorCard();
    }

    final displayPosts = skipFirst && _posts.length > 1
        ? _posts.skip(1).toList()
        : _posts;

    if (displayPosts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('没有找到匹配的文章，请尝试其他关键词或分类。')),
      );
    }

    final shouldShowPaginationFooter =
        _tabIndex == 0 || _tabIndex == 1;
    final extraFooterCount = shouldShowPaginationFooter ? 1 : 0;

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: displayPosts.length + 1 + extraFooterCount,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              sectionTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          );
        }

        if (shouldShowPaginationFooter && index == displayPosts.length + 1) {
          if (_loadingMore) {
            return const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          if (!_hasMore && _posts.length >= _pageSize) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: Center(
                child: Text(
                  'No more posts',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            );
          }
          return const SizedBox.shrink();
        }

        final post = displayPosts[index - 1];
        return ArticleCard(
          post: post,
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ArticleDetailScreen(post: post),
              ),
            );
            if (_tabIndex == 2) _loadSavedPosts();
          },
        );
      },
    );
  }

  /// 错误提示卡片
  Widget _buildErrorCard() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '无法加载内容',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(_error!),
              const SizedBox(height: 8),
              ..._buildErrorTips(),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (_apiError?.canRetry ?? true)
                    FilledButton(
                      onPressed: _loadInitial,
                      child: const Text('重试'),
                    ),
                  if (_apiError?.showConfigEntry ?? false)
                    OutlinedButton.icon(
                      onPressed: _showConfigHelpDialog,
                      icon: const Icon(Icons.settings_outlined),
                      label: const Text('站点配置帮助'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 错误提示信息
  List<Widget> _buildErrorTips() {
    final tips = <String>[];
    if (_apiError?.type == ContentApiErrorType.network) {
      tips.add('检查网络连接，确认当前设备可访问互联网。');
      tips.add('确认你的站点可以在浏览器中正常打开。');
    } else if (_apiError?.type == ContentApiErrorType.config) {
      tips.add('检查站点地址是否正确配置。');
      tips.add('地址示例：https://blog.nishiki.icu');
    } else if (_apiError?.type == ContentApiErrorType.server) {
      tips.add('确认站点服务正常运行且 API 可访问。');
      tips.add('WordPress 站点请确认已启用 REST API。');
    } else {
      tips.add('请稍后重试，若持续失败可刷新页面或重启应用。');
    }
    return [
      ...tips.map(
        (tip) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2, right: 6),
                child: Icon(Icons.info_outline, size: 14),
              ),
              Expanded(
                child: Text(tip, style: Theme.of(context).textTheme.bodySmall),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  /// WordPress 配置帮助对话框
  void _showConfigHelpDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('WordPress 配置帮助'),
        content: SelectableText(
          '当前站点地址：${AppConfig.wordpressBaseUrl}\n\n'
          '请确保地址是你的 WordPress 根域名，然后重新运行：\n'
          'flutter run --dart-define=WP_BASE_URL=https://blog.nishiki.icu',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// Feed 骨架屏加载占位
  Widget _buildFeedSkeleton({required String sectionTitle, int count = 3}) {
    final cardColor = Theme.of(context).brightness == Brightness.dark
        ? AppTheme.cardDark
        : Colors.white;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(
            sectionTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        ...List.generate(count, (_) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                border: Border.all(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.45),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}
