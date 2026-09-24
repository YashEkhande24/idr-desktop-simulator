import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:idr_navigator/main.dart';
import 'package:idr_navigator/screens/pure_nav_screen.dart';
import 'package:idr_navigator/services/idr_pipeline.dart';

void main() {
  testWidgets('IDR Navigator app launches and displays Navigation HUD', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => IdrPipeline()),
        ],
        child: const IdrNavigatorApp(),
      ),
    );

    // Initial pump
    await tester.pump();

    // Verify Navigation UI elements
    expect(find.text('IDR NAVIGATOR'), findsOneWidget);
    expect(find.text('KM/H'), findsOneWidget);
  });

  testWidgets('PureNavScreen launches and displays navigation map and HUD', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final pipeline = IdrPipeline();
    addTearDown(() => pipeline.pause());
    pipeline.start();

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

    // Verify Navigation UI elements
    expect(find.text('IDR NAVIGATOR'), findsOneWidget);
    expect(find.text('KM/H'), findsOneWidget);

    pipeline.pause();
    await tester.pump();
  });
}

