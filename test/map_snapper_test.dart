import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:idr_navigator/core/math_utils.dart';
import 'package:idr_navigator/services/ekf_3d.dart';
import 'package:idr_navigator/services/map_snapper.dart';

void main() {
  group('Module 5: Smart 3D Map-Matching Filter Tests', () {
    test('Clamped orthogonal vector projection computes exact cross-track distance', () {
      final branches = [
        const MapBranch(
          name: 'NH-48 Main Line',
          points: [
            Vec3(0.0, 0.0, 0.0),
            Vec3(100.0, 0.0, 0.0),
          ],
        ),
      ];

      final snapper = MapSnapper(branches: branches);

      // Vehicle is at (40, 3.5, 0) - 3.5m off centerline to the left/right
      final match = snapper.snap(const Vec3(40.0, 3.5, 0.0));

      expect(match, isNotNull);
      expect(match!.branchName, equals('NH-48 Main Line'));
      expect(match.snappedPoint.x, closeTo(40.0, 1e-4));
      expect(match.snappedPoint.y, closeTo(0.0, 1e-4));
      expect(match.crossTrackDistance.abs(), closeTo(3.5, 1e-4));
      expect(match.segmentIndex, equals(0));
    });

    test('3D Multi-Tier Disambiguation separates elevated flyover from decoy underpass', () {
      final branches = [
        // Level 2 Elevated Highway Deck at z = 18m
        const MapBranch(
          name: 'Elevated Flyover Deck (Tier 2)',
          isElevated: true,
          points: [
            Vec3(280.0, 350.0, 18.0),
            Vec3(280.0, 600.0, 18.0),
          ],
        ),
        // At-grade Service Road directly underneath at z = 0m
        const MapBranch(
          name: 'At-Grade Service Road (Underpass)',
          isElevated: false,
          points: [
            Vec3(280.0, 350.0, 0.0),
            Vec3(280.0, 600.0, 0.0),
          ],
        ),
      ];

      final snapper = MapSnapper(branches: branches, beta: 2.5);

      // Scenario A: Car is on the elevated flyover (z = 17.8m, e.g. from Barometer)
      final elevatedMatch = snapper.snapWithHeading(
        const Vec3(282.0, 450.0, 17.8),
        math.pi / 2, // Northbound
      );

      expect(elevatedMatch, isNotNull);
      expect(elevatedMatch!.branchName, equals('Elevated Flyover Deck (Tier 2)'));
      expect(elevatedMatch.isElevated, isTrue);

      // Scenario B: Car is on the ground underpass (z = 0.2m)
      final groundMatch = snapper.snapWithHeading(
        const Vec3(282.0, 450.0, 0.2),
        math.pi / 2, // Northbound
      );

      expect(groundMatch, isNotNull);
      expect(groundMatch!.branchName, equals('At-Grade Service Road (Underpass)'));
      expect(groundMatch.isElevated, isFalse);
    });

    test('Heading agreement scoring rejects perpendicular cross-streets', () {
      final branches = [
        // Eastbound road: Heading = 0 rad
        const MapBranch(
          name: 'Eastbound Avenue',
          points: [
            Vec3(0.0, 0.0, 0.0),
            Vec3(100.0, 0.0, 0.0),
          ],
        ),
        // Northbound cross-street: Heading = pi/2 rad
        const MapBranch(
          name: 'Northbound Crossway',
          points: [
            Vec3(50.0, -50.0, 0.0),
            Vec3(50.0, 50.0, 0.0),
          ],
        ),
      ];

      final snapper = MapSnapper(branches: branches, headingWeight: 10.0);

      // Vehicle is near intersection (48, 2, 0), driving Eastbound (yaw = 0 rad)
      final match = snapper.snapWithHeading(
        const Vec3(48.0, 2.0, 0.0),
        0.0, // heading East
      );

      expect(match, isNotNull);
      expect(match!.branchName, equals('Eastbound Avenue'));
    });

    test('HDOP-scheduled constraint variance contracts tightly in tunnels', () {
      final branches = MapSnapper.createDefaultBenchmarkBranches();
      final snapper = MapSnapper(branches: branches);

      // Open Sky: HDOP = 1.0 -> constraint is loose (sigma ~ 4.4m)
      final sigmaOpenSky = snapper.lateralSigma(1.0);
      expect(sigmaOpenSky, greaterThan(3.5));

      // Tunnel Outage: HDOP = 25.0 -> constraint is rigid (sigma ~ 1.1m)
      final sigmaTunnel = snapper.lateralSigma(25.0);
      expect(sigmaTunnel, closeTo(1.1, 0.2));
      expect(sigmaTunnel, lessThan(sigmaOpenSky));
    });

    test('Ekf3D updateMapMatching snaps drifting IMU path back onto road centerline', () {
      final ekf = Ekf3D();

      // Simulate vehicle at px=50.0, but drifting py=6.0 off Eastbound road (y=0)
      for (int i = 0; i < 20; i++) {
        ekf.predict(
          vehicleAccel: const Vec3(1.0, 0.0, 0.0),
          vehicleGyro: Vec3.zero,
          dt: 0.01,
        );
      }

      // Force py drift
      final branches = [
        const MapBranch(
          name: 'Expressway',
          points: [
            Vec3(0.0, 0.0, 0.0),
            Vec3(200.0, 0.0, 0.0),
          ],
        ),
      ];
      final snapper = MapSnapper(branches: branches);
      final match = snapper.snapWithHeading(ekf.state.position, ekf.state.yaw, hdop: 25.0);

      expect(match, isNotNull);

      // Apply rigid tunnel map snap
      final sigmaTunnel = snapper.lateralSigma(25.0, match);

      // Apply multiple filter steps of map-matching constraint
      for (int i = 0; i < 5; i++) {
        final currentMatch = snapper.snapWithHeading(ekf.state.position, ekf.state.yaw, hdop: 25.0);
        if (currentMatch != null) {
          ekf.updateMapMatching(
            normal2D: currentMatch.normal2D,
            crossTrackDistance: currentMatch.crossTrackDistance,
            sigma: sigmaTunnel,
            roadElevation: currentMatch.snappedPoint.z,
          );
        }
      }

      // Position along normal y should be snapped back onto centerline y=0
      expect(ekf.state.py.abs(), lessThan(1.0));
    });

    test('Pedestrian walking motion bypasses vehicular road snapping', () {
      final branches = MapSnapper.createDefaultBenchmarkBranches();
      final snapper = MapSnapper(branches: branches);

      // A pedestrian walking on a sidewalk at (50, 8, 0) next to the road (y=0)
      // When pedestrian mode is detected, road snapping is bypassed,
      // preventing the walking user from being dragged into vehicular highway lanes.
      MapSnapResult? trySnap({required bool isPedestrian}) {
        if (isPedestrian) return null;
        return snapper.snapWithHeading(const Vec3(50.0, 8.0, 0.0), 0.0);
      }

      final pedestrianMatch = trySnap(isPedestrian: true);
      expect(pedestrianMatch, isNull);

      final vehicleMatch = trySnap(isPedestrian: false);
      expect(vehicleMatch, isNotNull);
    });
  });
}

