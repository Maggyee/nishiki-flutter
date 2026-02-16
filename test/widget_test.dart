import 'package:flutter_test/flutter_test.dart';

import 'package:nishiki_flutter/main.dart';

void main() {
  testWidgets('app boots with shell UI', (WidgetTester tester) async {
    await tester.pumpWidget(const NishikiApp());
    await tester.pump();

    expect(find.text('Nishiki Blog'), findsOneWidget);
  });
}
