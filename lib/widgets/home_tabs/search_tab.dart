import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/wp_models.dart';
import '../../theme/app_theme.dart';

/// 搜索 Tab — 搜索框 + 分类筛选 + 最近搜索 + 搜索结果
class SearchTab extends StatelessWidget {
  const SearchTab({
    super.key,
    required this.searchController,
    required this.categories,
    required this.recentSearches,
    required this.selectedCategoryId,
    required this.isAggregateMode,
    required this.onSearch,
    required this.onScheduleSearch,
    required this.onCategorySelected,
    required this.onBuildFeed,
  });

  // 搜索输入框控制器
  final TextEditingController searchController;
  // 分类列表
  final List<WpCategory> categories;
  // 最近搜索记录
  final List<String> recentSearches;
  // 选中的分类 ID
  final int? selectedCategoryId;
  // 是否聚合模式
  final bool isAggregateMode;
  // 执行搜索回调
  final Future<void> Function([String? forcedTerm]) onSearch;
  // 延迟搜索回调
  final void Function({String? forcedTerm, Duration delay}) onScheduleSearch;
  // 分类选择变化回调
  final ValueChanged<int?> onCategorySelected;
  // 构建文章列表的代理方法
  final Widget Function({required String sectionTitle, bool skipFirst}) onBuildFeed;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onSearch,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _buildSearchArea(context),
          _buildCategoryArea(context),
          _buildRecentSearches(context),
          onBuildFeed(sectionTitle: '搜索结果', skipFirst: false),
        ],
      ),
    );
  }

  /// 搜索框区域
  Widget _buildSearchArea(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: SearchBar(
        key: const ValueKey('home.search.entry'),
        controller: searchController,
        hintText: '搜索文章、话题或作者',
        leading: const Icon(Icons.search),
        trailing: [
          IconButton(
            key: const ValueKey('home.search.submit'),
            tooltip: '开始搜索',
            onPressed: () => onSearch(),
            icon: const Icon(Icons.arrow_forward),
          ),
        ],
        onSubmitted: (_) => onSearch(),
        onChanged: (_) => onScheduleSearch(),
      ),
    );
  }

  /// 分类筛选区域
  Widget _buildCategoryArea(BuildContext context) {
    // 聚合模式下不显示分类选择，因为不同站点的分类 ID 可能冲突
    if (isAggregateMode) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '聚合模式下暂不按分类筛选，避免不同站点分类 ID 冲突。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          // "全部"选项
          ChoiceChip(
            label: const Text('全部'),
            selected: selectedCategoryId == null,
            showCheckmark: true,
            checkmarkColor: AppTheme.primaryDark,
            labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: AppTheme.darkText,
              fontWeight: FontWeight.w700,
            ),
            selectedColor: Theme.of(context).colorScheme.primaryContainer,
            side: BorderSide(
              color: selectedCategoryId == null
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).dividerColor,
              width: selectedCategoryId == null ? 2 : 1,
            ),
            onSelected: (_) {
              onCategorySelected(null);
            },
          ),
          // 各分类选项
          ...categories.take(8).map((category) {
            final selected = selectedCategoryId == category.id;
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
                onCategorySelected(selected ? null : category.id);
              },
            );
          }),
        ],
      ),
    );
  }

  /// 最近搜索记录
  Widget _buildRecentSearches(BuildContext context) {
    if (recentSearches.isEmpty) {
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
            children: recentSearches.map((term) {
              return ActionChip(
                label: Text(term),
                onPressed: () {
                  searchController.text = term;
                  onScheduleSearch(forcedTerm: term, delay: Duration.zero);
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
