import 'package:facedetectionapp/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('FaceDetectionApp initializes correctly', (WidgetTester tester) async {

    await tester.pumpWidget(FaceDetectionApp());

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
  });
}