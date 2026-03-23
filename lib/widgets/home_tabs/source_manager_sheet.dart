import 'package:flutter/material.dart';

import '../../services/blog_source_service.dart';

/// 站点与组合管理底部弹窗
class SourceManagerSheet {
  /// 显示站点管理底部弹窗
  static void show(BuildContext context) {
    final blogSource = BlogSourceService();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        // 合并所有需要监听的 ValueNotifier
        final mergedListenable = Listenable.merge([
          blogSource.sourceEntries,
          blogSource.groups,
          blogSource.mode,
          blogSource.selectedGroupId,
          blogSource.baseUrl,
        ]);

        return SafeArea(
          child: AnimatedBuilder(
            animation: mergedListenable,
            builder: (context, _) {
              final sources = blogSource.sourceEntries.value;
              final groups = blogSource.groups.value;
              final isAggregateMode =
                  blogSource.mode.value == BlogSourceMode.aggregate;

              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  8,
                  20,
                  24 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 标题
                    Text(
                      '站点与组合',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '当前范围：${blogSource.currentScopeLabel}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),

                    // 模式切换（单站点/聚合）
                    SegmentedButton<BlogSourceMode>(
                      segments: const [
                        ButtonSegment(
                          value: BlogSourceMode.single,
                          icon: Icon(Icons.language_rounded),
                          label: Text('单站点'),
                        ),
                        ButtonSegment(
                          value: BlogSourceMode.aggregate,
                          icon: Icon(Icons.hub_rounded),
                          label: Text('聚合'),
                        ),
                      ],
                      selected: <BlogSourceMode>{blogSource.mode.value},
                      onSelectionChanged: (selection) async {
                        final nextMode = selection.first;
                        if (nextMode == BlogSourceMode.aggregate &&
                            sources.length <= 1) {
                          _showToast(context, '至少添加两个站点后才能启用聚合');
                          return;
                        }
                        await blogSource.setMode(nextMode);
                      },
                    ),

                    const SizedBox(height: 20),
                    Text('站点', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),

                    // 站点列表
                    ...sources.map((source) => _buildSourceListTile(
                          context, source, blogSource, isAggregateMode)),
                    const SizedBox(height: 12),

                    // 添加站点按钮
                    FilledButton.icon(
                      onPressed: () => _showAddSourceDialog(context, blogSource),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('添加站点'),
                    ),

                    const SizedBox(height: 20),
                    Text('组合', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),

                    // 全部站点聚合选项
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        isAggregateMode &&
                                blogSource.selectedGroupId.value == null
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      title: const Text('全部站点聚合'),
                      subtitle: Text('包含 ${sources.length} 个站点'),
                    ),

                    // 组合列表
                    ...groups.map((group) =>
                        _buildGroupListTile(context, group, blogSource, isAggregateMode)),
                    const SizedBox(height: 12),

                    // 创建组合按钮
                    OutlinedButton.icon(
                      onPressed: sources.length < 2
                          ? null
                          : () => _showGroupDialog(context, blogSource),
                      icon: const Icon(Icons.collections_bookmark_rounded),
                      label: const Text('创建站点组合'),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// 站点列表项
  static Widget _buildSourceListTile(
    BuildContext context,
    BlogSiteSource source,
    BlogSourceService blogSource,
    bool isAggregateMode,
  ) {
    final selected =
        !isAggregateMode && blogSource.currentSource == source.baseUrl;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected
            ? Icons.check_circle_rounded
            : Icons.radio_button_unchecked_rounded,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(source.name),
      subtitle: Text(source.hostLabel),
      trailing: PopupMenuButton<String>(
        onSelected: (value) async {
          if (value == 'rename') {
            await _showRenameSourceDialog(context, source, blogSource);
            return;
          }
          if (value == 'delete') {
            try {
              await blogSource.removeSource(source.baseUrl);
            } catch (error) {
              _showToast(context, error.toString());
            }
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'rename', child: Text('重命名')),
          PopupMenuItem(value: 'delete', child: Text('删除')),
        ],
      ),
      onTap: () async {
        await blogSource.selectSource(source.baseUrl);
      },
    );
  }

  /// 组合列表项
  static Widget _buildGroupListTile(
    BuildContext context,
    BlogSiteGroup group,
    BlogSourceService blogSource,
    bool isAggregateMode,
  ) {
    final selected =
        isAggregateMode && blogSource.selectedGroupId.value == group.id;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected
            ? Icons.check_circle_rounded
            : Icons.radio_button_unchecked_rounded,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(group.name),
      subtitle: Text(
        group.sourceBaseUrls.map(blogSource.labelForSource).join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) async {
          if (value == 'edit') {
            await _showGroupDialog(context, blogSource, group: group);
            return;
          }
          if (value == 'delete') {
            await blogSource.deleteGroup(group.id);
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'edit', child: Text('编辑')),
          PopupMenuItem(value: 'delete', child: Text('删除')),
        ],
      ),
      onTap: () async {
        await blogSource.selectGroup(group.id);
      },
    );
  }

  /// 添加站点对话框
  static Future<void> _showAddSourceDialog(
    BuildContext context,
    BlogSourceService blogSource,
  ) async {
    final nameController = TextEditingController();
    final urlController = TextEditingController(text: 'https://');

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加站点'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: '站点名称'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(labelText: '站点地址'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await blogSource.addSource(
                  urlController.text,
                  name: nameController.text,
                );
                if (ctx.mounted) {
                  Navigator.of(ctx).pop();
                }
              } catch (error) {
                _showToast(context, error.toString());
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  /// 重命名站点对话框
  static Future<void> _showRenameSourceDialog(
    BuildContext context,
    BlogSiteSource source,
    BlogSourceService blogSource,
  ) async {
    final controller = TextEditingController(text: source.name);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名站点'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: '站点名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await blogSource.renameSource(source.baseUrl, controller.text);
                if (ctx.mounted) {
                  Navigator.of(ctx).pop();
                }
              } catch (error) {
                _showToast(context, error.toString());
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  /// 组合创建/编辑对话框
  static Future<void> _showGroupDialog(
    BuildContext context,
    BlogSourceService blogSource, {
    BlogSiteGroup? group,
  }) async {
    final nameController = TextEditingController(text: group?.name ?? '');
    final selectedSources = <String>{
      ...?group?.sourceBaseUrls,
      if (group == null && blogSource.sourceEntries.value.isNotEmpty)
        blogSource.sourceEntries.value.first.baseUrl,
    };

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(group == null ? '创建站点组合' : '编辑站点组合'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: '组合名称'),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '选择站点',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      ...blogSource.sourceEntries.value.map((source) {
                        final checked = selectedSources.contains(
                          source.baseUrl,
                        );
                        return CheckboxListTile(
                          value: checked,
                          contentPadding: EdgeInsets.zero,
                          title: Text(source.name),
                          subtitle: Text(source.hostLabel),
                          onChanged: (value) {
                            setDialogState(() {
                              if (value ?? false) {
                                selectedSources.add(source.baseUrl);
                              } else {
                                selectedSources.remove(source.baseUrl);
                              }
                            });
                          },
                        );
                      }),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () async {
                    try {
                      await blogSource.saveGroup(
                        id: group?.id,
                        name: nameController.text,
                        sourceBaseUrls: selectedSources.toList(),
                      );
                      if (ctx.mounted) {
                        Navigator.of(ctx).pop();
                      }
                    } catch (error) {
                      _showToast(context, error.toString());
                    }
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Toast 提示
  static void _showToast(BuildContext context, String message) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message.replaceFirst('FormatException: ', '')),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
