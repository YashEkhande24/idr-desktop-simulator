import 'package:flutter_test/flutter_test.dart';
import 'package:idr_navigator/core/math_utils.dart';

void main() {
  group('MathUtils Advanced Filtering & Quaternion Tests', () {
    test('Quaternion identity and multiplication', () {
      final q1 = Quaternion.identity;
      final q2 = Quaternion.fromEuler(0.1, 0.2, 0.3);
      final prod = q1 * q2;

      expect(prod.w, closeTo(q2.w, 1e-6));
      expect(prod.x, closeTo(q2.x, 1e-6));
      expect(prod.y, closeTo(q2.y, 1e-6));
      expect(prod.z, closeTo(q2.z, 1e-6));
    });

    test('Quaternion vector rotation aligns with Euler rotation matrix', () {
      const roll = 0.2;
      const pitch = -0.3;
      const yaw = 0.5;

      final q = Quaternion.fromEuler(roll, pitch, yaw);
      final mat = Mat3.fromEuler(roll, pitch, yaw);
      const v = Vec3(1.0, 2.0, 3.0);

      final vRotQuat = q.rotate(v);
      final vRotMat = mat.transform(v);

      expect(vRotQuat.x, closeTo(vRotMat.x, 1e-4));
      expect(vRotQuat.y, closeTo(vRotMat.y, 1e-4));
      expect(vRotQuat.z, closeTo(vRotMat.z, 1e-4));
    });

    test('Quaternion Euler round-trip conversions', () {
      const roll = 0.35;
      const pitch = -0.22;
      const yaw = 1.15;

      final q = Quaternion.fromEuler(roll, pitch, yaw);
      final euler = q.toEuler();

      expect(euler.roll, closeTo(roll, 1e-5));
      expect(euler.pitch, closeTo(pitch, 1e-5));
      expect(euler.yaw, closeTo(yaw, 1e-5));
    });

    test('Huber M-estimation weight downweights outliers smoothly', () {
      expect(MathUtils.huberWeight(0.5, k: 1.345), equals(1.0));
      expect(MathUtils.huberWeight(1.345, k: 1.345), equals(1.0));
      expect(MathUtils.huberWeight(2.69, k: 1.345), closeTo(0.5, 1e-3));
      expect(MathUtils.huberWeight(13.45, k: 1.345), closeTo(0.1, 1e-3));
    });

    test('Chi-square gating distinguishes inliers from extreme outliers', () {
      // 1 DOF: critical value ~6.635 for p=0.01
      expect(MathUtils.passChiSquareGate(2.0, 1), isTrue);
      expect(MathUtils.passChiSquareGate(10.0, 1), isFalse);

      // 3 DOF: critical value ~14.16 for 3-sigma
      expect(MathUtils.passChiSquareGate(5.0, 3, pValue: 0.0027), isTrue);
      expect(MathUtils.passChiSquareGate(25.0, 3, pValue: 0.0027), isFalse);
    });

    test('Savitzky-Golay quadratic derivative computes smooth derivative', () {
      // Linear ramp: y(t) = 5 * t => derivative should be exactly 5.0
      const dt = 0.02;
      final window = List.generate(
        5,
        (i) => Vec3(5.0 * (i * dt), 0.0, 0.0),
      );

      final deriv = MathUtils.savitzkyGolayDerivative5(window, dt);
      expect(deriv.x, closeTo(5.0, 1e-3));
      expect(deriv.y, closeTo(0.0, 1e-3));
    });

    test('Bortz coning vector correctly evaluates cross product correction', () {
      const prevTheta = Vec3(0.1, 0.0, 0.0);
      const currTheta = Vec3(0.0, 0.2, 0.0);
      final coning = MathUtils.bortzConingVector(prevTheta, currTheta);
      // (prevTheta x currTheta) = [0, 0, 0.02]
      // coning = [0, 0, 0.02 / 12] = 0.00166667
      expect(coning.x, equals(0.0));
      expect(coning.y, equals(0.0));
      expect(coning.z, closeTo(0.02 / 12.0, 1e-6));
    });

    test('SE(2) arc step yields exact arc integration on turning vehicle', () {
      // Vehicle moving at 10 m/s heading East (yaw = 0), turning Left with omegaZ = 0.5 rad/s over 0.2s
      const speed = 10.0;
      const yaw = 0.0;
      const omegaZ = 0.5;
      const dt = 0.2;

      final arc = MathUtils.arcStepSE2(speed: speed, yaw: yaw, omegaZ: omegaZ, dt: dt);
      // Theoretical dx = 10 * (sin(0.1) - sin(0)) / 0.5 = 20 * sin(0.1) = 1.99667
      // Theoretical dy = 10 * (-cos(0.1) + cos(0)) / 0.5 = 20 * (1 - cos(0.1)) = 0.09983
      expect(arc.dx, closeTo(1.99667, 1e-4));
      expect(arc.dy, closeTo(0.09983, 1e-4));
    });

    test('Calibrated sea level pressure and altitude round-trip', () {
      const trueAlt = 450.0; // 450m elevation
      // At 450m, pressure is approx 960 hPa with standard sea level 1013.25
      const pBaro = 960.0;
      final p0 = MathUtils.calibratedSeaLevelPressure(pBaro, trueAlt);
      final altRecalculated = MathUtils.altitudeFromCalibratedPressure(pBaro, p0);
      expect(altRecalculated, closeTo(trueAlt, 1e-3));
    });

    test('Magnetic dip angle evaluates true inclination against gravity', () {
      // In northern hemisphere, field points forward and down:
      const gravity = Vec3(0.0, 0.0, 9.80665); // UP in sensor rest frame
      const magField = Vec3(20.0, 0.0, 35.0); // Z is 35 uT down towards earth
      final dip = MathUtils.magneticDipAngle(magField, gravity);
      expect(dip, greaterThan(0.5)); // positive inclination (~60 degrees)
    });

    test('Somigliana WGS84 normal gravity evaluates accurate regional gravity field', () {
      // Equator: ~9.7803 m/s^2
      final gEquator = MathUtils.wgs84NormalGravity(0.0);
      expect(gEquator, closeTo(9.7803, 1e-3));

      // Bangalore / Southern India (~12.97 deg N): ~9.783 m/s^2
      final gBangalore = MathUtils.wgs84NormalGravity(12.97);
      expect(gBangalore, closeTo(9.7831, 1e-3));

      // Mumbai / Western India (~19.07 deg N): ~9.786 m/s^2
      final gMumbai = MathUtils.wgs84NormalGravity(19.076);
      expect(gMumbai, closeTo(9.7863, 1e-3));

      // Delhi / Northern India (~28.61 deg N): ~9.792 m/s^2
      final gDelhi = MathUtils.wgs84NormalGravity(28.61);
      expect(gDelhi, closeTo(9.7924, 1e-3));

      // North Pole (90 deg N): ~9.8322 m/s^2
      final gPole = MathUtils.wgs84NormalGravity(90.0);
      expect(gPole, closeTo(9.8322, 1e-3));
    });

    test('Dynamic Coriolis acceleration computes exact ENU components from latitude', () {
      // Vehicle driving East (v_x = 20 m/s) at Mumbai (19.07 deg N)
      final vNav = const Vec3(20.0, 0.0, 0.0);
      final aCor = MathUtils.coriolisAcceleration(vNav, 19.076);
      // a_x = 0
      // a_y = -2 * w * sin(19.07 deg) * v_x < 0 (pushes South in Northern hemisphere)
      // a_z = 2 * w * cos(19.07 deg) * v_x > 0 (Eötvös effect: upward lift for Eastbound motion)
      expect(aCor.x, equals(0.0));
      expect(aCor.y, lessThan(0.0));
      expect(aCor.z, greaterThan(0.0));
    });

    test('Adaptive NHC lateral variance relaxes under cornering tire slip', () {
      const nominalVar = 0.02;
      // Driving straight (latAccel = 0): remains at nominal variance
      final vStraight = MathUtils.adaptiveNhcLatVariance(nominalVar, 0.0, 20.0);
      expect(vStraight, equals(nominalVar));

      // High-speed curve (latAccel = 3.5 m/s^2 at 80 km/h = 22.2 m/s):
      final vCornering = MathUtils.adaptiveNhcLatVariance(nominalVar, 3.5, 22.2);
      expect(vCornering, greaterThan(nominalVar * 1.5));
      expect(vCornering, lessThanOrEqualTo(0.45));
    });

    test('Hard-iron magnetic offset estimator computes centroid of bounding sphere', () {
      final magSamples = [
        const Vec3(10.0, 20.0, 30.0),
        const Vec3(30.0, 40.0, 50.0),
        const Vec3(20.0, 30.0, 40.0),
        const Vec3(15.0, 25.0, 35.0),
        const Vec3(25.0, 35.0, 45.0),
        const Vec3(10.0, 30.0, 40.0),
        const Vec3(30.0, 30.0, 40.0),
        const Vec3(20.0, 20.0, 40.0),
        const Vec3(20.0, 40.0, 40.0),
        const Vec3(20.0, 30.0, 30.0),
        const Vec3(20.0, 30.0, 50.0),
      ];
      final offset = MathUtils.hardIronOffsetEstimate(magSamples);
      expect(offset.x, closeTo(20.0, 1e-3));
      expect(offset.y, closeTo(30.0, 1e-3));
      expect(offset.z, closeTo(40.0, 1e-3));
    });

    test('C1 Hermite backward bridge smoother smoothly transitions terminal drift without kinks', () {
      // 5-point straight outage trajectory drifting in y by 10 meters at the end
      final raw = [
        const Vec3(0.0, 0.0, 0.0),   // Start of outage (index 0)
        const Vec3(10.0, 1.0, 0.0),
        const Vec3(20.0, 3.0, 0.0),
        const Vec3(30.0, 6.0, 0.0),
        const Vec3(40.0, 10.0, 0.0), // End of outage (index 4) - drifted by +10 in Y
      ];
      // True position at end should have been Y = 0. Terminal correction = (0, -10, 0)
      const correction = Vec3(0.0, -10.0, 0.0);
      final smoothed = MathUtils.smoothOutageTrajectory(
        trajectory: raw,
        outageStartIndex: 0,
        terminalCorrection: correction,
      );

      // Start point should remain untouched (correction = 0)
      expect(smoothed[0].y, equals(0.0));
      // End point should have exact terminal correction applied (10.0 - 10.0 = 0.0)
      expect(smoothed[4].y, closeTo(0.0, 1e-3));
      // Intermediate points should be smoothly shifted
      expect(smoothed[2].y, lessThan(raw[2].y));
    });
  });
}
