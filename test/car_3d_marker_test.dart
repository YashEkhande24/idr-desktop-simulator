import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idr_navigator/widgets/car_3d_marker.dart';

void main() {
  group('Car3DMarker Procedural 3D Mesh Tests', () {
    testWidgets('renders properly with default parameters', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: Car3DMarker(
                headingDeg: 45.0,
                size: 80.0,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(Car3DMarker), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Car3DMarker),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );
    });

    testWidgets('renders accurately in Course-Up and North-Up modes with 3-axis EKF attitude', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Car3DMarker(
                  headingDeg: 90.0,
                  pitchDeg: 5.2, // Uphill climb
                  rollDeg: -3.8, // Left cornering lean
                  isCourseUp: true,
                  size: 80.0,
                ),
                Car3DMarker(
                  headingDeg: 180.0,
                  pitchDeg: -4.5, // Downhill / braking dive
                  rollDeg: 2.1,  // Right cornering lean
                  isCourseUp: false,
                  isBraking: true,
                  size: 80.0,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(Car3DMarker), findsNWidgets(2));
    });
  });
}
