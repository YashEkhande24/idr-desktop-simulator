import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:idr_navigator/core/math_utils.dart';
import 'package:idr_navigator/services/ekf_3d.dart';

void main() {
  group('Module 4: Ekf3D Tests', () {
    test('Kinematic prediction propagates position correctly', () {
      final ekf = Ekf3D();

      // Forward acceleration of 2 m/s^2 for 1 second (100 steps of 0.01s)
      for (int i = 0; i < 100; i++) {
        ekf.predict(
          vehicleAccel: const Vec3(2.0, 0.0, 0.0),
          vehicleGyro: Vec3.zero,
          dt: 0.01,
        );
      }

      final st = ekf.state;
      // p = 0.5 * a * t^2 = 0.5 * 2.0 * 1.0^2 = 1.0 meter
      expect(st.px, closeTo(1.0, 0.1));
      // v = a * t = 2.0 * 1.0 = 2.0 m/s
      expect(st.vx, closeTo(2.0, 0.1));
    });

    test('Non-Holonomic Constraints (NHC) eliminate false lateral sliding', () {
      final ekf = Ekf3D();

      // Apply forward motion but with severe lateral acceleration disturbance
      for (int i = 0; i < 50; i++) {
        ekf.predict(
          vehicleAccel: const Vec3(1.0, 4.0, 0.0), // 4 m/s^2 false lateral slip
          vehicleGyro: Vec3.zero,
          dt: 0.01,
        );
        ekf.applyNhc(); // constrain lateral sliding to ~0
      }

      final st = ekf.state;
      // Without NHC, vy would be 4.0 * 0.5 = 2.0 m/s
      // With NHC active, lateral velocity should be strongly constrained
      expect(st.vy.abs(), lessThan(0.5));
    });

    test('Sigmoid HDOP autonomously rejects corrupted tunnel GNSS', () {
      final ekf = Ekf3D();

      // Nominal GNSS updates converging towards (10, 0)
      for (int i = 0; i < 8; i++) {
        ekf.updateGnss(
          gnssX: 10.0,
          gnssY: 0.0,
          gnssZ: 0.0,
          hdop: 1.0,
          isDenied: false,
        );
      }
      expect(ekf.state.px, greaterThan(5.0));

      final prevX = ekf.state.px;

      // Corrupted tunnel GNSS outlier at (500, 0) with HDOP = 25.0
      ekf.updateGnss(
        gnssX: 500.0,
        gnssY: 0.0,
        gnssZ: 0.0,
        hdop: 25.0,
        isDenied: true,
      );

      // Filter should ignore the corrupted outlier
      expect(ekf.state.px, closeTo(prevX, 0.1));
    });

    test('Kinematic cross-covariance couples heading uncertainty into position error during turns', () {
      final ekf = Ekf3D();

      // Forward motion of 10 m/s with 0.15 rad/s yaw rate
      for (int i = 0; i < 50; i++) {
        ekf.predict(
          vehicleAccel: const Vec3(0.0, 0.0, 0.0),
          vehicleGyro: const Vec3(0.0, 0.0, 0.15),
          vTcn: 10.0,
          dt: 0.02,
        );
      }

      // Cross-covariance P03 or P13 must be non-zero to reflect heading-position coupling
      expect(ekf.crossCovarianceP03.abs() + ekf.crossCovarianceP13.abs(), greaterThan(0.001));
    });

    test('Chi-square gating protects barometer from abrupt pressure spikes', () {
      final ekf = Ekf3D();

      // Normal elevation updates at 10m
      for (int i = 0; i < 20; i++) {
        ekf.updateBarometer(10.0);
      }
      expect(ekf.state.pz, closeTo(10.0, 0.5));

      final prevZ = ekf.state.pz;

      // Abrupt impossible 500m spike (e.g. cabin door slam pressure wave)
      ekf.updateBarometer(500.0);

      // Chi-square 1 DOF gate rejects the outlier
      expect(ekf.state.pz, closeTo(prevZ, 0.5));
    });

    test('Turn Velocity Update (TVU) reinforces forward speed during curves', () {
      final ekf = Ekf3D();
      // Vehicle in motion at 10.0 m/s
      ekf.predict(
        vehicleAccel: Vec3.zero,
        vehicleGyro: const Vec3(0.0, 0.0, 0.3),
        vTcn: 10.0,
        dt: 0.1,
      );
      expect(ekf.forwardSpeed, closeTo(10.0, 0.5));

      // Inject physical centripetal speed of 11.2 m/s (Huber inlier)
      ekf.updateTurnVelocity(11.2, variance: 0.10);
      expect(ekf.forwardSpeed, closeTo(10.8, 0.5));
    });

    test('SE(2) arc integration propagates curved trajectory smoothly without chord shrinkage', () {
      final ekf = Ekf3D(initYaw: 0.0); // Heading East (+X)
      const double speed = 10.0; // 10 m/s
      const double omegaZ = 0.5; // Turning Left
      const double dt = 0.1;

      for (int i = 0; i < 10; i++) {
        ekf.predict(
          vehicleAccel: Vec3.zero,
          vehicleGyro: const Vec3(0.0, 0.0, omegaZ),
          vTcn: speed,
          dt: dt,
        );
      }

      // Over 1.0 second, total yaw rotated is 0.5 rad (~28.6 deg)
      // True arc length = speed * t = 10.0m
      final dx = ekf.state.px;
      final dy = ekf.state.py;
      final chordDist = math.sqrt(dx * dx + dy * dy);
      // Chord distance across 0.5 rad arc of radius 20m: 2 * R * sin(theta/2) = 40 * sin(0.25) = 9.896m
      expect(chordDist, closeTo(9.896, 0.3));
      expect(ekf.state.py, greaterThan(2.0)); // turned North (+Y)
    });
  });
}
