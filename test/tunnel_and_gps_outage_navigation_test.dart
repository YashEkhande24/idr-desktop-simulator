import 'package:flutter_test/flutter_test.dart';
import 'package:idr_navigator/core/math_utils.dart';
import 'package:idr_navigator/models/navigation_models.dart';
import 'package:idr_navigator/models/sensor_data.dart';
import 'package:idr_navigator/services/idr_pipeline.dart';
import 'package:idr_navigator/services/map_snapper.dart';
import 'package:idr_navigator/services/sensor_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Tunnel Mode & GPS Deactivation Navigation Resilience Tests', () {
    late IdrPipeline pipeline;

    setUp(() {
      pipeline = IdrPipeline(autoStart: false);
      // Setup known reference coordinate (Pune)
      pipeline.sensorService.setReferenceAnchor(18.5204, 73.8567, 550.0);
    });

    tearDown(() {
      pipeline.dispose();
    });

    test('1. Navigation continues seamlessly when tunnel mode is activated', () async {
      // Define a straight tunnel along North (Y-axis)
      final road = MapBranch(
        name: 'Katraj Tunnel',
        points: const [
          Vec3(0, 0, 0),
          Vec3(0, 500, 0),
          Vec3(0, 1000, 0),
          Vec3(0, 2000, 0),
        ],
        isTunnel: true,
        speedLimitMps: 20.0,
      );
      pipeline.mapSnapper.branches.clear();
      pipeline.mapSnapper.branches.add(road);

      const dest = NavDestination(
        name: 'Tunnel North Exit',
        targetEnu: Vec3(0, 1500, 0),
        latitude: 18.5338,
        longitude: 73.8567,
      );

      // Start pipeline and navigation
      pipeline.startForTesting();
      await pipeline.navigationService.startNavigation(dest, pipeline);
      expect(pipeline.navigationService.isNavigating, isTrue);

      final initialRemaining = pipeline.navigationService.remainingDistanceMeters;
      expect(initialRemaining, closeTo(1500.0, 50.0));

      // 1. Initial driving: car approaches tunnel entrance at 15 m/s (54 km/h)
      // Provide initial GNSS fix to initialize heading and position
      final entryGnss = GnssSample(
        timestamp: 1.0,
        position: const Vec3(0.0, 50.0, 0.0),
        latitude: 18.5204 + 50.0 / 111320.0,
        longitude: 73.8567,
        altitude: 550.0,
        speed: 15.0,
        heading: 0.0, // North
        hdop: 1.0,
      );
      pipeline.processGnssForTesting(entryGnss);

      // Send IMU samples showing forward movement
      for (int i = 0; i < 20; i++) {
        pipeline.processImuForTesting(ImuSample(
          timestamp: 1.0 + (i * 0.01),
          accel: const Vec3(0.0, 0.0, 9.81),
          gyro: Vec3.zero,
        ));
      }

      final preTunnelSpeed = pipeline.tcnSpeed.estimatedSpeed;
      final preTunnelPosY = pipeline.ekf.state.position.y;
      final entryLat = pipeline.currentLatitude;
      expect(preTunnelSpeed, greaterThan(5.0));

      // 2. ENTER TUNNEL: User activates "SIMULATE TUNNEL" (or enters real tunnel outage)
      pipeline.toggleTunnelOutage();
      expect(pipeline.forceTunnelOutage, isTrue);
      expect(pipeline.tcnSpeed.isOutageMode, isTrue);
      expect(pipeline.tcnSpeed.isStationary, isFalse);

      // Feed 100 IMU samples (1 second) of highway cruising inside the tunnel (a_fwd ~ 0, gyro ~ 0)
      for (int i = 1; i <= 100; i++) {
        final t = 2.0 + (i * 0.01);
        // Small road vibration noise typical of tunnel asphalt
        final noise = (i % 2 == 0 ? 0.05 : -0.05);
        pipeline.processImuForTesting(ImuSample(
          timestamp: t,
          accel: Vec3(noise, 0.0, 9.81 + noise * 0.5),
          gyro: const Vec3(0.0, 0.0, 0.0),
        ));
      }

      // Assertions inside tunnel:
      // A. Vehicle must NOT be locked into standstill/zero-velocity!
      expect(pipeline.tcnSpeed.isStationary, isFalse, reason: 'Vehicle must not freeze at standstill in tunnel');
      expect(pipeline.tcnSpeed.estimatedSpeed, greaterThan(10.0), reason: 'Vehicle must maintain cruising speed in tunnel');

      // B. EKF position must continue advancing North through the tunnel
      final insideTunnelPosY = pipeline.ekf.state.position.y;
      expect(insideTunnelPosY, greaterThan(preTunnelPosY + 5.0), reason: 'Vehicle position must advance through the tunnel');

      // C. Turn-by-turn navigation must advance and remaining distance must decrement
      final tunnelRemaining = pipeline.navigationService.remainingDistanceMeters;
      expect(tunnelRemaining, lessThan(initialRemaining), reason: 'Remaining distance must decrement as vehicle drives through tunnel');
      expect(pipeline.navigationService.isOffRoute, isFalse, reason: 'Vehicle staying on tunnel road must not trigger false off-route');

      // D. Geodetic coordinates (lat/lon) must update to dead reckoning WGS84 (not frozen at entrance!)
      final tunnelLat = pipeline.currentLatitude;
      expect(tunnelLat, isNotNull);
      expect(tunnelLat, greaterThan(entryLat!), reason: 'Latitude must advance North via dead-reckoning geodesy');
    });

    test('2. Navigation continues when GPS hardware is deactivated in device settings', () async {
      final road = MapBranch(
        name: 'Expressway',
        points: const [
          Vec3(0, 0, 0),
          Vec3(0, 1000, 0),
        ],
        speedLimitMps: 25.0,
      );
      pipeline.mapSnapper.branches.clear();
      pipeline.mapSnapper.branches.add(road);

      const dest = NavDestination(
        name: 'City Gate',
        targetEnu: Vec3(0, 800, 0),
        latitude: 18.5276,
        longitude: 73.8567,
      );

      pipeline.startForTesting();
      await pipeline.navigationService.startNavigation(dest, pipeline);

      // Simulate initial lock at 18 m/s
      pipeline.processGnssForTesting(GnssSample(
        timestamp: 10.0,
        position: const Vec3(0, 100, 0),
        latitude: 18.5213,
        longitude: 73.8567,
        altitude: 550.0,
        speed: 18.0,
        heading: 0.0,
        hdop: 1.0,
      ));

      for (int i = 0; i < 20; i++) {
        pipeline.processImuForTesting(ImuSample(
          timestamp: 10.0 + (i * 0.01),
          accel: const Vec3(0.0, 0.0, 9.81),
          gyro: Vec3.zero,
        ));
      }

      final speedBeforeGpsOff = pipeline.tcnSpeed.estimatedSpeed;
      final posBeforeGpsOff = pipeline.ekf.state.position.y;
      final latBeforeGpsOff = pipeline.currentLatitude!;
      final initialRemaining = pipeline.navigationService.remainingDistanceMeters;
      expect(speedBeforeGpsOff, greaterThan(5.0));

      // Simulate user disabling GPS in quick settings
      pipeline.sensorService.emitGpsStatusForTesting(
        GpsHardwareStatus.serviceDisabled,
        'Location services are disabled in device settings',
      );
      await pumpEventQueue();

      // Process step to propagate new status into solution
      pipeline.processImuForTesting(ImuSample(
        timestamp: 10.5,
        accel: const Vec3(0.0, 0.0, 9.81),
        gyro: Vec3.zero,
      ));

      // Verify pipeline marks GNSS as denied
      expect(pipeline.latestSolution?.isGnssDenied, isTrue);

      // Drive for 150 IMU samples (1.5 seconds) under dead reckoning
      for (int i = 1; i <= 150; i++) {
        final t = 11.0 + (i * 0.01);
        pipeline.processImuForTesting(ImuSample(
          timestamp: t,
          accel: const Vec3(0.02, 0.0, 9.81),
          gyro: Vec3.zero,
        ));
      }

      // Assertions during GPS deactivation:
      expect(pipeline.tcnSpeed.isStationary, isFalse);
      expect(pipeline.tcnSpeed.estimatedSpeed, greaterThan(10.0));
      expect(pipeline.ekf.state.position.y, greaterThan(posBeforeGpsOff + 10.0));
      expect(pipeline.navigationService.remainingDistanceMeters, lessThan(initialRemaining));
      expect(pipeline.currentLatitude, greaterThan(latBeforeGpsOff));
      expect(pipeline.navigationService.isNavigating, isTrue);
    });

    test('3. Vehicle accurately comes to a stop inside a tunnel when driver brakes', () async {
      pipeline.startForTesting();

      // Pre-align cabin on level ground
      for (int i = 0; i < 25; i++) {
        pipeline.processImuForTesting(ImuSample(
          timestamp: 10.0 + (i * 0.01),
          accel: const Vec3(0.0, 0.0, 9.81),
          gyro: Vec3.zero,
        ));
      }

      pipeline.toggleTunnelOutage();
      expect(pipeline.tcnSpeed.isOutageMode, isTrue);

      // Set initial cruising speed
      pipeline.tcnSpeed.enterOutageCruisingMode(15.0);
      expect(pipeline.tcnSpeed.isStationary, isFalse);

      // Simulate hard braking deceleration (a_fwd = -3.5 m/s^2) for 4.5 seconds until stopped
      for (int i = 1; i <= 450; i++) {
        final t = 100.0 + (i * 0.01);
        pipeline.processImuForTesting(ImuSample(
          timestamp: t,
          accel: const Vec3(-3.5, 0.0, 9.81),
          gyro: Vec3.zero,
        ));
      }

      // Then 50 samples resting at standstill (a_fwd = 0.0)
      for (int i = 451; i <= 500; i++) {
        final t = 100.0 + (i * 0.01);
        pipeline.processImuForTesting(ImuSample(
          timestamp: t,
          accel: const Vec3(0.0, 0.0, 9.81),
          gyro: Vec3.zero,
        ));
      }

      // After sustained hard braking, vehicle must reach rest (not locked at cruise forever!)
      expect(pipeline.tcnSpeed.estimatedSpeed, lessThan(0.5));
      expect(pipeline.tcnSpeed.isStationary, isTrue);
    });
  });
}
