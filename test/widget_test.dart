import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nishiki_flutter/main.dart';
import 'package:nishiki_flutter/models/wp_models.dart';
import 'package:nishiki_flutter/screens/article_detail_screen.dart';
import 'package:nishiki_flutter/widgets/article_card.dart';

WpPost _samplePost() {
  return WpPost(
    sourceBaseUrl: 'https://example.com',
    id: 42,
    title: 'Widget Test Post',
    excerpt: 'Short excerpt for widget test',
    contentHtml: '<p>Sample content for detail view.</p>',
    author: 'Test Author',
    date: DateTime(2026, 2, 22),
    featuredImageUrl: null,
    categories: const ['Testing'],
    categoryIds: const [1],
    link: 'https://example.com/post/42',
    readMinutes: 1,
  );
}

Future<void> _pumpAppShell(WidgetTester tester) async {
  await tester.pumpWidget(const NishikiApp());
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('app boots with shell UI', (WidgetTester tester) async {
    await _pumpAppShell(tester);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(4));
  });

  testWidgets('switches to Search tab and shows search controls', (
    WidgetTester tester,
  ) async {
    await _pumpAppShell(tester);

    await tester.tap(find.byIcon(Icons.search_outlined));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(SearchBar), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
  });

  testWidgets('Saved empty state can navigate back to Home', (
    WidgetTester tester,
  ) async {
    await _pumpAppShell(tester);

    await tester.tap(find.byIcon(Icons.bookmark_outline));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byIcon(Icons.bookmark_outline_rounded), findsOneWidget);
    expect(find.byType(FilledButton), findsWidgets);

    await tester.tap(find.byType(FilledButton).first);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('Profile tab renders site-management entry', (
    WidgetTester tester,
  ) async {
    await _pumpAppShell(tester);

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.byIcon(Icons.hub_rounded), findsWidgets);
    expect(find.byIcon(Icons.info_outline_rounded), findsWidgets);
  });

  testWidgets('Article card tap opens detail and supports back navigation', (
    WidgetTester tester,
  ) async {
    final post = _samplePost();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: ArticleCard(
                post: post,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ArticleDetailScreen(post: post),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byType(InkWell).first);
    await tester.pumpAndSettle();

    expect(find.byType(ArticleDetailScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Back').first);
    await tester.pumpAndSettle();

    expect(find.byType(ArticleDetailScreen), findsNothing);
    expect(find.byType(ArticleCard), findsOneWidget);
  });

  testWidgets('Bookmark animation in detail page does not throw assertion', (
    WidgetTester tester,
  ) async {
    final post = _samplePost();

    await tester.pumpWidget(MaterialApp(home: ArticleDetailScreen(post: post)));

    await tester.pump(const Duration(milliseconds: 200));

    final bookmarkButton = find.byTooltip('Bookmark article');
    expect(bookmarkButton, findsOneWidget);

    await tester.tap(bookmarkButton);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
  });

  testWidgets('Edge swipe from left pops detail page', (
    WidgetTester tester,
  ) async {
    final post = _samplePost();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ArticleDetailScreen(post: post),
                      ),
                    );
                  },
                  child: const Text('Open detail'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open detail'));
    await tester.pumpAndSettle();
    expect(find.byType(ArticleDetailScreen), findsOneWidget);

    final gesture = await tester.startGesture(const Offset(6, 220));
    await gesture.moveBy(const Offset(140, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byType(ArticleDetailScreen), findsNothing);
    expect(find.text('Open detail'), findsOneWidget);
  });

  testWidgets('Swipe not started from left edge does not pop detail page', (
    WidgetTester tester,
  ) async {
    final post = _samplePost();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ArticleDetailScreen(post: post),
                      ),
                    );
                  },
                  child: const Text('Open detail'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open detail'));
    await tester.pumpAndSettle();
    expect(find.byType(ArticleDetailScreen), findsOneWidget);

    final gesture = await tester.startGesture(const Offset(120, 220));
    await gesture.moveBy(const Offset(170, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byType(ArticleDetailScreen), findsOneWidget);
  });
}
