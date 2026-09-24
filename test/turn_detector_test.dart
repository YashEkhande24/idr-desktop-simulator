import 'package:flutter_test/flutter_test.dart';
import 'package:idr_navigator/core/math_utils.dart';
import 'package:idr_navigator/services/map_snapper.dart';
import 'package:idr_navigator/services/turn_detector.dart';

void main() {
  group('Module 5 Extension: TurnDetector Tests', () {
    test('Straight driving does not trigger turn state', () {
      final detector = TurnDetector();

      for (int i = 0; i < 20; i++) {
        final state = detector.processYawRate(0.02, 0.02);
        expect(state, TurnState.straight);
      }
      expect(detector.isTurning, isFalse);
    });

    test('Sustained left turn detects turningLeft state', () {
      final detector = TurnDetector();

      for (int i = 0; i < 10; i++) {
        detector.processYawRate(0.35, 0.02); // 0.35 rad/s > 0.22 threshold
      }
      expect(detector.state, TurnState.turningLeft);
      expect(detector.isTurning, isTrue);
      expect(detector.accumulatedTurnAngleDeg, greaterThan(0.0));
    });

    test('Sustained right turn detects turningRight state', () {
      final detector = TurnDetector();

      for (int i = 0; i < 10; i++) {
        detector.processYawRate(-0.35, 0.02); // Negative = Right turn
      }
      expect(detector.state, TurnState.turningRight);
      expect(detector.isTurning, isTrue);
    });

    test('Branch disambiguation picks road aligning with vehicle turn heading', () {
      final detector = TurnDetector();

      // Vehicle is at origin heading East (0 rad)
      const vehiclePos = Vec3(0, 0, 0);
      const vehicleHeadingEast = 0.0;

      final straightBranch = MapBranch(
        name: 'NH-48 Straight East',
        points: const [Vec3(0, 0, 0), Vec3(100, 0, 0)], // East
      );

      final northForkBranch = MapBranch(
        name: 'Service Road North',
        points: const [Vec3(0, 0, 0), Vec3(0, 100, 0)], // North (pi/2)
      );

      final chosen = detector.selectBestBranch(
        candidateBranches: [straightBranch, northForkBranch],
        vehiclePos: vehiclePos,
        vehicleHeadingRad: vehicleHeadingEast,
      );

      expect(chosen?.name, equals('NH-48 Straight East'));
    });

    test('TCN speed computes kinematic curvature and centripetal acceleration', () {
      final detector = TurnDetector();

      // Vehicle traveling at 20 m/s (~72 km/h) turning at 0.1 rad/s
      detector.processYawRate(0.10, 0.02, vTcn: 20.0);

      // Curvature kappa = 0.10 / 20 = 0.005 (radius = 200m)
      expect(detector.roadCurvature, closeTo(0.005, 1e-4));
      // Centripetal acceleration a_cf = 20 * 0.10 = 2.0 m/s^2
      expect(detector.centripetalAccel, closeTo(2.0, 1e-4));
    });
  });
}
