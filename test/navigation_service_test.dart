import 'package:flutter_test/flutter_test.dart';
import 'package:idr_navigator/core/math_utils.dart';
import 'package:idr_navigator/models/navigation_models.dart';
import 'package:idr_navigator/services/idr_pipeline.dart';
import 'package:idr_navigator/services/map_snapper.dart';
import 'package:idr_navigator/services/navigation_service.dart';
import 'package:idr_navigator/services/routing_service.dart';

import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('dev.fluttercommunity.plus/sensors/method'), (call) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter.baseflow.com/geolocator'), (call) async {
          if (call.method == 'isLocationServiceEnabled') return true;
          if (call.method == 'checkPermission') return 3; // LocationPermission.whileInUse
          return null;
        });
  });

  group('Navigation Models Tests', () {
    test('NavDestination initializes with ENU and Geodetic coordinates', () {
      const dest = NavDestination(
        name: 'Pune Airport (PNQ)',
        subtitle: 'Lohegaon corridor',
        targetEnu: Vec3(6200.0, 4800.0, 25.0),
        latitude: 18.5822,
        longitude: 73.9197,
      );

      expect(dest.name, equals('Pune Airport (PNQ)'));
      expect(dest.targetEnu.x, equals(6200.0));
      expect(dest.targetEnu.y, equals(4800.0));
      expect(dest.latitude, equals(18.5822));
      expect(dest.longitude, equals(73.9197));
      expect(dest.isCustomPin, isFalse);
    });

    test('RouteStep and NavRoute calculate accurate distances and ETA', () {
      const step1 = RouteStep(
        instruction: 'Head North on Mumbai-Pune Expressway',
        maneuver: ManeuverType.depart,
        distanceMeters: 1000.0,
        startPosEnu: Vec3(0, 0, 0),
        endPosEnu: Vec3(0, 1000, 0),
        roadName: 'Mumbai-Pune Expressway',
        expectedSpeedMps: 20.0, // 72 km/h
      );

      expect(step1.estimatedDurationSeconds, equals(50.0));

      final route = NavRoute(
        destination: const NavDestination(
          name: 'Toll Plaza',
          targetEnu: Vec3(0, 3000, 0),
        ),
        points: const [Vec3(0, 0, 0), Vec3(0, 1000, 0), Vec3(0, 3000, 0)],
        steps: const [step1],
        totalDistanceMeters: 3000.0,
        estimatedDurationSeconds: 150.0,
        isOfflineAStar: true,
      );

      expect(route.totalDistanceKm, equals(3.0));
      expect(route.estimatedDurationMinutes, equals(3));
      expect(route.isOfflineAStar, isTrue);
      expect(route.formattedEtaClock(), isNotEmpty);
    });
  });

  group('RoutingService Offline A* Graph Pathfinder Tests', () {
    test('Plans optimal A* route across connected road branches and generates maneuvers', () async {
      // Create a 2-road network meeting at junction (0, 500)
      final branch1 = MapBranch(
        name: 'NH-48 Highway',
        points: const [
          Vec3(0, 0, 0),
          Vec3(0, 250, 0),
          Vec3(0, 500, 0),
        ],
        speedLimitMps: 22.2,
      );

      final branch2 = MapBranch(
        name: 'Airport Bypass Road',
        points: const [
          Vec3(0, 500, 0),
          Vec3(300, 500, 0),
          Vec3(600, 500, 0),
        ],
        speedLimitMps: 16.6,
      );

      final branches = [branch1, branch2];

      const destination = NavDestination(
        name: 'Airport Terminal',
        targetEnu: Vec3(600, 500, 0),
      );

      final route = await RoutingService.calculateRoute(
        originEnu: const Vec3(0, 0, 0),
        destination: destination,
        roadBranches: branches,
      );

      expect(route.points.length, greaterThanOrEqualTo(3));
      expect(route.totalDistanceMeters, closeTo(1100.0, 50.0));
      expect(route.steps, isNotEmpty);

      // Verify maneuvers: Depart -> Turn Right -> Arrive
      expect(route.steps.first.maneuver, equals(ManeuverType.depart));
      final turnSteps = route.steps.where((s) => s.maneuver == ManeuverType.turnRight).toList();
      expect(turnSteps, isNotEmpty);
      expect(route.steps.last.maneuver, equals(ManeuverType.arrive));
    });
  });

  group('NavigationService Lifecycle & Real-Time Tracking Tests', () {
    late IdrPipeline pipeline;
    late NavigationService navService;

    setUp(() {
      pipeline = IdrPipeline();
      navService = pipeline.navigationService;
    });

    tearDown(() {
      pipeline.dispose();
    });

    test('startNavigation initializes route and distance countdown', () async {
      const dest = NavDestination(
        name: 'Katraj Tunnel',
        targetEnu: Vec3(0, 800, 0),
      );

      final started = await navService.startNavigation(dest, pipeline);

      expect(started, isTrue);
      expect(navService.isNavigating, isTrue);
      expect(navService.destination, equals(dest));
      expect(navService.route, isNotNull);
      expect(navService.hasArrived, isFalse);
      expect(navService.isOffRoute, isFalse);
      expect(navService.remainingDistanceMeters, greaterThan(0.0));
      expect(navService.formatDistance(navService.remainingDistanceMeters), isNotEmpty);
      expect(navService.formatRemainingTime(), isNotEmpty);
    });

    test('updateVehicleProgress updates distance and detects destination arrival', () async {
      const dest = NavDestination(
        name: 'Hinjewadi Phase 1',
        targetEnu: Vec3(0, 500, 0),
      );

      await navService.startNavigation(dest, pipeline);

      // Vehicle starts at (0, 0)
      navService.updateVehicleProgress(const Vec3(0, 0, 0), 0.0, pipeline);
      final initialRemaining = navService.remainingDistanceMeters;

      // Vehicle drives forward to (0, 300)
      navService.updateVehicleProgress(const Vec3(0, 300, 0), 0.0, pipeline);
      expect(navService.remainingDistanceMeters, lessThan(initialRemaining));
      expect(navService.hasArrived, isFalse);

      // Vehicle arrives near destination (0, 490) within 25m threshold
      navService.updateVehicleProgress(const Vec3(0, 490, 0), 0.0, pipeline);
      expect(navService.hasArrived, isTrue);
      expect(navService.remainingDistanceMeters, equals(0.0));
      expect(navService.distanceToNextManeuverMeters, equals(0.0));
    });

    test('updateVehicleProgress flags offRoute when vehicle departs > 65m', () async {
      const dest = NavDestination(
        name: 'Airport Road',
        targetEnu: Vec3(280, 600, 0),
      );

      await navService.startNavigation(dest, pipeline);
      final pts = navService.route!.points;
      expect(pts.length, greaterThanOrEqualTo(2));

      // Vehicle on track (midpoint of first segment)
      final onTrack = (pts[0] + pts[1]) * 0.5;
      navService.updateVehicleProgress(onTrack, 0.0, pipeline);
      expect(navService.isOffRoute, isFalse);

      // Vehicle departs 300m away from on-track position
      final offTrack = onTrack + const Vec3(300, -300, 0);
      navService.updateVehicleProgress(offTrack, 0.0, pipeline);
      expect(navService.isOffRoute, isTrue);
    });

    test('cancelNavigation resets active navigation state', () async {
      const dest = NavDestination(
        name: 'Custom Target',
        targetEnu: Vec3(200, 400, 0),
      );

      await navService.startNavigation(dest, pipeline);
      expect(navService.isNavigating, isTrue);

      navService.cancelNavigation();

      expect(navService.isNavigating, isFalse);
      expect(navService.destination, isNull);
      expect(navService.route, isNull);
      expect(navService.remainingDistanceMeters, equals(0.0));
      expect(navService.hasArrived, isFalse);
    });
  });
}
