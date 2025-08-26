import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speedbook_taxi/home_page.dart';

void main() {
  testWidgets('setCurrentLocation is called on timer tick', (tester) async {
    int callCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          locationUpdater: (lat, lng) async {
            callCount++;
          },
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 10));

    expect(callCount, greaterThan(0));
  });
}