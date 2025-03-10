import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/main.dart';

void main() {
  testWidgets('FaceDetectionApp initializes correctly', (WidgetTester tester) async {
    // Mock cameras list

    await tester.pumpWidget(FaceDetectionApp());

    // Ensure the app is rendered correctly
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
  });
}