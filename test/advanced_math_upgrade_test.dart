import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:idr_navigator/core/math_utils.dart';
import 'package:idr_navigator/services/ekf_3d.dart';
import 'package:idr_navigator/services/map_snapper.dart';
import 'package:idr_navigator/services/tcn_speed_engine.dart';

void main() {
  group('Advanced Mathematical & Kinematic Upgrade Tests', () {
    test('1. Menger curvature accurately computes radius of known circular arcs', () {
      // Circle with radius R = 100 meters, center at (0, 100)
      const r = 100.0;
      final a = Vec3(r * math.cos(-0.1), r + r * math.sin(-0.1), 0.0);
      final b = Vec3(r * math.cos(0.0), r + r * math.sin(0.0), 0.0);
      final c = Vec3(r * math.cos(0.1), r + r * math.sin(0.1), 0.0);

      final kappa = MathUtils.mengerCurvature(a, b, c);
      expect(kappa, closeTo(1.0 / r, 1e-3)); // Expected kappa = 0.01 (1/100m)

      // Straight line has kappa = 0
      final s1 = const Vec3(0.0, 0.0, 0.0);
      final s2 = const Vec3(50.0, 0.0, 0.0);
      final s3 = const Vec3(100.0, 0.0, 0.0);
      expect(MathUtils.mengerCurvature(s1, s2, s3), closeTo(0.0, 1e-6));
    });

    test('2. Analytical PCA orientation angle converges without null-vector when covXY = 0', () {
      // Pure horizontal motion aligned with vehicle X axis: covXX > 0, covXY = 0, covYY = 0
      final theta1 = MathUtils.pcaOrientationAngle(1.5, 0.0, 0.1);
      expect(theta1, closeTo(0.0, 1e-6)); // 0 rad forward

      // Pure lateral motion: covYY > covXX, covXY = 0
      final theta2 = MathUtils.pcaOrientationAngle(0.1, 0.0, 1.5);
      expect(theta2.abs(), closeTo(math.pi / 2, 1e-4)); // 90 deg lateral

      // 45 degree diagonal
      final theta3 = MathUtils.pcaOrientationAngle(1.0, 1.0, 1.0);
      expect(theta3, closeTo(math.pi / 4, 1e-4)); // 45 deg
    });

    test('3. Centripetal turn speed compensates mount lever-arm angular acceleration & banking', () {
      // Uncompensated case: v = 4.0 / 0.20 = 20 m/s (72 km/h)
      final vRaw = MathUtils.centripetalTurnSpeed(
        measuredLatAccel: 4.0,
        yawRate: 0.20,
        mountOffsetForward: 1.25,
        angularAccel: 0.0,
        roadBankAngleRad: 0.0,
      );
      expect(vRaw, closeTo(20.0, 1e-2));

      // With angular acceleration alpha_z = 0.4 rad/s^2 at mount r_x = 1.25m:
      // tangential mount accel = 0.4 * 1.25 = 0.5 m/s^2
      // true net centripetal accel = 4.0 - 0.5 = 3.5 m/s^2 -> v = 3.5 / 0.2 = 17.5 m/s
      final vComp = MathUtils.centripetalTurnSpeed(
        measuredLatAccel: 4.0,
        yawRate: 0.20,
        mountOffsetForward: 1.25,
        angularAccel: 0.4,
        roadBankAngleRad: 0.0,
      );
      expect(vComp, closeTo(17.5, 1e-2));

      // With road superelevation banking phi = 3 degrees:
      // gravity projection = 9.80665 * sin(3 deg) = 0.513 m/s^2
      // net = 4.0 - 0.513 = 3.487 m/s^2 -> v = 3.487 / 0.2 = 17.43 m/s
      final vBank = MathUtils.centripetalTurnSpeed(
        measuredLatAccel: 4.0,
        yawRate: 0.20,
        mountOffsetForward: 0.0,
        angularAccel: 0.0,
        roadBankAngleRad: MathUtils.degToRad(3.0),
      );
      expect(vBank, closeTo(17.43, 0.05));
    });

    test('4. Slope-compensated forward acceleration cancels hill gravity leakage', () {
      // Driving on a 6% uphill grade: pitch = 3.43 degrees
      final pitchRad = MathUtils.degToRad(3.43);
      const measuredAx = 0.587; // Sensor reads 0.587 m/s^2 due to uphill tilt

      final netAx = MathUtils.slopeCompensatedForwardAccel(
        measuredFwdAccel: measuredAx,
        pitchRad: pitchRad,
      );
      expect(netAx, closeTo(0.0, 0.01)); // Net dynamic acceleration is zero!
    });

    test('5. EKF 15-state ESKF includes Van Loan process noise cross-coupling P[0..2, 3..5]', () {
      final ekf = Ekf3D();
      ekf.reset();

      // Propagate for 10 steps
      for (int i = 0; i < 10; i++) {
        ekf.predict(
          vehicleAccel: const Vec3(1.0, 0.0, 0.0),
          vehicleGyro: const Vec3(0.0, 0.0, 0.0),
          dt: 0.01,
          vehicleSpecificForce: const Vec3(1.0, 0.0, 9.80665),
        );
      }

      // Check cross-covariance between position (0..2) and velocity (3..5)
      final state = ekf.state;
      expect(state.covariance[0 * 9 + 3], greaterThan(0.0));
    });

    test('6. Unified 2D GNSS Doppler velocity vector update adjusts heading and velocity', () {
      final ekf = Ekf3D(initYaw: math.pi / 2); // Facing North (pi/2 rad)

      // True motion is 15 m/s Northbound: vEast = 0, vNorth = 15
      ekf.updateGnssVelocityVector(
        vEast: 0.0,
        vNorth: 15.0,
        hdop: 1.0,
        isDenied: false,
      );

      // Filter must absorb Northward velocity
      expect(ekf.state.velocity.y, greaterThan(1.0));
      expect(ekf.forwardSpeed, greaterThan(1.0));
    });

    test('7. Guarded pedestrian cadence detector rejects vehicular cruising motion', () {
      final engine = TcnSpeedEngine();

      // First establish normal vehicular driving (> 2.5 m/s cruising)
      for (int i = 0; i < 40; i++) {
        engine.predict(
          vehicleAccel: const Vec3(2.5, 0.0, 0.0),
          vehicleGyro: const Vec3(0.0, 0.0, 0.0),
          isShockGateActive: false,
          dt: 0.05,
        );
      }
      expect(engine.estimatedSpeed, greaterThan(2.5));

      // Now encounter rough road rumble:
      // Even with vertical vibrations and gyro motion, vehicular momentum locks out pedestrian false alarm!
      for (int i = 0; i < 30; i++) {
        final double zBounce = 3.8 * (i % 4 == 0 ? 1.0 : (i % 4 == 2 ? -1.0 : 0.0));
        engine.predict(
          vehicleAccel: Vec3(1.5, 0.2, zBounce),
          vehicleGyro: const Vec3(0.3, 0.2, 0.3),
          isShockGateActive: false,
          dt: 0.02,
        );
      }

      // Must NOT be classified as pedestrian because car has forward momentum
      expect(engine.isPedestrian, isFalse);
    });

    test('8. MapSnapper evaluates Menger curvature and dynamic lane deadbands', () {
      final branches = [
        const MapBranch(
          name: '4-Lane Highway',
          points: [
            Vec3(0.0, 0.0, 0.0),
            Vec3(100.0, 0.0, 0.0),
            Vec3(200.0, 50.0, 0.0),
          ],
          lanes: 4,
        ),
      ];

      final snapper = MapSnapper(branches: branches);
      final match = snapper.snapWithHeading(const Vec3(50.0, 2.0, 0.0), 0.0);

      expect(match, isNotNull);
      expect(match!.lanes, equals(4));
      // 4 lanes deadband = 4 * 3.5 / 2 = 7.0 meters
      expect(snapper.laneDeadband(match), equals(7.0));
    });

    test('9. Exact Van Loan IMU process noise evaluates cubic position and quadratic cross-covariance', () {
      const sa = 0.16; // (m/s^2)^2/Hz
      const dt = 0.01; // 100 Hz

      final vl = MathUtils.vanLoanProcessNoise(sa: sa, dt: dt);
      // q_vv = Sa * dt = 0.16 * 0.01 = 0.0016
      expect(vl.qvv, closeTo(0.0016, 1e-6));
      // q_pv = 0.5 * Sa * dt^2 = 0.5 * 0.16 * 0.0001 = 0.000008
      expect(vl.qpv, closeTo(8e-6, 1e-8));
      // q_pp = (1/3) * Sa * dt^3 = (1/3) * 0.16 * 0.000001 = 5.333e-8
      expect(vl.qpp, closeTo(5.333e-8, 1e-10));
    });

    test('10. 5-point Savitzky-Golay scalar filter computes smooth climb rate derivative', () {
      // Linear climb at 2.5 m/s: [100.0, 100.25, 100.5, 100.75, 101.0] with dt = 0.10s
      const dt = 0.10;
      final linearAlt = [100.0, 100.25, 100.5, 100.75, 101.0];
      final vzLinear = MathUtils.savitzkyGolayDerivative5Scalar(linearAlt, dt);
      expect(vzLinear, closeTo(2.5, 1e-3));

      // Constant altitude (zero climb):
      final flatAlt = [500.0, 500.0, 500.0, 500.0, 500.0];
      final vzFlat = MathUtils.savitzkyGolayDerivative5Scalar(flatAlt, dt);
      expect(vzFlat, closeTo(0.0, 1e-6));
    });

    test('11. Third-order baro-inertial vertical damping EKF update bounds vertical velocity', () {
      final ekf = Ekf3D();
      ekf.reset();

      // Introduce climbing barometric rate of 1.8 m/s
      for (int i = 0; i < 5; i++) {
        ekf.updateBaroClimbRate(1.8, sigmaVz: 0.30);
      }

      // Filter velocity z-state must absorb the barometric climb rate
      expect(ekf.state.velocity.z, greaterThan(0.5));
      expect(ekf.climbRate, greaterThan(0.5));
    });

    test('12. Iterated Extended Kalman Filter (IEKF) converges on non-linear curved map matches', () {
      final ekf = Ekf3D();
      ekf.reset();

      // Large initial cross-track error of 5.0m from road normal
      ekf.updateMapMatchingIterated(
        normal2D: const Vec3(0.0, 1.0, 0.0),
        crossTrackDistance: 5.0,
        sigma: 1.0,
        laneDeadbandM: 1.75,
        maxIterations: 2,
      );

      // Position should be pulled towards the road
      expect(ekf.state.position.y.abs(), greaterThan(0.5));
    });

    test('13. 3D magnetic ellipsoid least-squares fitting recovers hard-iron offset', () {
      // Synthesize noisy magnetic sphere shifted by hard-iron offset [15.0, -10.0, 5.0] uT
      const trueCenter = Vec3(15.0, -10.0, 5.0);
      final samples = <Vec3>[];
      for (int i = 0; i < 30; i++) {
        final theta = (i / 30.0) * 2.0 * math.pi;
        final phi = (i / 30.0) * math.pi - (math.pi / 2.0);
        final x = trueCenter.x + 45.0 * math.cos(phi) * math.cos(theta);
        final y = trueCenter.y + 45.0 * math.cos(phi) * math.sin(theta);
        final z = trueCenter.z + 45.0 * math.sin(phi);
        samples.add(Vec3(x, y, z));
      }

      final fit = MathUtils.fitMagneticEllipsoid(samples);
      expect(fit.center.x, closeTo(15.0, 2.5));
      expect(fit.center.y, closeTo(-10.0, 2.5));
      expect(fit.center.z, closeTo(5.0, 2.5));
    });

    test('14. C2-continuous cubic spline evaluates continuous tangent, curvature, and projection', () {
      // 90-degree bend from (0,0) to (100, 100)
      final spline = CubicSpline3D.fromPoints([
        const Vec3(0.0, 0.0, 0.0),
        const Vec3(50.0, 10.0, 0.0),
        const Vec3(80.0, 50.0, 0.0),
        const Vec3(100.0, 100.0, 0.0),
      ]);

      expect(spline.totalLength, greaterThan(100.0));

      // Tangent at start points mostly East (+X)
      final t0 = spline.evaluateTangent(5.0);
      expect(t0.x, greaterThan(0.8));

      // Normal is perpendicular
      final n0 = spline.evaluateNormal2D(5.0);
      expect(t0.dot(n0), closeTo(0.0, 1e-4));

      // Curvature is positive along the curve
      final kappa = spline.evaluateCurvature(spline.totalLength * 0.5);
      expect(kappa, greaterThan(0.0));

      // Orthogonal projection of nearby point
      final proj = spline.projectPoint(const Vec3(50.0, 12.0, 0.0));
      expect(proj.distance, closeTo(2.0, 0.5));
    });
  });
}
