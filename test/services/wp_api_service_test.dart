import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nishiki_flutter/services/wp_api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WpApiService', () {
    test('fetchPosts builds expected query and parses embedded post data', () async {
      late Uri requestedUri;
      final client = MockClient((request) async {
        requestedUri = request.url;
        return http.Response(
          jsonEncode([
            {
              'id': 101,
              'date': '2026-03-16T08:30:00',
              'link': 'https://example.com/posts/101',
              'title': {'rendered': 'Hello <em>World</em>'},
              'excerpt': {'rendered': '<p>Excerpt text</p>'},
              'content': {'rendered': '<p>Body text for reading time.</p>'},
              '_embedded': {
                'author': [
                  {'name': 'Nishiki'}
                ],
                'wp:featuredmedia': [
                  {
                    'media_details': {
                      'sizes': {
                        'medium': {'source_url': 'https://img.example.com/post.jpg'}
                      }
                    }
                  }
                ],
                'wp:term': [
                  [
                    {'taxonomy': 'category', 'name': 'Tech'},
                    {'taxonomy': 'post_tag', 'name': 'Ignore Me'}
                  ]
                ]
              }
            }
          ]),
          200,
        );
      });

      final service = WpApiService(client: client);
      final posts = await service.fetchPosts(search: 'flutter', categoryId: 9, page: 2);

      expect(requestedUri.path, '/wp-json/wp/v2/posts');
      expect(requestedUri.queryParameters['search'], 'flutter');
      expect(requestedUri.queryParameters['categories'], '9');
      expect(requestedUri.queryParameters['page'], '2');
      expect(requestedUri.queryParameters['_embed'], '1');

      expect(posts, hasLength(1));
      expect(posts.first.id, 101);
      expect(posts.first.title, 'Hello World');
      expect(posts.first.excerpt, 'Excerpt text');
      expect(posts.first.author, 'Nishiki');
      expect(posts.first.categories, ['Tech']);
      expect(posts.first.featuredImageUrl, 'https://img.example.com/post.jpg');
      expect(posts.first.link, 'https://example.com/posts/101');
      expect(posts.first.readMinutes, greaterThanOrEqualTo(1));
    });

    test('fetchCategories parses category list', () async {
      final service = WpApiService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode([
              {'id': 1, 'name': 'News'},
              {'id': 2, 'name': 'Design'}
            ]),
            200,
          ),
        ),
      );

      final categories = await service.fetchCategories();

      expect(categories, hasLength(2));
      expect(categories.first.id, 1);
      expect(categories.first.name, 'News');
      expect(categories.last.name, 'Design');
    });

    test('fetchPostById throws typed exception on 404', () async {
      final service = WpApiService(
        client: MockClient((_) async => http.Response('not found', 404)),
      );

      expect(
        () => service.fetchPostById(404),
        throwsA(
          isA<WpApiException>()
              .having((e) => e.type, 'type', WpApiErrorType.server)
              .having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });
  });
}
