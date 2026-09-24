import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:idr_navigator/core/math_utils.dart';
import 'package:idr_navigator/models/ekf_state.dart';
import 'package:idr_navigator/models/nav_solution.dart';
import 'package:idr_navigator/services/cabin_alignment.dart';
import 'package:idr_navigator/services/ekf_3d.dart';
import 'package:idr_navigator/services/tcn_speed_engine.dart';

void main() {
  group('Phone In-Hand Rotation & Speed Accuracy Suite', () {
    test('Continuous 360° yaw rotation in hand while stationary keeps speed at 0.0 and zero drift', () {
      final aligner = CabinAligner();
      final tcn = TcnSpeedEngine();
      final ekf = Ekf3D();

      const dt = 0.01;
      const yawRate = 2.0; // 2 rad/s (~114 deg/s)
      final totalSteps = (2 * math.pi / (yawRate * dt)).ceil(); // Full 360°

      // Earth gravity vector in world frame
      const g = 9.80665;

      for (int i = 0; i < totalSteps; i++) {
        final angle = yawRate * i * dt;

        // Rotating phone horizontally in hand (flat on palm):
        // Gravity remains [0, 0, g], but gyro shows active yaw rotation [0, 0, 2.0]
        final rawAccel = Vec3(0.003 * math.sin(angle), 0.003 * math.cos(angle), g);
        final rawGyro = const Vec3(0.002, -0.001, yawRate);

        aligner.ingest(rawAccel, rawGyro, dt: dt);
        final aVeh = aligner.transformAccel(rawAccel);
        final wVeh = aligner.transformGyro(rawGyro);

        final speed = tcn.predict(
          vehicleAccel: aVeh,
          vehicleGyro: wVeh,
          isShockGateActive: false,
          dt: dt,
        );

        if (tcn.isStationary) {
          ekf.applyStandstill(wVeh.z, aVeh.x);
        } else {
          ekf.predict(
            vehicleAccel: aVeh,
            vehicleGyro: wVeh,
            dt: dt,
            vTcn: speed,
          );
        }

        expect(tcn.isStationary, isTrue, reason: 'Standstill must NOT break during hand yaw rotation at step $i');
        expect(tcn.estimatedSpeed, equals(0.0), reason: 'Speed must be 0.0 at step $i');
      }

      expect(ekf.state.position.norm, lessThan(0.001), reason: 'Position drift must be 0.0m after 360° spin');
      expect(ekf.forwardSpeed, equals(0.0));
    });

    test('Violent 3D tumbling in hand (pitch, roll, yaw at 2-3 rad/s) keeps speed at 0.0 and zero drift', () {
      final aligner = CabinAligner();
      final tcn = TcnSpeedEngine();
      final ekf = Ekf3D();

      const dt = 0.01;
      const g = 9.80665;

      double curRoll = 0.0;
      double curPitch = 0.0;
      double curYaw = 0.0;

      for (int i = 0; i < 300; i++) {
        // Varying 3D angular velocities mimicking phone held and manipulated in hand
        final wx = 1.5 * math.sin(i * 0.08);
        final wy = 1.8 * math.cos(i * 0.06);
        final wz = 2.2 * math.sin(i * 0.05);

        curRoll += wx * dt;
        curPitch += wy * dt;
        curYaw += wz * dt;

        // Current rotation matrix from world to phone
        final cr = math.cos(curRoll);
        final sr = math.sin(curRoll);
        final cp = math.cos(curPitch);
        final sp = math.sin(curPitch);
        final cy = math.cos(curYaw);
        final sy = math.sin(curYaw);

        final rRoll = Mat3([
          1.0, 0.0, 0.0,
          0.0, cr, -sr,
          0.0, sr, cr,
        ]);
        final rPitch = Mat3([
          cp, 0.0, sp,
          0.0, 1.0, 0.0,
          -sp, 0.0, cp,
        ]);
        final rYaw = Mat3([
          cy, -sy, 0.0,
          sy, cy, 0.0,
          0.0, 0.0, 1.0,
        ]);

        final rWorldToPhone = rYaw * (rPitch * rRoll);
        // Gravity [0, 0, g] expressed in rotated phone sensor coordinates
        final sensorG = rWorldToPhone.transform(const Vec3(0.0, 0.0, g));

        // Add slight physiological hand tremor noise (0.05 m/s^2)
        final rawAccel = sensorG + Vec3(0.02 * math.sin(i * 0.3), 0.02 * math.cos(i * 0.3), 0.01);
        final rawGyro = Vec3(wx, wy, wz);

        aligner.ingest(rawAccel, rawGyro, dt: dt);
        final aVeh = aligner.transformAccel(rawAccel);
        final wVeh = aligner.transformGyro(rawGyro);

        final speed = tcn.predict(
          vehicleAccel: aVeh,
          vehicleGyro: wVeh,
          isShockGateActive: false,
          dt: dt,
        );

        if (tcn.isStationary) {
          ekf.applyStandstill(wVeh.z, aVeh.x);
        } else {
          ekf.predict(
            vehicleAccel: aVeh,
            vehicleGyro: wVeh,
            dt: dt,
            vTcn: speed,
          );
        }

        // After initial 10-sample convergence, phone rotation must maintain zero speed and standstill
        if (i > 15) {
          expect(tcn.isStationary, isTrue, reason: 'Standstill must hold during 3D tumbling at step $i');
          expect(tcn.estimatedSpeed, equals(0.0));
        }
      }

      expect(ekf.state.position.norm, lessThan(0.01), reason: 'Position drift must be negligible after 300 steps of tumbling');
    });

    test('NavSolution master speed hierarchy correctly prioritizes GNSS Doppler and snaps to 0 at rest', () {
      final dummyCov = List<double>.filled(81, 0.0);

      // Scenario 1: Stationary vehicle with GNSS speed near 0
      final stoppedState = EkfState(
        position: Vec3.zero,
        velocity: Vec3.zero,
        attitude: Vec3.zero,
        covariance: dummyCov,
      );
      final stoppedSolution = NavSolution(
        timestamp: 100.0,
        idrState: stoppedState,
        classicDrState: stoppedState,
        gnssStatus: GnssStatus.available,
        hdop: 1.0,
        isGnssDenied: false,
        idrDriftError: 0.0,
        classicDriftError: 0.0,
        shockDetected: false,
        rawJerk: 0.0,
        jerkVariance: 0.0,
        tcnEstimatedSpeed: 0.0,
        baroAltitude: 10.0,
        cabinConfidence: 1.0,
        isCabinLocked: true,
        mountPitchDeg: 0.0,
        mountRollDeg: 0.0,
        gnssSpeed: 0.1, // 0.1 m/s (creeping noise below 0.5 m/s threshold)
      );
      expect(stoppedSolution.speedKmh, equals(0.0), reason: 'Stopped vehicle must show exactly 0.0 km/h');

      // Scenario 2: Nominal highway driving with active GNSS (54 km/h = 15.0 m/s)
      final cruisingState = EkfState(
        position: const Vec3(100.0, 50.0, 0.0),
        velocity: const Vec3(15.0, 0.0, 0.0),
        attitude: Vec3.zero,
        covariance: dummyCov,
      );
      final cruisingSolution = NavSolution(
        timestamp: 105.0,
        idrState: cruisingState,
        classicDrState: cruisingState,
        gnssStatus: GnssStatus.available,
        hdop: 1.1,
        isGnssDenied: false,
        idrDriftError: 0.0,
        classicDriftError: 0.0,
        shockDetected: false,
        rawJerk: 0.0,
        jerkVariance: 0.0,
        tcnEstimatedSpeed: 14.8, // Slightly different IMU estimate
        baroAltitude: 10.0,
        cabinConfidence: 1.0,
        isCabinLocked: true,
        mountPitchDeg: 0.0,
        mountRollDeg: 0.0,
        gnssSpeed: 15.0, // Ground truth Doppler: exactly 15.0 m/s = 54.0 km/h
      );
      expect(cruisingSolution.speedKmh, closeTo(54.0, 0.01), reason: 'Must track ground truth GNSS Doppler speed');

      // Scenario 3: Tunnel outage (GNSS denied, dead reckoning active)
      final tunnelSolution = NavSolution(
        timestamp: 110.0,
        idrState: cruisingState,
        classicDrState: cruisingState,
        gnssStatus: GnssStatus.denied,
        hdop: 25.0,
        isGnssDenied: true,
        idrDriftError: 1.2,
        classicDriftError: 4.5,
        shockDetected: false,
        rawJerk: 0.0,
        jerkVariance: 0.0,
        tcnEstimatedSpeed: 15.0,
        baroAltitude: 10.0,
        cabinConfidence: 1.0,
        isCabinLocked: true,
        mountPitchDeg: 0.0,
        mountRollDeg: 0.0,
        gnssSpeed: null,
      );
      expect(tunnelSolution.speedKmh, closeTo(54.0, 0.01), reason: 'In tunnel, speed tracks calibrated EKF state');
    });

    test('Ekf3D updateGnssSpeed fuses Doppler velocity and snaps to zero at standstill', () {
      final ekf = Ekf3D();

      // Update with GNSS speed 20.0 m/s (72 km/h)
      for (int i = 0; i < 10; i++) {
        ekf.updateGnssSpeed(20.0, 1.0);
      }
      expect(ekf.forwardSpeed, closeTo(20.0, 0.5));

      // Update with GNSS speed < 0.5 m/s (confirmed stop)
      ekf.updateGnssSpeed(0.2, 1.5);
      expect(ekf.forwardSpeed, equals(0.0), reason: 'Forward speed must snap to 0 on stop');
    });
  });
}
