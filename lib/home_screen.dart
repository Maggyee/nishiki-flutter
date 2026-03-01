import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models/wp_models.dart';
import 'services/wp_api_service.dart';
import 'services/bookmark_service.dart';
import 'services/settings_service.dart';
import 'widgets/article_card.dart';
import 'screens/article_detail_screen.dart';
import 'theme/app_theme.dart';
import 'config.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final _api = WpApiService();
  final _searchController = TextEditingController();
  final _bookmarkService = BookmarkService();
  final _settings = SettingsService();

  List<WpPost> _posts = const [];
  List<WpCategory> _categories = const [];
  final List<String> _recentSearches = [];
  bool _categoriesLoading = false;

  // 收藏的文章列表
  List<WpPost> _savedPosts = const [];
  bool _savedLoading = false;

  bool _loading = true;
  String? _error;
  WpApiException? _apiError;

  // ===== Profile 页面动画控制器 =====
  late AnimationController _avatarPulseCtrl;    // 头像呼吸脉冲
  late AnimationController _profileEnterCtrl;   // 入场动画
  late Animation<double> _avatarPulseAnim;      // 脉冲缩放动画
  int _tabIndex = 0;
  int? _selectedCategoryId;
  Timer? _searchDebounce;
  int _searchRequestId = 0;

  @override
  void initState() {
    super.initState();
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
    _searchController.dispose();
    _avatarPulseCtrl.dispose();
    _profileEnterCtrl.dispose();
    super.dispose();
  }

  void _scheduleSearch({String? forcedTerm, Duration delay = const Duration(milliseconds: 280)}) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(delay, () {
      _search(forcedTerm);
    });
  }

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

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
      _apiError = null;
    });

    try {
      setState(() {
        _posts = const [];
      });

      final posts = await _api.fetchPosts();
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        if (e is WpApiException) {
          _apiError = e;
          _error = e.userMessage;
        } else {
          _error = e.toString();
        }
        _loading = false;
      });
    }
  }

  Future<void> _loadCategoriesIfNeeded() async {
    if (_categoriesLoading || _categories.isNotEmpty) return;
    _categoriesLoading = true;
    try {
      final categories = await _api.fetchCategories();
      if (!mounted) return;
      setState(() {
        _categories = categories;
      });
    } catch (_) {
      // Keep search usable even if categories fail to load.
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
          _savedPosts = savedData.map((data) => WpPost.fromSummaryMap(data)).toList();
          _savedLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _savedLoading = false);
    }
  }

  Future<void> _search([String? forcedTerm]) async {
    final term = (forcedTerm ?? _searchController.text).trim();
    final requestId = ++_searchRequestId;

    if (term.isEmpty && _selectedCategoryId == null) {
      await _loadInitial();
      return;
    }

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

      if (!mounted || requestId != _searchRequestId) {
        return;
      }

      setState(() {
        _posts = posts;
        _loading = false;
      });

      if (term.isNotEmpty) {
        _recentSearches.remove(term);
        _recentSearches.insert(0, term);
        if (_recentSearches.length > 5) {
          _recentSearches.removeLast();
        }
      }
    } catch (e) {
      if (!mounted || requestId != _searchRequestId) {
        return;
      }

      setState(() {
        if (e is WpApiException) {
          _apiError = e;
          _error = e.userMessage;
        } else {
          _error = e.toString();
        }
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = switch (_tabIndex) {
      0 => _buildHomeTab(),
      1 => _buildSearchTab(),
      2 => _buildSavedTab(),
      _ => _buildProfileTab(),
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
      body: body,
      bottomNavigationBar: TooltipVisibility(
        visible: false,
        child: NavigationBar(
          selectedIndex: _tabIndex,
          onDestinationSelected: (value) {
            if (_tabIndex == value) return;
            setState(() => _tabIndex = value);
            _syncProfilePulseForTab(value);
            // 切换到收藏 tab 时自动刷新数据
            if (value == 2) _loadSavedPosts();
            // 切换到搜索 tab 时懒加载分类，提升首页首屏速度
            if (value == 1) _loadCategoriesIfNeeded();
            // 切换到 Profile 时播放一次入场动画
            if (value == 3) {
              _profileEnterCtrl.forward(from: 0.0);
            }
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: '首页',
            ),
            NavigationDestination(
              icon: Icon(Icons.search_outlined),
              selectedIcon: Icon(Icons.search),
              label: '搜索',
            ),
            NavigationDestination(
              icon: Icon(Icons.bookmark_outline),
              selectedIcon: Icon(Icons.bookmark),
              label: '收藏',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: '我的',
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 首页 Tab ====================
  Widget _buildHomeTab() {
    return RefreshIndicator(
      onRefresh: _loadInitial,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(
              '今日精选',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '来自你 WordPress 站点的最新文章',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          _buildHomeHero(),
          _buildFeed(sectionTitle: '热门推荐', skipFirst: true),
        ],
      ),
    );
  }

  Widget _buildHomeHero() {
    if (_loading) {
      return _buildHeroSkeleton();
    }
    if (_error != null || _posts.isEmpty) {
      return const SizedBox.shrink();
    }

    final featured = _posts.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Text(
            '精选推荐',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        HeroArticleCard(
          post: featured,
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ArticleDetailScreen(post: featured)),
            );
          },
        ),
      ],
    );
  }

  // ==================== 搜索 Tab ====================
  Widget _buildSearchTab() {
    return RefreshIndicator(
      onRefresh: _search,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _buildSearchArea(),
          _buildCategoryArea(),
          _buildRecentSearches(),
          _buildFeed(sectionTitle: '搜索结果'),
        ],
      ),
    );
  }

  Widget _buildSearchArea() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: SearchBar(
        controller: _searchController,
        hintText: '搜索文章、话题或作者',
        leading: const Icon(Icons.search),
        trailing: [
          IconButton(
            tooltip: '开始搜索',
            onPressed: _search,
            icon: const Icon(Icons.arrow_forward),
          ),
        ],
        onSubmitted: (_) => _search(),
        onChanged: (_) => _scheduleSearch(),
      ),
    );
  }

  Widget _buildCategoryArea() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ChoiceChip(
            label: const Text('全部'),
            selected: _selectedCategoryId == null,
            showCheckmark: true,
            checkmarkColor: AppTheme.primaryDark,
            labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: AppTheme.darkText,
              fontWeight: FontWeight.w700,
            ),
            selectedColor: Theme.of(context).colorScheme.primaryContainer,
            side: BorderSide(
              color: _selectedCategoryId == null
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).dividerColor,
              width: _selectedCategoryId == null ? 2 : 1,
            ),
            onSelected: (_) {
              setState(() => _selectedCategoryId = null);
              _scheduleSearch(delay: Duration.zero);
            },
          ),
          ..._categories.take(8).map((category) {
            final selected = _selectedCategoryId == category.id;
            return ChoiceChip(
              label: Text(category.name),
              selected: selected,
              showCheckmark: true,
              checkmarkColor: AppTheme.primaryDark,
              labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppTheme.darkText,
                fontWeight: FontWeight.w700,
              ),
              selectedColor: Theme.of(context).colorScheme.primaryContainer,
              side: BorderSide(
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).dividerColor,
                width: selected ? 2 : 1,
              ),
              onSelected: (_) {
                setState(() => _selectedCategoryId = selected ? null : category.id);
                _scheduleSearch(delay: Duration.zero);
              },
            );
          }),
        ],
      ),
    );
  }

  Widget _buildRecentSearches() {
    if (_recentSearches.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('最近搜索', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _recentSearches.map((term) {
              return ActionChip(
                label: Text(term),
                onPressed: () {
                  _searchController.text = term;
                  _scheduleSearch(forcedTerm: term, delay: Duration.zero);
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ==================== 文章 Feed 列表 ====================
  Widget _buildFeed({required String sectionTitle, bool skipFirst = false}) {
    if (_loading) {
      return _buildFeedSkeleton(sectionTitle: sectionTitle);
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('无法加载内容', style: TextStyle(fontWeight: FontWeight.w700)),
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

    final displayPosts =
        skipFirst && _posts.length > 1 ? _posts.skip(1).toList() : _posts;

    if (displayPosts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text('没有找到匹配的文章，请尝试其他关键词或分类。'),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: displayPosts.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(sectionTitle, style: Theme.of(context).textTheme.titleMedium),
          );
        }

        final post = displayPosts[index - 1];
        return ArticleCard(
          post: post,
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ArticleDetailScreen(post: post)),
            );
            if (_tabIndex == 2) _loadSavedPosts();
          },
        );
      },
    );
  }

  Widget _buildHeroSkeleton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        height: 220,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          color: Theme.of(context).brightness == Brightness.dark
              ? AppTheme.cardDark
              : Colors.white,
          border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }

  Widget _buildFeedSkeleton({required String sectionTitle, int count = 3}) {
    final cardColor = Theme.of(context).brightness == Brightness.dark
        ? AppTheme.cardDark
        : Colors.white;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(sectionTitle, style: Theme.of(context).textTheme.titleMedium),
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

  List<Widget> _buildErrorTips() {
    final tips = <String>[];

    if (_apiError?.type == WpApiErrorType.network) {
      tips.add('检查网络连接，确认当前设备可访问互联网。');
      tips.add('确认你的站点可以在浏览器中正常打开。');
    } else if (_apiError?.type == WpApiErrorType.config) {
      tips.add('检查 WP_BASE_URL 是否指向你的 WordPress 根域名。');
      tips.add('地址示例：https://blog.nishiki.icu');
    } else if (_apiError?.type == WpApiErrorType.server) {
      tips.add('确认 WordPress 已启用 REST API 并允许匿名读取文章。');
      tips.add('如果使用安全插件，请放行 /wp-json/wp/v2/*。');
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
              Expanded(child: Text(tip, style: Theme.of(context).textTheme.bodySmall)),
            ],
          ),
        ),
      ),
    ];
  }

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

  // ==================== 收藏 Tab ====================
  Widget _buildSavedTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 加载中
    if (_savedLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // 空状态 — 精美引导页
    if (_savedPosts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppTheme.primaryColor.withValues(alpha: 0.15)
                      : AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(
                  Icons.bookmark_outline_rounded,
                  size: 56,
                  color: AppTheme.primaryColor,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                '暂无收藏文章',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppTheme.darkModeText : AppTheme.darkText,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '在文章详情页点击书签图标 🔖\n即可将喜欢的文章收藏到这里',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: isDark ? AppTheme.darkModeSecondary : AppTheme.lightText,
                ),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: () => _goToTab(0),
                icon: const Icon(Icons.explore_outlined, size: 18),
                label: const Text('去发现文章'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 有收藏内容
    return RefreshIndicator(
      onRefresh: _loadSavedPosts,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: _savedPosts.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '我的收藏',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: isDark ? AppTheme.darkModeText : AppTheme.darkText,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '共 ${_savedPosts.length} 篇文章',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? AppTheme.darkModeSecondary : AppTheme.lightText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_savedPosts.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => _showClearSavedDialog(),
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text('清空'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        textStyle: const TextStyle(fontSize: 13),
                      ),
                    ),
                ],
              ),
            );
          }

          if (index == 1) {
            return const SizedBox(height: 8);
          }

          final post = _savedPosts[index - 2];
          return _buildSavedCard(post, isDark);
        },
      ),
    );
  }

  /// 收藏卡片 — 支持滑动取消收藏
  Widget _buildSavedCard(WpPost post, bool isDark) {
    return Dismissible(
      key: ValueKey('saved_${post.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 24),
            SizedBox(height: 4),
            Text('取消收藏', style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      confirmDismiss: (direction) async {
        await _bookmarkService.toggleSave(post.id);
        return true;
      },
      onDismissed: (_) {
        setState(() {
          _savedPosts = _savedPosts.where((p) => p.id != post.id).toList();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已取消收藏：${post.title}'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            action: SnackBarAction(
              label: '撤销',
              onPressed: () async {
                await _bookmarkService.toggleSave(post.id, postData: post.toSummaryMap());
                _loadSavedPosts();
              },
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Material(
          color: isDark ? AppTheme.cardDark : AppTheme.cardLight,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            onTap: () async {
              if (post.contentHtml.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('加载文章内容中...'),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    duration: const Duration(seconds: 1),
                  ),
                );
                try {
                  final freshPost = await _api.fetchPostById(post.id);
                  if (freshPost != null && mounted) {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ArticleDetailScreen(post: freshPost)),
                    );
                    _loadSavedPosts();
                  }
                } catch (_) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('无法加载文章，请检查网络连接'),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    );
                  }
                }
              } else {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ArticleDetailScreen(post: post)),
                );
                _loadSavedPosts();
              }
            },
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                boxShadow: isDark ? null : AppTheme.softShadow,
              ),
              child: Row(
                children: [
                  // 左侧缩略图
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: post.featuredImageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: post.featuredImageUrl!,
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                            memCacheWidth: 160,
                            memCacheHeight: 160,
                            maxWidthDiskCache: 320,
                            fadeInDuration: const Duration(milliseconds: 120),
                            placeholder: (context, url) => Container(
                              width: 80,
                              height: 80,
                              color: isDark ? AppTheme.surfaceDark : AppTheme.dividerColor,
                            ),
                            errorWidget: (context, url, error) => Container(
                              width: 80,
                              height: 80,
                              color: AppTheme.primaryLight,
                              child: const Icon(Icons.image_outlined, color: AppTheme.primaryColor),
                            ),
                          )
                        : Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              gradient: AppTheme.heroGradient,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(
                              child: Text(
                                post.title.isNotEmpty ? post.title[0] : '?',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (post.categories.isNotEmpty)
                          Text(
                            post.categories.first.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        if (post.categories.isNotEmpty)
                          const SizedBox(height: 4),
                        Text(
                          post.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text(
                              post.author,
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? AppTheme.darkModeSecondary : AppTheme.lightText,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: Container(
                                width: 3, height: 3,
                                decoration: const BoxDecoration(
                                  color: AppTheme.lightText,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            Text(
                              _formatDate(post.date),
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? AppTheme.darkModeSecondary : AppTheme.lightText,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(Icons.bookmark_rounded, color: AppTheme.primaryColor, size: 22),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 清空收藏确认对话框
  void _showClearSavedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空收藏？'),
        content: const Text('确定要清空所有收藏的文章吗？此操作不可撤销。'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              for (final post in _savedPosts) {
                await _bookmarkService.toggleSave(post.id);
              }
              _loadSavedPosts();
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }

  // ==================== Profile Tab（完整实现 + 交互动画） ====================
  Widget _buildProfileTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final likedCount = _bookmarkService.likedCount;
    final savedCount = _bookmarkService.savedCount;
    final readCount = _settings.readCount;

    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        // ===== 顶部渐变 Header 区域（带入场动画） =====
        _buildAnimatedEntry(
          delay: 0.0,
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: AppTheme.heroGradient,
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                // 用户头像 — 呼吸脉冲动画
                AnimatedBuilder(
                  animation: _avatarPulseAnim,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _avatarPulseAnim.value,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.2),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3 + 0.2 * (_avatarPulseAnim.value - 1.0) / 0.08),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.1 + 0.15 * (_avatarPulseAnim.value - 1.0) / 0.08),
                              blurRadius: 16 * _avatarPulseAnim.value,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(Icons.person_rounded, size: 36, color: Colors.white),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 14),
                // 名称
                const Text(
                  '阅读者',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  AppConfig.wordpressBaseUrl.replaceFirst('https://', '').replaceFirst('http://', ''),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),

        // ===== 阅读统计卡片（带入场动画） =====
        _buildAnimatedEntry(
          delay: 0.1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.cardDark : AppTheme.cardLight,
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                boxShadow: isDark ? null : AppTheme.softShadow,
              ),
              child: Row(
                children: [
                  // 已读（带计数动画）
                  _buildAnimatedStatItem(
                    icon: Icons.auto_stories_rounded,
                    label: '已读',
                    count: readCount,
                    color: const Color(0xFF6FAEEB),
                    isDark: isDark,
                  ),
                  // 分隔线
                  Container(width: 1, height: 40, color: isDark ? AppTheme.surfaceDark : AppTheme.dividerColor),
                  // 收藏
                  _buildAnimatedStatItem(
                    icon: Icons.bookmark_rounded,
                    label: '收藏',
                    count: savedCount,
                    color: const Color(0xFFFFB347),
                    isDark: isDark,
                  ),
                  // 分隔线
                  Container(width: 1, height: 40, color: isDark ? AppTheme.surfaceDark : AppTheme.dividerColor),
                  // 点赞
                  _buildAnimatedStatItem(
                    icon: Icons.favorite_rounded,
                    label: '点赞',
                    count: likedCount,
                    color: const Color(0xFFFF6B8A),
                    isDark: isDark,
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // ===== 设置区域标题（滑入动画） =====
        _buildAnimatedEntry(
          delay: 0.2,
          slideOffset: const Offset(-0.1, 0), // 从左侧滑入
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Text(
              '阅读偏好',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: isDark ? AppTheme.darkModeSecondary : AppTheme.lightText,
              ),
            ),
          ),
        ),

        // ===== 设置项列表（带入场） =====
        _buildAnimatedEntry(
          delay: 0.25,
          child: _buildSettingsCard(isDark, [
            // 🌓 深色模式切换
            _SettingsTile(
              icon: _settings.themeModeIcon,
              iconColor: const Color(0xFF8B5CF6),
              title: '外观模式',
              subtitle: _settings.themeModeName,
              trailing: _buildThemeModeChip(isDark),
              onTap: () async {
                HapticFeedback.mediumImpact(); // 触觉反馈
                await _settings.cycleThemeMode();
                setState(() {});
              },
            ),

            // 🔤 字体大小
            _SettingsTile(
              icon: Icons.text_fields_rounded,
              iconColor: const Color(0xFF3B82F6),
              title: '阅读字体',
              subtitle: _settings.fontScaleName,
              trailing: _buildFontScaleSlider(isDark),
              onTap: null,
            ),
          ]),
        ),

        const SizedBox(height: 12),

        // ===== 功能区域（滑入动画） =====
        _buildAnimatedEntry(
          delay: 0.35,
          slideOffset: const Offset(-0.1, 0),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Text(
              '功能',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: isDark ? AppTheme.darkModeSecondary : AppTheme.lightText,
              ),
            ),
          ),
        ),

        _buildAnimatedEntry(
          delay: 0.4,
          child: _buildSettingsCard(isDark, [
            // 🌐 访问博客
            _SettingsTile(
              icon: Icons.language_rounded,
              iconColor: const Color(0xFF10B981),
              title: '访问博客网站',
              subtitle: AppConfig.wordpressBaseUrl.replaceFirst('https://', ''),
              onTap: () async {
                HapticFeedback.lightImpact();
                final url = Uri.parse(AppConfig.wordpressBaseUrl);
                try {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                } catch (_) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('无法打开浏览器'),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    );
                  }
                }
              },
            ),

            // 🗑️ 清除缓存
            _SettingsTile(
              icon: Icons.cleaning_services_rounded,
              iconColor: const Color(0xFFF59E0B),
              title: '清除缓存',
              subtitle: '清除文章缓存和图片缓存',
              onTap: () {
                HapticFeedback.lightImpact();
                _showClearCacheDialog(isDark);
              },
            ),

            // 🗑️ 重置全部
            _SettingsTile(
              icon: Icons.restart_alt_rounded,
              iconColor: const Color(0xFFEF4444),
              title: '重置所有数据',
              subtitle: '清除收藏、点赞和设置',
              onTap: () {
                HapticFeedback.heavyImpact();
                _showResetDialog(isDark);
              },
            ),
          ]),
        ),

        const SizedBox(height: 12),

        // ===== 关于区域（滑入动画） =====
        _buildAnimatedEntry(
          delay: 0.5,
          slideOffset: const Offset(-0.1, 0),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Text(
              '关于',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: isDark ? AppTheme.darkModeSecondary : AppTheme.lightText,
              ),
            ),
          ),
        ),

        _buildAnimatedEntry(
          delay: 0.55,
          child: _buildSettingsCard(isDark, [
            _SettingsTile(
              icon: Icons.info_outline_rounded,
              iconColor: const Color(0xFF6366F1),
              title: '关于 Nishiki Blog',
              subtitle: 'v1.0.0 · Flutter 构建',
              onTap: () {
                HapticFeedback.lightImpact();
                _showAboutDialog(isDark);
              },
            ),
          ]),
        ),

        // 底部 App 版本标注（淡入动画）
        _buildAnimatedEntry(
          delay: 0.65,
          child: Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Center(
              child: Text(
                'Nishiki 用 💙 制作',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppTheme.darkModeSecondary.withValues(alpha: 0.6) : AppTheme.lightText.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 统计数据单项（带计数动画 + 点击弹跳）
  Widget _buildAnimatedStatItem({
    required IconData icon,
    required String label,
    required int count,
    required Color color,
    required bool isDark,
  }) {
    return Expanded(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: count.toDouble()),
        duration: const Duration(milliseconds: 1200),
        curve: Curves.easeOutCubic,
        builder: (context, animatedCount, child) {
          return Column(
            children: [
              // 彩色图标
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(height: 10),
              // 计数动画数字
              Text(
                '${animatedCount.toInt()}',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: isDark ? AppTheme.darkModeText : AppTheme.darkText,
                ),
              ),
              const SizedBox(height: 2),
              // 标签
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppTheme.darkModeSecondary : AppTheme.lightText,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 通用入场动画包装器（淡入 + 上滑/侧滑）
  Widget _buildAnimatedEntry({
    required double delay,
    required Widget child,
    Offset slideOffset = const Offset(0, 0.05), // 默认从下方轻微滑入
  }) {
    // 计算该元素的区间动画（带延迟的交错效果）
    final begin = delay;
    final end = (delay + 0.4).clamp(0.0, 1.0);

    return AnimatedBuilder(
      animation: _profileEnterCtrl,
      builder: (context, _) {
        final curvedValue = Curves.easeOutCubic.transform(
          ((_profileEnterCtrl.value - begin) / (end - begin)).clamp(0.0, 1.0),
        );
        return Opacity(
          opacity: curvedValue,
          child: FractionalTranslation(
            translation: Offset(
              slideOffset.dx * (1 - curvedValue),
              slideOffset.dy * (1 - curvedValue),
            ),
            child: child,
          ),
        );
      },
    );
  }

  /// 构建设置卡片容器（包含多个设置项）
  Widget _buildSettingsCard(bool isDark, List<_SettingsTile> tiles) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppTheme.cardDark : AppTheme.cardLight,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          boxShadow: isDark ? null : AppTheme.softShadow,
        ),
        child: Column(
          children: [
            for (int i = 0; i < tiles.length; i++) ...[
              _buildSettingsTileWidget(tiles[i], isDark),
              if (i < tiles.length - 1)
                Padding(
                  padding: const EdgeInsets.only(left: 60),
                  child: Divider(
                    height: 1,
                    color: isDark ? AppTheme.surfaceDark : AppTheme.dividerColor,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// 渲染单个设置项 Widget（带按压缩放反馈）
  Widget _buildSettingsTileWidget(_SettingsTile tile, bool isDark) {
    return _PressableScale(
      onTap: tile.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // 彩色图标容器
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: tile.iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(tile.icon, size: 20, color: tile.iconColor),
            ),
            const SizedBox(width: 14),
            // 标题和副标题
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tile.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppTheme.darkModeText : AppTheme.darkText,
                    ),
                  ),
                  if (tile.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      tile.subtitle!,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? AppTheme.darkModeSecondary : AppTheme.lightText,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // 右侧内容（自定义 trailing 或默认箭头）
            if (tile.trailing != null)
              tile.trailing!
            else if (tile.onTap != null)
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: isDark ? AppTheme.darkModeSecondary : AppTheme.lightText,
              ),
          ],
        ),
      ),
    );
  }

  /// 主题模式切换 Chip（带旋转过渡动画）
  Widget _buildThemeModeChip(bool isDark) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: animation, child: child),
        );
      },
      child: Container(
        key: ValueKey(_settings.themeModeName), // 切换时触发动画
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isDark
              ? AppTheme.primaryColor.withValues(alpha: 0.15)
              : AppTheme.primaryLight,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_settings.themeModeIcon, size: 14, color: AppTheme.primaryColor),
            const SizedBox(width: 4),
            Text(
              _settings.themeModeName,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 字体大小滑块（带触觉反馈 + 字号预览动画）
  Widget _buildFontScaleSlider(bool isDark) {
    return SizedBox(
      width: 130,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 左侧小 A — 根据当前值动态缩放
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              fontSize: 11 * (_settings.fontScale.value < 1.0 ? 1.1 : 0.9),
              fontWeight: FontWeight.w600,
              color: _settings.fontScale.value <= 0.9
                  ? AppTheme.primaryColor
                  : (isDark ? AppTheme.darkModeText : AppTheme.darkText),
            ),
            child: const Text('A'),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                activeTrackColor: AppTheme.primaryColor,
                inactiveTrackColor: isDark ? AppTheme.surfaceDark : AppTheme.dividerColor,
                thumbColor: AppTheme.primaryColor,
                overlayColor: AppTheme.primaryColor.withValues(alpha: 0.1),
              ),
              child: Slider(
                value: _settings.fontScale.value,
                min: 0.8,
                max: 1.4,
                divisions: 3,
                onChanged: (value) async {
                  // 只在到达刻度点时触发触觉反馈
                  final oldStep = (_settings.fontScale.value * 5).round();
                  final newStep = (value * 5).round();
                  if (oldStep != newStep) {
                    HapticFeedback.selectionClick();
                  }
                  await _settings.setFontScale(value);
                  setState(() {});
                },
              ),
            ),
          ),
          // 右侧大 A — 根据当前值动态缩放
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              fontSize: 16 * (_settings.fontScale.value > 1.2 ? 1.1 : 0.9),
              fontWeight: FontWeight.w700,
              color: _settings.fontScale.value >= 1.3
                  ? AppTheme.primaryColor
                  : (isDark ? AppTheme.darkModeText : AppTheme.darkText),
            ),
            child: const Text('A'),
          ),
        ],
      ),
    );
  }

  /// 清除缓存对话框
  void _showClearCacheDialog(bool isDark) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除缓存？'),
        content: const Text('将清除文章缓存和图片缓存。你的收藏和点赞数据不会受到影响。'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('✅ 缓存已清除'),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              );
            },
            child: const Text('清除'),
          ),
        ],
      ),
    );
  }

  /// 重置全部数据对话框
  void _showResetDialog(bool isDark) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('⚠️ 重置所有数据？'),
        content: const Text(
          '这将清除你的所有收藏、点赞、阅读记录和设置。\n\n此操作不可逆！',
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _settings.clearAllData();
              await _bookmarkService.init(); // 重新初始化（空数据）
              if (mounted) {
                setState(() {
                  _savedPosts = const [];
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('✅ 所有数据已重置'),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                );
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('确认重置'),
          ),
        ],
      ),
    );
  }

  /// 关于应用对话框
  void _showAboutDialog(bool isDark) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            // App Icon
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: AppTheme.heroGradient,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryColor.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Center(
                child: Text(
                  'N',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Nishiki Blog',
              style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'v1.0.0',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? AppTheme.darkModeSecondary : AppTheme.lightText,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '一个精致的 WordPress 博客阅读器，\n使用 Flutter 构建。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: isDark ? AppTheme.darkModeSecondary : AppTheme.mediumText,
              ),
            ),
            const SizedBox(height: 20),
            // 技术栈标签
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                _buildTechChip('Flutter', isDark),
                _buildTechChip('WordPress API', isDark),
                _buildTechChip('Material 3', isDark),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
        actions: [
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
          ),
        ],
      ),
    );
  }

  /// 技术栈标签 Chip
  Widget _buildTechChip(String label, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? AppTheme.primaryColor.withValues(alpha: 0.12)
            : AppTheme.primaryLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppTheme.primaryColor,
        ),
      ),
    );
  }

  void _goToTab(int tabIndex) {
    setState(() => _tabIndex = tabIndex);
    _syncProfilePulseForTab(tabIndex);
  }
}

/// 设置项数据模型
class _SettingsTile {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });
}

/// 格式化日期为 "Feb 16" 格式
String _formatDate(DateTime date) {
  return '${date.month}月${date.day}日';
}

/// ================================================================
/// 按压缩放反馈组件 — 按下时轻微缩小，松开后弹回
/// 提供类似 iOS 原生的触摸反馈体验
/// ================================================================
class _PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _PressableScale({required this.child, this.onTap});

  @override
  State<_PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<_PressableScale>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 200),
    );
    // 按下缩小到 0.97，松开恢复 1.0
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 如果没有 onTap，不添加手势交互
    if (widget.onTap == null) {
      return widget.child;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _ctrl.forward(),   // 按下 → 缩小
      onTapUp: (_) {
        _ctrl.reverse();                    // 松开 → 恢复
        widget.onTap?.call();
      },
      onTapCancel: () => _ctrl.reverse(),   // 取消 → 恢复
      child: AnimatedBuilder(
        animation: _scaleAnim,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnim.value,
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}
