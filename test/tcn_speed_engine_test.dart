import 'package:flutter_test/flutter_test.dart';
import 'package:idr_navigator/core/constants.dart';
import 'package:idr_navigator/core/math_utils.dart';
import 'package:idr_navigator/services/tcn_speed_engine.dart';

void main() {
  group('Module 3: Upgraded 8-Channel TCN Speed Engine Tests', () {
    test('8-Channel window accumulates rotation-invariant norms', () {
      final engine = TcnSpeedEngine();

      for (int i = 0; i < 45; i++) {
        engine.predict(
          vehicleAccel: const Vec3(1.2, 0.4, 0.8),
          vehicleGyro: const Vec3(0.01, -0.02, 0.03),
          isShockGateActive: false,
          dt: 0.02,
        );
      }

      expect(engine.isStationary, isFalse);
      expect(engine.estimatedSpeed, greaterThan(0.0));
      expect(engine.estimatedVariance, inInclusiveRange(0.08, 2.0));
    });

    test('Human walking footstep cadence is correctly detected as pedestrian', () {
      final engine = TcnSpeedEngine();

      // Simulate human walking with phone in hand:
      // Inverted pendulum 1.8 Hz vertical bounce (~2.5 m/s^2) with natural torso wiggle
      for (int i = 0; i < 30; i++) {
        final double zBounce = 2.8 * (i % 4 == 0 ? 1.0 : (i % 4 == 2 ? -1.0 : 0.0));
        engine.predict(
          vehicleAccel: Vec3(0.6, 0.3, zBounce),
          vehicleGyro: Vec3(0.25, 0.20, 0.30), // Human body wiggle > 0.18 rad/s
          isShockGateActive: false,
          dt: 0.02,
        );
      }

      expect(engine.isPedestrian, isTrue);
      // Speed must be clamped to human walking pace
      expect(engine.estimatedSpeed, lessThanOrEqualTo(IdrConstants.pedestrianMaxSpeed));
    });

    test('Slow vehicle traffic crawl preserves car tracking and does NOT trigger pedestrian', () {
      final engine = TcnSpeedEngine();

      // Crawling car at 4-5 km/h in traffic:
      // Flat vehicle suspension (low vertical bounce), rock-steady chassis (near-zero angular rate)
      for (int i = 0; i < 30; i++) {
        engine.predict(
          vehicleAccel: const Vec3(0.25, 0.01, 0.05), // Gentle forward crawl
          vehicleGyro: const Vec3(0.005, 0.002, 0.01), // Near-zero angular rate (< 0.06 rad/s)
          isShockGateActive: false,
          dt: 0.02,
        );
      }

      expect(engine.isPedestrian, isFalse);
      expect(engine.isStationary, isFalse);
      expect(engine.estimatedSpeed, greaterThan(0.0));
    });

    test('Violent pothole shock triggers gate freeze and elevates uncertainty variance', () {
      final engine = TcnSpeedEngine();

      for (int i = 0; i < 20; i++) {
        engine.predict(
          vehicleAccel: const Vec3(1.0, 0.0, 0.0),
          vehicleGyro: const Vec3(0.0, 0.0, 0.0),
          isShockGateActive: false,
          dt: 0.02,
        );
      }

      final speedBeforeShock = engine.estimatedSpeed;

      // Pothole freeze active
      final speedDuringShock = engine.predict(
        vehicleAccel: const Vec3(1.0, 0.0, 18.0),
        vehicleGyro: const Vec3(0.0, 0.0, 0.0),
        isShockGateActive: true,
        dt: 0.02,
      );

      // Speed is held steady, uncertainty variance σ^2 is elevated
      expect(speedDuringShock, equals(speedBeforeShock));
      expect(engine.estimatedVariance, greaterThan(3.0));
    });

    test('Skog GLRT confirms standstill when vehicle is resting at stoplight', () {
      final engine = TcnSpeedEngine();

      // Feed stationary resting signals with small thermal noise
      for (int i = 0; i < 25; i++) {
        engine.predict(
          vehicleAccel: const Vec3(0.01, -0.01, 0.02),
          vehicleGyro: const Vec3(0.001, 0.001, 0.0),
          isShockGateActive: false,
          dt: 0.02,
        );
      }

      expect(engine.isStationary, isTrue);
      expect(engine.estimatedSpeed, equals(0.0));
      expect(engine.lastSkogStatistic, lessThan(15.0));
    });

    test('Vehicle immediately breaks out of standstill on gentle throttle launch and builds speed', () {
      final engine = TcnSpeedEngine();

      // 1. First come to a complete rest at a red light
      for (int i = 0; i < 25; i++) {
        engine.predict(
          vehicleAccel: const Vec3(0.01, -0.01, 0.01),
          vehicleGyro: const Vec3(0.001, 0.001, 0.0),
          isShockGateActive: false,
          dt: 0.02,
        );
      }
      expect(engine.isStationary, isTrue);
      expect(engine.estimatedSpeed, equals(0.0));

      // 2. Light turns green: driver applies gentle throttle (0.25 m/s^2 forward acceleration)
      for (int i = 0; i < 30; i++) {
        engine.predict(
          vehicleAccel: const Vec3(0.25, 0.01, 0.02),
          vehicleGyro: const Vec3(0.002, 0.001, 0.005),
          isShockGateActive: false,
          dt: 0.02,
        );
      }

      // Standstill must be unlatched and speed must be positively increasing
      expect(engine.isStationary, isFalse);
      expect(engine.estimatedSpeed, greaterThan(0.05));
    });
  });
}

