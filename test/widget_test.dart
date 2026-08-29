// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:zikr/main.dart';

void main() {
  testWidgets('Zikr app opens and dhikr counter increments', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Ассаламу алейкум'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.touch_app_rounded));
    await tester.pump();
    expect(find.text('Субханаллах'), findsOneWidget);

    await tester.tap(find.byType(GestureDetector).first);
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
  });
}
