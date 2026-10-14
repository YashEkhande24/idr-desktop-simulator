import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:idr_navigator/services/idr_pipeline.dart';
import 'package:idr_navigator/services/secret_bt_receiver.dart';
import 'package:idr_navigator/widgets/unified_tools_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      final message = details.exception.toString();
      if (message.contains('Failed to load font') ||
          message.contains('fonts.gstatic.com') ||
          message.contains('google_fonts')) {
        return;
      }
      originalOnError?.call(details);
    };
    TestWidgetsFlutterBinding.instance.platformDispatcher.onError = (error, stack) {
      if (error.toString().contains('Failed to load font') ||
          error.toString().contains('fonts.gstatic.com') ||
          error.toString().contains('google_fonts')) {
        return true;
      }
      return false;
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('dev.fluttercommunity.plus/sensors/method'), (call) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter.baseflow.com/geolocator'), (call) async {
          if (call.method == 'isLocationServiceEnabled') return true;
          if (call.method == 'checkPermission') return 3;
          if (call.method == 'getLastKnownPosition') return null;
          return null;
        });
  });

  group('Secret Bluetooth Demo Mode & Artificial Drift Tests', () {
    late SecretBtReceiver receiver;

    setUp(() {
      receiver = SecretBtReceiver();
      receiver.resetDrift();
    });

    tearDown(() {
      receiver.setEnabled(false);
    });

    test('IdrGhostPacket serialization and deserialization', () {
      final packet = IdrGhostPacket(
        latitude: 18.52043,
        longitude: 73.85674,
        altitude: 562.1,
        speedMps: 12.5,
        headingDeg: 42.0,
        accuracy: 1.5,
        timestampMs: 1727260000000,
        sender: 'IDR-Ghost-Phone2',
      );

      final json = packet.toJson();
      expect(json['magic'], 'IDR_GHOST_GPS');
      expect(json['lat'], 18.52043);
      expect(json['lng'], 73.85674);
      expect(json['speed_mps'], 12.5);

      final restored = IdrGhostPacket.fromJson(json);
      expect(restored.latitude, 18.52043);
      expect(restored.longitude, 73.85674);
      expect(restored.speedMps, 12.5);
      expect(restored.headingDeg, 42.0);
      expect(restored.sender, 'IDR-Ghost-Phone2');
    });

    test('SecretBtReceiver receives packet and generates artificial drift', () async {
      receiver.setEnabled(true);
      receiver.setDriftRate(0.005); // 0.5% SIH Winner target drift

      final packet = IdrGhostPacket(
        latitude: 19.8477,
        longitude: 75.2564,
        altitude: 550.0,
        speedMps: 15.0, // ~54 km/h
        headingDeg: 90.0, // Due East
        accuracy: 1.2,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        sender: 'Phone2-Beacon',
      );

      GhostNavState? emittedState;
      final sub = receiver.stateStream.listen((state) {
        emittedState = state;
      });

      receiver.injectPacket(packet);
      expect(receiver.connectionStatus, GhostConnectionStatus.connected);
      expect(receiver.packetsReceived, 1);

      // Wait 150 ms for kinematic 20 Hz loop (3 ticks)
      await Future.delayed(const Duration(milliseconds: 160));

      expect(emittedState, isNotNull);
      final s = emittedState!;

      // Verify raw vs drifted coordinates
      expect(s.rawPosition.latitude, closeTo(19.8477, 1e-5));
      expect(s.rawPosition.longitude, closeTo(75.2564, 1e-5));

      // With 0.5% drift, drifted position should be within 2 meters of raw position initially
      expect(s.driftedPosition.latitude, closeTo(19.8477, 1e-3));
      expect(s.driftedPosition.longitude, closeTo(75.2564, 1e-3));

      // Distance and drift metrics
      expect(s.cumulativeDistanceM, greaterThan(0.0));
      expect(s.driftPercentage, closeTo(0.5, 0.5)); // Around 0.5%
      expect(s.speedKmh, greaterThan(0.0));

      await sub.cancel();
    });

    test('IdrPipeline seamlessly integrates secret demo mode and overrides coordinates', () async {
      final pipeline = IdrPipeline();

      expect(pipeline.isSecretDemoModeActive, isFalse);

      pipeline.toggleSecretDemoMode(true);
      expect(pipeline.isSecretDemoModeActive, isTrue);

      final packet = IdrGhostPacket(
        latitude: 18.9220,
        longitude: 72.8347,
        altitude: 20.0,
        speedMps: 13.89, // 50 km/h
        headingDeg: 180.0, // South
        accuracy: 1.0,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        sender: 'TestBeacon',
      );

      pipeline.secretBtReceiver.injectPacket(packet);

      // Wait 120 ms for kinematic loop to process
      await Future.delayed(const Duration(milliseconds: 150));

      final solution = pipeline.latestSolution;
      expect(solution, isNotNull);
      expect(solution!.latitude, closeTo(18.9220, 1e-3));
      expect(solution.longitude, closeTo(72.8347, 1e-3));
      expect(solution.headingDeg, closeTo(180.0, 10.0));

      // Verify artificial drift is present on NavSolution
      expect(solution.idrDriftError, greaterThanOrEqualTo(0.0));
      expect(solution.classicLatitude, isNotNull);
      expect(solution.classicLongitude, isNotNull);
      expect(pipeline.classicTrajectory, isNotEmpty);

      pipeline.toggleSecretDemoMode(false);
      expect(pipeline.isSecretDemoModeActive, isFalse);
    });

    test('SecretBtReceiver simulation mode emits packets without external device', () async {
      receiver.startSimulation();
      expect(receiver.isSimulating, isTrue);
      expect(receiver.isEnabled, isTrue);

      await Future.delayed(const Duration(milliseconds: 250));

      expect(receiver.packetsReceived, greaterThanOrEqualTo(1));
      expect(receiver.connectionStatus, GhostConnectionStatus.connected);

      receiver.stopSimulation();
      expect(receiver.isSimulating, isFalse);
    });

    testWidgets('UnifiedToolsSheet renders Ghost Mode Override toggle and controls', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final pipeline = IdrPipeline();
      addTearDown(() => pipeline.pause());

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<IdrPipeline>.value(
            value: pipeline,
            child: const Scaffold(
              body: UnifiedToolsSheet(),
            ),
          ),
        ),
      );

      // Initial pump
      await tester.pump();

      // Verify Ghost Mode section label and title exist
      expect(find.text('SHADOW LINK // GHOST GPS (PHONE 2)'), findsOneWidget);
      expect(find.text('GHOST MODE OVERRIDE'), findsOneWidget);
      expect(find.text('STANDBY'), findsOneWidget);

      // Toggle Ghost Mode ON via the Switch
      final switches = find.byType(Switch);
      expect(switches, findsWidgets);

      // Tap the ghost mode switch (which toggles secret demo mode)
      pipeline.toggleSecretDemoMode(true);
      await tester.pump();

      expect(pipeline.isSecretDemoModeActive, isTrue);
      expect(find.text('DRIFT & TELEMETRY'), findsOneWidget);
      expect(find.text('SIMULATE'), findsOneWidget);

      pipeline.toggleSecretDemoMode(false);
      await tester.pump();
    });
  });
}
