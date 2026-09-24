import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:idr_navigator/core/math_utils.dart';
import 'package:idr_navigator/models/ekf_state.dart';
import 'package:idr_navigator/models/nav_solution.dart';
import 'package:idr_navigator/services/ekf_3d.dart';
import 'package:idr_navigator/services/tcn_speed_engine.dart';
import 'package:idr_navigator/services/vibration_gate.dart';

void main() {
  group('Idle Standstill and Compass Fix Tests', () {
    test('TcnSpeedEngine firmly locks to 0.0 km/h during idle', () {
      final engine = TcnSpeedEngine();

      // Feed 30 stationary samples with small MEMS noise (< 0.05 m/s^2)
      for (int i = 0; i < 30; i++) {
        final speed = engine.predict(
          vehicleAccel: const Vec3(0.02, -0.01, 0.01),
          vehicleGyro: const Vec3(0.002, 0.001, -0.003),
          isShockGateActive: false,
          dt: 0.02,
        );
        if (i > 22) {
          expect(engine.isStationary, isTrue);
          expect(speed, equals(0.0));
        }
      }
    });

    test('TcnSpeedEngine firmly locks to 0.0 km/h during real vehicle engine idle vibration', () {
      final engine = TcnSpeedEngine();

      // Simulate 50 samples of real car engine idle (20 Hz vibration, variance ~ 1.5 m^2/s^4)
      for (int i = 0; i < 50; i++) {
        final t = i * 0.02;
        final vibX = 0.20 + 1.2 * math.sin(2 * math.pi * 20 * t);
        final vibY = 0.10 + 0.8 * math.cos(2 * math.pi * 20 * t);
        final vibZ = 0.05 + 1.0 * math.sin(2 * math.pi * 20 * t + 1.0);
        final gyroZ = 0.02 * math.sin(2 * math.pi * 20 * t);

        final speed = engine.predict(
          vehicleAccel: Vec3(vibX, vibY, vibZ),
          vehicleGyro: Vec3(0.01, 0.01, gyroZ),
          isShockGateActive: false,
          dt: 0.02,
        );

        if (i >= 25) {
          expect(engine.isStationary, isTrue);
          expect(speed, equals(0.0));
        }
      }

      // Now simulate vehicle throttle launch (forward acceleration jumps by +1.5 m/s^2)
      for (int i = 0; i < 15; i++) {
        engine.predict(
          vehicleAccel: const Vec3(1.8, 0.1, 0.0),
          vehicleGyro: const Vec3(0.01, 0.01, 0.01),
          isShockGateActive: false,
          dt: 0.02,
        );
      }

      // Must break out of standstill on launch
      expect(engine.isStationary, isFalse);
      expect(engine.estimatedSpeed, greaterThan(0.0));
    });

    test('TcnSpeedEngine stays firmly locked to 0.0 km/h when phone is rotated on a table', () {
      final engine = TcnSpeedEngine();

      // First 25 samples: resting stationary on table
      for (int i = 0; i < 25; i++) {
        engine.predict(
          vehicleAccel: const Vec3(0.02, 0.01, 0.02),
          vehicleGyro: const Vec3(0.001, 0.001, -0.002),
          isShockGateActive: false,
          dt: 0.02,
        );
      }
      expect(engine.isStationary, isTrue);
      expect(engine.estimatedSpeed, equals(0.0));

      // Next 50 samples: user rotates the phone on the table (yaw rotation 1.0 - 2.5 rad/s)
      // Without translational forward or centripetal lateral acceleration
      for (int i = 0; i < 50; i++) {
        final t = i * 0.02;
        final speed = engine.predict(
          vehicleAccel: Vec3(
            0.02 + 0.05 * math.sin(t * 10), // Small table friction
            0.01 + 0.05 * math.cos(t * 10), // No centripetal lateral force (< 0.50 m/s^2)
            0.02,
          ),
          vehicleGyro: const Vec3(0.02, 0.01, 1.8), // Pure fast yaw rotation on table (1.8 rad/s ~ 103 deg/s)
          isShockGateActive: false,
          dt: 0.02,
        );

        // Speed MUST remain strictly 0.0 km/h and standstill must NOT break!
        expect(engine.isStationary, isTrue);
        expect(speed, equals(0.0));
      }
    });

    test('VibrationGate never trips shock gate while stationary', () {
      final gate = VibrationGate();

      // 50 samples at idle
      for (int i = 0; i < 50; i++) {
        gate.process(
          const Vec3(0.03, 0.02, -0.02),
          0.02,
          isStationary: true,
        );
        expect(gate.isShockDetected, isFalse);
        expect(gate.trustWeight, equals(1.0));
        expect(gate.lastVariance, equals(0.0));
      }
    });

    test('Tilt-compensated compass computes exact cardinal headings', () {
      const gravity = Vec3(0.0, 0.0, 9.80665); // flat phone face up

      // 1. Top of phone points North: mag field points along +Y
      final northHeading = MathUtils.computeTiltCompensatedHeading(
        gravity: gravity,
        magneticField: const Vec3(0.0, 30.0, -20.0),
      );
      expect(MathUtils.radToDeg(northHeading), closeTo(0.0, 1.0));

      // 2. Top of phone points East: mag field points along -X
      final eastHeading = MathUtils.computeTiltCompensatedHeading(
        gravity: gravity,
        magneticField: const Vec3(-30.0, 0.0, -20.0),
      );
      expect(MathUtils.radToDeg(eastHeading), closeTo(90.0, 1.0));

      // 3. Top of phone points South: mag field points along -Y
      final southHeading = MathUtils.computeTiltCompensatedHeading(
        gravity: gravity,
        magneticField: const Vec3(0.0, -30.0, -20.0),
      );
      expect(MathUtils.radToDeg(southHeading).abs(), closeTo(180.0, 1.0));

      // 4. Top of phone points West: mag field points along +X
      final westHeading = MathUtils.computeTiltCompensatedHeading(
        gravity: gravity,
        magneticField: const Vec3(30.0, 0.0, -20.0),
      );
      expect(MathUtils.radToDeg(westHeading), closeTo(-90.0, 1.0));
      expect(MathUtils.enuToCompassDeg(MathUtils.compassToEnuRad(270.0)), closeTo(270.0, 0.1));
    });

    test('NavSolution.headingDeg maps Cartesian ENU angle into [0, 360) navigational azimuth', () {
      // East in ENU: yaw = 0 rad -> Navigational Compass = 90 deg East
      final solEast = NavSolution(
        timestamp: 1.0,
        idrState: const EkfState(
          position: Vec3.zero,
          velocity: Vec3.zero,
          attitude: Vec3(0.0, 0.0, 0.0),
          covariance: [],
        ),
        classicDrState: const EkfState(
          position: Vec3.zero,
          velocity: Vec3.zero,
          attitude: Vec3.zero,
          covariance: [],
        ),
        gnssStatus: GnssStatus.available,
        hdop: 1.0,
        isGnssDenied: false,
        idrDriftError: 0.0,
        classicDriftError: 0.0,
        shockDetected: false,
        rawJerk: 0.0,
        jerkVariance: 0.0,
        tcnEstimatedSpeed: 0.0,
        baroAltitude: 0.0,
        cabinConfidence: 1.0,
        isCabinLocked: true,
        mountPitchDeg: 0.0,
        mountRollDeg: 0.0,
      );
      expect(solEast.headingDeg, closeTo(90.0, 0.1));

      // North in ENU: yaw = pi/2 rad -> Navigational Compass = 0 deg North
      final solNorth = NavSolution(
        timestamp: 1.0,
        idrState: const EkfState(
          position: Vec3.zero,
          velocity: Vec3.zero,
          attitude: Vec3(0.0, 0.0, math.pi / 2.0),
          covariance: [],
        ),
        classicDrState: const EkfState(
          position: Vec3.zero,
          velocity: Vec3.zero,
          attitude: Vec3.zero,
          covariance: [],
        ),
        gnssStatus: GnssStatus.available,
        hdop: 1.0,
        isGnssDenied: false,
        idrDriftError: 0.0,
        classicDriftError: 0.0,
        shockDetected: false,
        rawJerk: 0.0,
        jerkVariance: 0.0,
        tcnEstimatedSpeed: 0.0,
        baroAltitude: 0.0,
        cabinConfidence: 1.0,
        isCabinLocked: true,
        mountPitchDeg: 0.0,
        mountRollDeg: 0.0,
      );
      expect(solNorth.headingDeg, closeTo(0.0, 0.1));
    });

    test('Ekf3D trims gyro bias when stationary and learns from GNSS course when moving', () {
      final ekf = Ekf3D();

      // Stationary phone with 0.03 rad/s gyro bias
      for (int i = 0; i < 50; i++) {
        ekf.applyStandstill(0.03);
      }
      expect(ekf.gyroBiasZ, closeTo(0.03, 0.01));
      expect(ekf.forwardSpeed, equals(0.0));

      // Moving vehicle with GNSS ground track course
      // Driving East (ENU angle = 0 rad), vehicle heading currently offset by 0.2 rad
      ekf.updateCourse(0.0, 10.0, hdop: 1.0);
      expect(ekf.headingRad.abs(), lessThan(0.2));
    });

    test('Ekf3D standstill eliminates idle drift and contracts covariance towards 0.01 floor', () {
      final ekf = Ekf3D();

      // Initial position variance is 1.0 m^2
      expect(ekf.state.covariance[0], equals(1.0));

      // Feed 100 stationary cycles with forward accel bias (0.05 m/s^2) and gyro bias (0.02 rad/s)
      for (int i = 0; i < 100; i++) {
        ekf.applyStandstill(0.02, 0.05);
      }

      // Position must not have drifted AT ALL
      expect(ekf.state.position.x, equals(0.0));
      expect(ekf.state.position.y, equals(0.0));
      expect(ekf.state.position.z, equals(0.0));

      // Covariance must have contracted well below 1.0 m^2 towards 0.01 m^2 floor
      final covPx = ekf.state.covariance[0];
      final covPy = ekf.state.covariance[1 * 9 + 1];
      expect(covPx, lessThan(0.5));
      expect(covPx, greaterThanOrEqualTo(0.01));
      expect(covPy, lessThan(0.5));
      expect(covPy, greaterThanOrEqualTo(0.01));

      // Forward accelerometer bias must be estimated accurately
      expect(ekf.accelBiasX, closeTo(0.05, 0.01));
      // Gyro bias must be estimated accurately
      expect(ekf.gyroBiasZ, closeTo(0.02, 0.005));
    });

    test('Ekf3D compass update respects angular deadband', () {
      final ekf = Ekf3D();
      ekf.initializeHeading(0.0);

      // Magnetic fluctuation of 0.015 rad (< 0.02 rad deadband) must be ignored
      ekf.updateCompass(0.015, isStationary: true);
      expect(ekf.headingRad, equals(0.0));

      // True heading change > 0.02 rad is gently updated
      ekf.updateCompass(0.10, isStationary: true);
      expect(ekf.headingRad, greaterThan(0.0));
      expect(ekf.headingRad, lessThan(0.05));
    });
  });
}
