import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nishiki_flutter/main.dart';
import 'package:nishiki_flutter/models/wp_models.dart';
import 'package:nishiki_flutter/screens/article_detail_screen.dart';
import 'package:nishiki_flutter/widgets/article_card.dart';

WpPost _samplePost() {
  return WpPost(
    id: 42,
    title: 'Widget Test Post',
    excerpt: 'Short excerpt for widget test',
    contentHtml: '<p>Sample content for detail view.</p>',
    author: 'Test Author',
    date: DateTime(2026, 2, 22),
    featuredImageUrl: null,
    categories: const ['Testing'],
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
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
  });

  testWidgets('switches to Search tab and shows search controls',
      (WidgetTester tester) async {
    await _pumpAppShell(tester);

    await tester.tap(find.text('Search'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(SearchBar), findsOneWidget);
    expect(find.byTooltip('Run search'), findsOneWidget);
  });

  testWidgets('Saved empty state can navigate back to Home',
      (WidgetTester tester) async {
    await _pumpAppShell(tester);

    await tester.tap(find.text('Saved'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('暂无收藏文章'), findsOneWidget);
    expect(find.text('去发现文章'), findsOneWidget);

    await tester.tap(find.text('去发现文章'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Today Picks'), findsOneWidget);
  });

  testWidgets('Profile tab renders preference and feature sections',
      (WidgetTester tester) async {
    await _pumpAppShell(tester);

    await tester.tap(find.text('Profile'));
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.text('阅读偏好'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('功能'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('功能'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('关于'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('关于'), findsOneWidget);
  });

  testWidgets('Article card tap opens detail and supports back navigation',
      (WidgetTester tester) async {
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

  testWidgets('Bookmark animation in detail page does not throw assertion',
      (WidgetTester tester) async {
    final post = _samplePost();

    await tester.pumpWidget(
      MaterialApp(
        home: ArticleDetailScreen(post: post),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));

    final bookmarkButton = find.byTooltip('Bookmark article');
    expect(bookmarkButton, findsOneWidget);

    await tester.tap(bookmarkButton);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
  });
}
