import 'package:flutter/material.dart';

class SearchTabView extends StatelessWidget {
  const SearchTabView({
    super.key,
    required this.onRefresh,
    required this.onScrollNotification,
    required this.searchArea,
    required this.categoryArea,
    required this.recentSearches,
    required this.feed,
  });

  final Future<void> Function() onRefresh;
  final NotificationListenerCallback<ScrollNotification> onScrollNotification;
  final Widget searchArea;
  final Widget categoryArea;
  final Widget recentSearches;
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
            searchArea,
            categoryArea,
            recentSearches,
            feed,
          ],
        ),
      ),
    );
  }
}
