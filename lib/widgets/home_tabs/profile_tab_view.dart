import 'package:flutter/material.dart';

class ProfileTabView extends StatelessWidget {
  const ProfileTabView({
    super.key,
    required this.header,
    required this.stats,
    this.readingTitle,
    this.readingCard,
    required this.preferencesTitle,
    required this.preferencesCard,
    required this.featuresTitle,
    required this.featuresCard,
    required this.aboutTitle,
    required this.aboutCard,
    required this.footer,
  });

  final Widget header;
  final Widget stats;
  final Widget? readingTitle;
  final Widget? readingCard;
  final Widget preferencesTitle;
  final Widget preferencesCard;
  final Widget featuresTitle;
  final Widget featuresCard;
  final Widget aboutTitle;
  final Widget aboutCard;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        header,
        stats,
        ...?readingTitle == null ? null : [
          const SizedBox(height: 12),
          readingTitle!,
        ],
        ...?readingCard == null ? null : [readingCard!],
        const SizedBox(height: 12),
        preferencesTitle,
        preferencesCard,
        const SizedBox(height: 12),
        featuresTitle,
        featuresCard,
        const SizedBox(height: 12),
        aboutTitle,
        aboutCard,
        footer,
      ],
    );
  }
}
