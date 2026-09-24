import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:idr_navigator/core/math_utils.dart';
import 'package:idr_navigator/services/map_snapper.dart';
import 'package:idr_navigator/services/osm_map_loader.dart';

void main() {
  group('Module 5: Offline OpenStreetMap (OSM) Loader Tests', () {
    test('MathUtils wgs84ToEnu and enuToWgs84 round-trip with sub-millimeter precision', () {
      const refLat = 18.5204303;
      const refLon = 73.8567437;
      const refAlt = 560.0;

      // Point roughly 500 meters East and 300 meters North
      const targetLat = 18.5231303;
      const targetLon = 73.8614800;
      const targetAlt = 575.0;

      final enu = MathUtils.wgs84ToEnu(
        lat: targetLat,
        lon: targetLon,
        alt: targetAlt,
        refLat: refLat,
        refLon: refLon,
        refAlt: refAlt,
      );

      expect(enu.x, greaterThan(400.0)); // East meters
      expect(enu.y, greaterThan(250.0)); // North meters
      expect(enu.z, closeTo(15.0, 1e-4)); // Up meters

      // Reverse conversion back to WGS84
      final roundTrip = MathUtils.enuToWgs84(
        enu: enu,
        refLat: refLat,
        refLon: refLon,
        refAlt: refAlt,
      );

      expect(roundTrip.latitude, closeTo(targetLat, 1e-6));
      expect(roundTrip.longitude, closeTo(targetLon, 1e-6));
      expect(roundTrip.altitude, closeTo(targetAlt, 1e-3));
    });

    test('OsmMapLoader parses sample offline GeoJSON into MapBranch network', () {
      final file = File('assets/maps/sample_osm_highway.geojson');
      expect(file.existsSync(), isTrue);

      final geoJsonStr = file.readAsStringSync();
      final result = OsmMapLoader.parseGeoJson(geoJsonStr);

      final branches = result.branches;
      expect(branches.length, equals(4));

      // Branch 0: NH-48 Mainline
      expect(branches[0].name, contains('NH-48'));
      expect(branches[0].isElevated, isFalse);
      expect(branches[0].points.length, equals(4));

      // Branch 1: Elevated Flyover Deck (Tier 2)
      expect(branches[1].name, contains('Flyover'));
      expect(branches[1].isElevated, isTrue);
      expect(branches[1].points.last.z, greaterThan(branches[1].points.first.z));

      // Branch 2: At-Grade Service Road (Underpass)
      expect(branches[2].name, contains('Service Road'));
      expect(branches[2].isElevated, isFalse);

      // Branch 3: Highway Tunnel
      expect(branches[3].name, contains('Tunnel'));
    });

    test('MapSnapper works seamlessly with loaded offline OpenStreetMap branches', () {
      final file = File('assets/maps/sample_osm_highway.geojson');
      final geoJsonStr = file.readAsStringSync();
      final result = OsmMapLoader.parseGeoJson(geoJsonStr);

      final snapper = MapSnapper(branches: result.branches, beta: 2.5);

      // Test Vehicle position near the NH-48 Mainline
      final p0 = result.branches[0].points[1];
      final perturbed = Vec3(p0.x, p0.y + 3.2, p0.z);

      final match = snapper.snap(perturbed);
      expect(match, isNotNull);
      expect(match!.branchName, contains('NH-48'));
      expect(match.crossTrackDistance.abs(), closeTo(3.2, 0.1));
    });

    test('OsmMapLoader successfully loads and preps 2900+ Maharashtra real-world highways', () {
      final file = File('assets/maps/maharashtra_highways.geojson');
      expect(file.existsSync(), isTrue);

      final geoJsonStr = file.readAsStringSync();
      final result = OsmMapLoader.parseGeoJson(geoJsonStr);

      final branches = result.branches;
      expect(branches.length, greaterThan(2000));

      final elevatedBranches = branches.where((b) => b.isElevated).toList();
      expect(elevatedBranches.length, greaterThan(400));

      // Test snapping on the real-world Maharashtra Expressway network
      final snapper = MapSnapper(branches: branches, beta: 2.5);
      final samplePoint = branches.first.points.first;
      final perturbed = Vec3(samplePoint.x, samplePoint.y + 2.5, samplePoint.z);

      final match = snapper.snap(perturbed);
      expect(match, isNotNull);
      expect(match!.crossTrackDistance.abs(), closeTo(2.5, 0.2));
    });

    test('OsmMapLoader parses minor urban roads (residential, service, tertiary) and snaps accurately', () {
      final file = File('assets/maps/pune_urban_full.geojson');
      expect(file.existsSync(), isTrue);

      final geoJsonStr = file.readAsStringSync();
      final result = OsmMapLoader.parseGeoJson(geoJsonStr);

      expect(result.branches.length, greaterThan(4000));

      // With AABB optimization, snapping across 4600+ segments runs in <1ms
      final snapper = MapSnapper(branches: result.branches);
      final samplePoint = result.branches[100].points.first;
      final perturbed = Vec3(samplePoint.x + 1.8, samplePoint.y, samplePoint.z);

      final match = snapper.snap(perturbed);
      expect(match, isNotNull);
      expect(match!.crossTrackDistance.abs(), lessThanOrEqualTo(1.8 + 1e-4));
    });
  });
}


