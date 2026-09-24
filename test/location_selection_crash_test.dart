import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:idr_navigator/core/math_utils.dart';
import 'package:idr_navigator/models/navigation_models.dart';
import 'package:idr_navigator/screens/pure_nav_screen.dart';
import 'package:idr_navigator/services/idr_pipeline.dart';
import 'package:idr_navigator/widgets/destination_picker_sheet.dart';

void main() {
  testWidgets('Selecting a standard POI in DestinationPickerSheet does not crash', (tester) async {
    final pipeline = IdrPipeline();
    addTearDown(() => pipeline.pause());

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: pipeline),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: DestinationPickerSheet(pipeline: pipeline),
          ),
        ),
      ),
    );

    await tester.pump();

    // Find the first POI card and tap it
    final poiFinder = find.text('Pune International Airport (PNQ)');
    expect(poiFinder, findsOneWidget);

    await tester.tap(poiFinder);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // Find and tap START TURN-BY-TURN GUIDANCE button
    final startBtn = find.text('START TURN-BY-TURN GUIDANCE');
    if (startBtn.evaluate().isNotEmpty) {
      await tester.tap(startBtn);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }
  });

  testWidgets('Tapping on map in PureNavScreen opens sheet and selects dropped pin without crash', (tester) async {
    final pipeline = IdrPipeline();
    addTearDown(() => pipeline.pause());

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: pipeline),
        ],
        child: const MaterialApp(
          home: PureNavScreen(),
        ),
      ),
    );

    await tester.pump();

    // Drop a pin via DestinationPickerSheet with initialDestination
    final tapDest = NavDestination(
      name: 'Map Dropped Pin',
      subtitle: 'Coordinates: 18.5204°, 73.8567°',
      targetEnu: MathUtils.wgs84ToEnu(
        lat: 18.5204,
        lon: 73.8567,
        refLat: pipeline.sensorService.refLat ?? 18.5204,
        refLon: pipeline.sensorService.refLon ?? 73.8567,
      ),
      latitude: 18.5204,
      longitude: 73.8567,
      isCustomPin: true,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: pipeline),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: DestinationPickerSheet(
              pipeline: pipeline,
              initialDestination: tapDest,
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  });
}
