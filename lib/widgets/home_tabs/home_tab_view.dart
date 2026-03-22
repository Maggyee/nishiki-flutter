import 'package:flutter/material.dart';

class HomeTabView extends StatelessWidget {
  const HomeTabView({
    super.key,
    required this.onRefresh,
    required this.onScrollNotification,
    required this.hero,
    required this.feed,
  });

  final Future<void> Function() onRefresh;
  final NotificationListenerCallback<ScrollNotification> onScrollNotification;
  final Widget hero;
  final Widget feed;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: onScrollNotification,
      child: RefreshIndicator(
        onRefresh: onRefresh,
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
            hero,
            feed,
          ],
        ),
      ),
    );
  }
}
