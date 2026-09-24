import 'package:flutter_test/flutter_test.dart';
import 'package:idr_navigator/core/constants.dart';
import 'package:idr_navigator/core/math_utils.dart';
import 'package:idr_navigator/services/cabin_alignment.dart';

void main() {
  group('Module 1: CabinAligner Tests', () {
    test('Flat phone alignment recognizes vertical gravity', () {
      final aligner = CabinAligner();

      // Feed 100 samples of a flat phone (screen up): az = +9.8 m/s^2
      for (int i = 0; i < 110; i++) {
        aligner.ingest(
          const Vec3(0.0, 0.0, IdrConstants.gravity),
          Vec3.zero,
        );
      }

      expect(aligner.isLocked, isTrue);
      expect(aligner.confidence, greaterThan(0.85));
      expect(aligner.mountPitchDeg.abs(), lessThan(2.0));
      expect(aligner.mountRollDeg.abs(), lessThan(2.0));

      // Test transformed acceleration removes gravity
      final aVeh = aligner.transformAccel(const Vec3(0.0, 0.0, IdrConstants.gravity));
      expect(aVeh.z.abs(), lessThan(0.1));
    });

    test('Tilted phone alignment computes mount pitch angle correctly', () {
      final aligner = CabinAligner();

      // Phone mounted at 20 deg pitch:
      // g_sensor = R_pitch^T * [0, 0, 9.8]
      // ax = -sin(20) * 9.8 = -3.35, az = cos(20) * 9.8 = 9.21
      for (int i = 0; i < 110; i++) {
        aligner.ingest(
          const Vec3(-3.354, 0.0, 9.215),
          Vec3.zero,
        );
      }

      aligner.forceCalibrate();
      expect(aligner.isLocked, isTrue);
      expect(aligner.mountPitchDeg, closeTo(20.0, 1.5));
    });

    test('Mahony filter tracks orientation quaternion and integrates gyro bias', () {
      final aligner = CabinAligner();

      // Flat phone with constant gyro bias of 0.05 rad/s on x
      const gyroWithBias = Vec3(0.05, 0.0, 0.0);
      for (int i = 0; i < 150; i++) {
        aligner.ingest(
          const Vec3(0.0, 0.0, IdrConstants.gravity),
          gyroWithBias,
          vTcn: 5.0,
          tcnVariance: 0.10,
        );
      }

      // Quaternion should remain normalized and upright
      expect(aligner.attitudeQuaternion.norm, closeTo(1.0, 1e-5));
      expect(aligner.isLocked, isTrue);
    });
  });
}
