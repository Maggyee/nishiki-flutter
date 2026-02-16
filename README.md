# Nishiki Flutter WordPress App

A Flutter blog app connected to WordPress REST API.

## Features

- Home feed with article cards
- Search by keyword
- Category filters
- Recent searches
- Article detail reader
- Loading, empty, and error states
- Mobile-friendly bottom navigation

## Run

```bash
cd nishiki_flutter
flutter pub get
flutter run --dart-define=WP_BASE_URL=https://your-wordpress-site.com
```

Use your real WordPress site base URL (no trailing slash required).

Examples:
- `https://example.com`
- `https://blog.example.com`

## WordPress requirements

- WordPress REST API must be public at `/wp-json/wp/v2/`
- Posts and categories endpoints enabled
