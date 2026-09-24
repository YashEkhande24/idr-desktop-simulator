import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:idr_navigator/core/math_utils.dart';
import 'package:idr_navigator/services/cabin_alignment.dart';
import 'package:idr_navigator/services/tcn_speed_engine.dart';
import 'package:idr_navigator/services/ekf_3d.dart';

void main() {
  group('Idle Phone Zero Drift & Standstill Suite', () {
    test('Flat idle phone on table maintains zero speed and stationary lock', () {
      final aligner = CabinAligner();
      final tcn = TcnSpeedEngine();
      final ekf = Ekf3D();

      for (int i = 0; i < 100; i++) {
        final rawAccel = Vec3(0.005, -0.008, 9.807);
        final rawGyro = Vec3(0.001, -0.002, 0.001);

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
          ekf.applyStandstill(wVeh.z, aVeh.x);
        } else {
          ekf.predict(
            vehicleAccel: aVeh,
            vehicleGyro: wVeh,
            dt: 0.01,
            vTcn: speed,
          );
        }
      }

      expect(tcn.isStationary, isTrue);
      expect(tcn.estimatedSpeed, equals(0.0));
      expect(ekf.state.position.norm, lessThan(0.001));
    });

    test('Tilted phone (15° pitch + 10° roll) levels gravity and locks zero speed without drift', () {
      final aligner = CabinAligner();
      final tcn = TcnSpeedEngine();
      final ekf = Ekf3D();

      final rollAngle = 10.0 * math.pi / 180.0;
      final pitchAngle = 15.0 * math.pi / 180.0;

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

      // Gravity [0, 0, g] transformed into phone frame
      final trueG = const Vec3(0, 0, 9.80665);
      final phoneG = rBv.transpose.transform(trueG);

      Vec3? posAtLock;
      for (int i = 0; i < 150; i++) {
        // Add small sensor noise
        final rawAccel = phoneG + Vec3(0.004, -0.006, 0.002);
        final rawGyro = Vec3(0.001, -0.001, 0.001);

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
        } else {
          ekf.predict(
            vehicleAccel: aVeh,
            vehicleGyro: wVeh,
            dt: 0.01,
            vTcn: speed,
          );
        }
      }

      // Check alignment removed gravity tilt
      expect(aligner.mountPitchDeg, closeTo(15.0, 1.0));
      expect(aligner.mountRollDeg, closeTo(10.0, 1.0));
      expect(tcn.isStationary, isTrue);
      expect(tcn.estimatedSpeed, equals(0.0));
      expect(posAtLock, isNotNull);
      // Once stationary lock engages, position must be completely frozen (0.0 mm drift)
      expect((ekf.state.position - posAtLock!).norm, lessThan(0.0001));
    });
  });
}
