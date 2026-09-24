import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:idr_navigator/core/math_utils.dart';
import 'package:idr_navigator/services/cabin_alignment.dart';
import 'package:idr_navigator/services/tcn_speed_engine.dart';
import 'package:idr_navigator/services/ekf_3d.dart';
import 'package:idr_navigator/services/baseline_dr.dart';

void main() {
  group('Hand-Held Stationary Phone Zero Drift Suite', () {
    test('Hand-held phone with 35° reading tilt and 3-axis tremor maintains 0.0 km/h and 0.0m drift', () {
      final aligner = CabinAligner();
      final tcn = TcnSpeedEngine();
      final ekf = Ekf3D();
      final classicDr = BaselineDr();

      final rollAngle = 15.0 * math.pi / 180.0;
      final pitchAngle = 35.0 * math.pi / 180.0;

      final cr = math.cos(rollAngle);
      final sr = math.sin(rollAngle);
      final cp = math.cos(pitchAngle);
      final sp = math.sin(pitchAngle);

      final rRoll = Mat3([
        1.0, 0.0, 0.0,
        0.0, cr,  -sr,
        0.0, sr,   cr,
      ]);
      final rPitch = Mat3([
        cp,  0.0, sp,
        0.0, 1.0, 0.0,
        -sp, 0.0, cp,
      ]);
      final rBv = rPitch * rRoll;

      final trueG = const Vec3(0, 0, 9.80665);
      final phoneG = rBv.transpose.transform(trueG);

      Vec3? posAtLock;

      // Simulate 300 samples (3.0 seconds @ 100 Hz) of realistic hand-held holding
      for (int i = 0; i < 300; i++) {
        final t = i * 0.01;
        // 8-10 Hz physiological hand tremor on accel (amplitude ~0.15 m/s^2)
        final tremorAx = 0.12 * math.sin(2 * math.pi * 8.5 * t);
        final tremorAy = 0.15 * math.cos(2 * math.pi * 9.0 * t);
        final tremorAz = 0.10 * math.sin(2 * math.pi * 8.0 * t + 0.5);

        // 8-10 Hz 3-axis angular tremor on gyro (w_roll ~0.08, w_pitch ~0.12, w_yaw ~0.05 rad/s)
        // Total gyro norm is ~0.15 rad/s (> 0.08 rad/s threshold)
        final tremorGx = 0.08 * math.sin(2 * math.pi * 8.5 * t);
        final tremorGy = 0.12 * math.cos(2 * math.pi * 9.0 * t);
        final tremorGz = 0.05 * math.sin(2 * math.pi * 7.5 * t);

        final rawAccel = phoneG + Vec3(tremorAx, tremorAy, tremorAz);
        final rawGyro = Vec3(tremorGx, tremorGy, tremorGz);

        aligner.ingest(rawAccel, rawGyro, dt: 0.01);
        final aVeh = aligner.transformAccel(rawAccel);
        final wVeh = aligner.transformGyro(rawGyro);

        final speed = tcn.predict(
          vehicleAccel: aVeh,
          vehicleGyro: wVeh,
          isShockGateActive: false,
          dt: 0.01,
        );

        if (tcn.isStationary) {
          posAtLock ??= ekf.state.position;
          ekf.applyStandstill(wVeh.z, aVeh.x);
          classicDr.syncWithGnss(
            position: classicDr.state.position,
            velocity: Vec3.zero,
            yaw: classicDr.state.yaw,
          );
        } else {
          ekf.predict(
            vehicleAccel: aVeh,
            vehicleGyro: wVeh,
            dt: 0.01,
            vTcn: speed,
          );
          classicDr.step(vehicleAccel: aVeh, vehicleGyro: wVeh, dt: 0.01);
        }
      }

      expect(tcn.isStationary, isTrue);
      expect(tcn.estimatedSpeed, equals(0.0));
      if (posAtLock != null) {
        final driftAfterLock = (ekf.state.position - posAtLock).norm;
        expect(driftAfterLock, lessThan(0.001), reason: 'Position must not drift while held in hand');
      }
    });

    test('Hand tilt change (re-adjusting grip from 25° to 45° in hand) maintains zero drift', () {
      final aligner = CabinAligner();
      final tcn = TcnSpeedEngine();
      final ekf = Ekf3D();
      final classicDr = BaselineDr();

      Vec3? posAtLock;

      // 500 samples (5.0 seconds): user dynamically adjusts hand tilt from 25° to 45°
      for (int i = 0; i < 500; i++) {
        final t = i * 0.01;
        // Dynamically changing pitch angle from 25° to 45°
        final pitchAngle = (25.0 + 10.0 * math.sin(t * 0.5)) * math.pi / 180.0;
        final rollAngle = (10.0 + 5.0 * math.cos(t * 0.5)) * math.pi / 180.0;

        final cr = math.cos(rollAngle);
        final sr = math.sin(rollAngle);
        final cp = math.cos(pitchAngle);
        final sp = math.sin(pitchAngle);

        final rRoll = Mat3([
          1.0, 0.0, 0.0,
          0.0, cr,  -sr,
          0.0, sr,   cr,
        ]);
        final rPitch = Mat3([
          cp,  0.0, sp,
          0.0, 1.0, 0.0,
          -sp, 0.0, cp,
        ]);
        final rBv = rPitch * rRoll;

        final trueG = const Vec3(0, 0, 9.80665);
        final phoneG = rBv.transpose.transform(trueG);

        // Hand tremor
        final tremorAx = 0.10 * math.sin(2 * math.pi * 8.0 * t);
        final tremorAy = 0.12 * math.cos(2 * math.pi * 9.0 * t);
        final tremorAz = 0.08 * math.sin(2 * math.pi * 7.5 * t);

        final tremorGx = 0.06 * math.sin(2 * math.pi * 8.0 * t);
        final tremorGy = 0.10 * math.cos(2 * math.pi * 9.0 * t);
        final tremorGz = 0.04 * math.sin(2 * math.pi * 7.5 * t);

        final rawAccel = phoneG + Vec3(tremorAx, tremorAy, tremorAz);
        final rawGyro = Vec3(tremorGx, tremorGy, tremorGz);

        aligner.ingest(rawAccel, rawGyro, dt: 0.01);
        final aVeh = aligner.transformAccel(rawAccel);
        final wVeh = aligner.transformGyro(rawGyro);

        final speed = tcn.predict(
          vehicleAccel: aVeh,
          vehicleGyro: wVeh,
          isShockGateActive: false,
          dt: 0.01,
        );

        if (tcn.isStationary) {
          posAtLock ??= ekf.state.position;
          ekf.applyStandstill(wVeh.z, aVeh.x);
          classicDr.syncWithGnss(
            position: classicDr.state.position,
            velocity: Vec3.zero,
            yaw: classicDr.state.yaw,
          );
        } else {
          ekf.predict(
            vehicleAccel: aVeh,
            vehicleGyro: wVeh,
            dt: 0.01,
            vTcn: speed,
          );
          classicDr.step(vehicleAccel: aVeh, vehicleGyro: wVeh, dt: 0.01);
        }
      }

      expect(tcn.isStationary, isTrue);
      expect(tcn.estimatedSpeed, equals(0.0));
      if (posAtLock != null) {
        final drift = (ekf.state.position - posAtLock).norm;
        expect(drift, lessThan(0.001), reason: 'Dynamic grip tilt must not drift');
      }
    });

    test('Real vehicle throttle launch breaks out cleanly from stationary hand-held state', () {
      final aligner = CabinAligner();
      final tcn = TcnSpeedEngine();
      final ekf = Ekf3D();

      // 1. Initial 100 samples stationary in hand
      for (int i = 0; i < 100; i++) {
        final rawAccel = const Vec3(0.05, -0.05, 9.807);
        final rawGyro = const Vec3(0.05, 0.08, -0.02);

        aligner.ingest(rawAccel, rawGyro, dt: 0.01);
        final aVeh = aligner.transformAccel(rawAccel);
        final wVeh = aligner.transformGyro(rawGyro);

        tcn.predict(
          vehicleAccel: aVeh,
          vehicleGyro: wVeh,
          isShockGateActive: false,
          dt: 0.01,
        );

        if (tcn.isStationary) {
          ekf.applyStandstill(wVeh.z, aVeh.x);
        }
      }
      expect(tcn.isStationary, isTrue);

      // 2. Real vehicle throttle launch (+1.5 m/s^2 forward acceleration sustained for 0.5s)
      for (int i = 0; i < 50; i++) {
        final rawAccel = const Vec3(1.5, 0.02, 9.807);
        final rawGyro = const Vec3(0.01, 0.01, 0.01);

        aligner.ingest(rawAccel, rawGyro, dt: 0.01);
        final aVeh = aligner.transformAccel(rawAccel);
        final wVeh = aligner.transformGyro(rawGyro);

        final speed = tcn.predict(
          vehicleAccel: aVeh,
          vehicleGyro: wVeh,
          isShockGateActive: false,
          dt: 0.01,
        );

        if (!tcn.isStationary) {
          ekf.predict(
            vehicleAccel: aVeh,
            vehicleGyro: wVeh,
            dt: 0.01,
            vTcn: speed,
          );
        }
      }

      // Standstill must be broken and vehicle must be in motion
      expect(tcn.isStationary, isFalse);
      expect(tcn.estimatedSpeed, greaterThan(0.20));
      expect(ekf.state.position.norm, greaterThan(0.05));
    });
  });
}

