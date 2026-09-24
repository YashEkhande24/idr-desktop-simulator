import 'package:flutter_test/flutter_test.dart';
import 'package:idr_navigator/core/math_utils.dart';
import 'package:idr_navigator/services/ekf_3d.dart';
import 'package:idr_navigator/services/tcn_speed_engine.dart';

void main() {
  group('Mathematical & Kinematic Accuracy Upgrades', () {
    test('Mat3.skewSymmetric satisfies [v]x * u == v x u', () {
      final v = const Vec3(1.5, -2.4, 3.1);
      final u = const Vec3(-0.8, 1.2, -4.5);

      final vx = Mat3.skewSymmetric(v);
      final transformed = vx.transform(u);
      final cross = v.cross(u);

      expect(transformed.x, closeTo(cross.x, 1e-10));
      expect(transformed.y, closeTo(cross.y, 1e-10));
      expect(transformed.z, closeTo(cross.z, 1e-10));
    });

    test('Vincenty distance evaluates exact ellipsoidal geodesic distance', () {
      // Coincident points
      final dZero = MathUtils.vincentyDistanceMeters(19.0760, 72.8777, 19.0760, 72.8777);
      expect(dZero, equals(0.0));

      // Mumbai (19.0760° N, 72.8777° E) to Pune (18.5204° N, 73.8567° E)
      // Geodesic distance on WGS-84 ellipsoid is approximately 119.5 km
      final dVincenty = MathUtils.vincentyDistanceMeters(19.0760, 72.8777, 18.5204, 73.8567);
      final dHaversine = MathUtils.haversineDistanceMeters(19.0760, 72.8777, 18.5204, 73.8567);

      expect(dVincenty, closeTo(119500.0, 2000.0));
      // Spherical vs Ellipsoidal difference is typically 0.1% to 0.4%
      final relDiff = (dVincenty - dHaversine).abs() / dVincenty;
      expect(relDiff, lessThan(0.005)); // within 0.5%
    });

    test('Transport rate vector omega_en^n vanishes at rest and computes correct ENU curvature', () {
      // At rest (v = 0), transport rate is identically 0
      final wRest = MathUtils.transportRate(vNav: Vec3.zero, latDeg: 19.076);
      expect(wRest.x, equals(0.0));
      expect(wRest.y, equals(0.0));
      expect(wRest.z, equals(0.0));

      // Moving North (v_N = 30 m/s): navigation frame pitches down around East axis (w_E < 0)
      final vNorth = const Vec3(0.0, 30.0, 0.0);
      final wNorth = MathUtils.transportRate(vNav: vNorth, latDeg: 19.076);
      expect(wNorth.x, lessThan(0.0)); // -v_N / (M + h)
      expect(wNorth.y, equals(0.0));
      expect(wNorth.z, equals(0.0));

      // Moving East (v_E = 30 m/s): navigation frame rotates around North and Up axes
      final vEast = const Vec3(30.0, 0.0, 0.0);
      final wEast = MathUtils.transportRate(vNav: vEast, latDeg: 19.076);
      expect(wEast.x, equals(0.0));
      expect(wEast.y, greaterThan(0.0)); // v_E / (N + h)
      expect(wEast.z, greaterThan(0.0)); // v_E * tan(phi) / (N + h)
    });

    test('Total apparent acceleration incorporates Coriolis and Transport Rate', () {
      final vNav = const Vec3(25.0, 0.0, 0.0); // 90 km/h highway speed Eastbound
      final aApparent = MathUtils.apparentAcceleration(vNav: vNav, latDeg: 19.076);
      final aCoriolis = MathUtils.coriolisAcceleration(vNav, 19.076);

      // Both agree on overall direction (Eötvös lift and Southward deflection)
      expect(aApparent.x, equals(0.0));
      expect(aApparent.y, lessThan(0.0));
      expect(aApparent.z, greaterThan(0.0));

      // Apparent acceleration magnitude is slightly larger due to added transport rate term
      expect(aApparent.norm, greaterThan(aCoriolis.norm));
    });

    test('Carriageway corridor deadband Huber loss ignores within-lane deviations', () {
      // Within lane deadband (+/- 1.75m): effective residual is zero, weight is 1.0
      final inLane = MathUtils.deadbandHuberLoss(rawResidual: 1.25, deadbandHalfWidthM: 1.75);
      expect(inLane.effectiveResidual, equals(0.0));
      expect(inLane.weight, equals(1.0));

      // Negative within lane deadband
      final inLaneNeg = MathUtils.deadbandHuberLoss(rawResidual: -1.50, deadbandHalfWidthM: 1.75);
      expect(inLaneNeg.effectiveResidual, equals(0.0));
      expect(inLaneNeg.weight, equals(1.0));

      // Outside lane deadband (e.g. 2.75m -> 1.0m excess): positive effective residual
      final outLane = MathUtils.deadbandHuberLoss(rawResidual: 2.75, deadbandHalfWidthM: 1.75);
      expect(outLane.effectiveResidual, closeTo(1.0, 1e-4));
      expect(outLane.weight, equals(1.0));

      // Large departure (e.g. 5.75m -> 4.0m excess): attenuated by Huber weight
      final largeDeparture = MathUtils.deadbandHuberLoss(rawResidual: 5.75, deadbandHalfWidthM: 1.75, k: 2.0);
      expect(largeDeparture.weight, lessThan(1.0));
      expect(largeDeparture.effectiveResidual, lessThan(4.0));
    });

    test('EKF GNSS update translates antenna coordinate by vehicle lever-arm', () {
      final ekf = Ekf3D();
      // Vehicle pointing North (yaw = 0 deg in ENU means pointing East, so let's set heading = 0)
      ekf.initializeHeading(0.0); // Facing East (x_fwd is +X East, y_lat is +Y North)

      // Mount offset: phone is 1.5m in front of rear axle (arm = [1.5, 0.0, 0.0])
      // When antenna is at (101.5, 50.0, 0.0), rear axle is at (100.0, 50.0, 0.0)
      ekf.updateGnss(
        gnssX: 101.5,
        gnssY: 50.0,
        gnssZ: 0.0,
        hdop: 1.0,
        isDenied: false,
        customLeverArm: const Vec3(1.5, 0.0, 0.0),
      );

      final state = ekf.state;
      // Fast acquisition snap should set position to rear-axle center (100.0, 50.0)
      expect(state.position.x, closeTo(100.0, 0.05));
      expect(state.position.y, closeTo(50.0, 0.05));
    });

    test('EKF applyZacu calibrates forward accelerometer bias during straight cruising', () {
      final ekf = Ekf3D();
      expect(ekf.accelBiasX, equals(0.0));

      // Apply several ZACU cycles with small persistent raw acceleration (e.g. 0.05 m/s^2 sensor bias)
      for (int i = 0; i < 20; i++) {
        ekf.applyZacu(0.05, 0.01);
      }

      // Accel bias should have migrated towards 0.05
      expect(ekf.accelBiasX, greaterThan(0.01));
      expect(ekf.accelBiasX, lessThanOrEqualTo(0.06));
    });

    test('TcnSpeedEngine 1D Gauss-Markov observer smoothly propagates acceleration between epochs', () {
      final engine = TcnSpeedEngine();
      engine.reset();

      // Launch motion from rest over a sustained throttle application
      double lastSpeed = 0.0;
      for (int i = 0; i < 15; i++) {
        lastSpeed = engine.predict(
          vehicleAccel: const Vec3(1.5, 0.0, 0.0),
          vehicleGyro: Vec3.zero,
          isShockGateActive: false,
          dt: 0.01,
        );
      }

      // Forward acceleration breaks standstill and registers positive speed
      expect(lastSpeed, greaterThan(0.0));
    });
  });
}
