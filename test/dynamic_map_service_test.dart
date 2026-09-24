import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:idr_navigator/core/math_utils.dart';
import 'package:idr_navigator/services/dynamic_map_service.dart';
import 'package:idr_navigator/services/osm_download_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Dynamic Map Engine - Geodesic & Buffer Calculations', () {
    test('Haversine distance accurately measures kilometers between coordinates', () {
      // Pune Swargate (18.500, 73.850) to ~25km North (18.725, 73.850)
      final distMeters = MathUtils.haversineDistanceMeters(18.500, 73.850, 18.725, 73.850);
      final distKm = distMeters / 1000.0;

      // 0.225 degrees latitude * ~111 km/deg ≈ 25.0 km
      expect(distKm, greaterThan(24.5));
      expect(distKm, lessThan(25.5));
    });

    test('DynamicMapService initial defaults are 50km radius and 25km buffer', () {
      final service = DynamicMapService();

      expect(service.radiusKm, equals(50.0));
      expect(service.bufferKm, equals(25.0));
      expect(service.isAutoDynamicEnabled, isTrue);
      expect(service.distanceMovedSinceCenterKm, equals(0.0));
      expect(service.remainingBufferDistanceKm, equals(25.0));
      expect(service.activeCenterLat, isNull);
      expect(service.activeCenterLon, isNull);
    });

    test('Radius to Bounding Box calculation covers 50 km in all 4 cardinal directions', () {
      const centerLat = 18.5204;
      const centerLon = 73.8567;
      const radiusKm = 50.0;

      final latDelta = radiusKm / 111.0;
      final lonDelta = radiusKm / (111.0 * math.cos(MathUtils.degToRad(centerLat)));

      final south = centerLat - latDelta;
      final north = centerLat + latDelta;
      final west = centerLon - lonDelta;
      final east = centerLon + lonDelta;

      // North-South span should be ~100 km (0.90 degrees)
      expect(north - south, closeTo(0.90, 0.05));
      // East-West span should be ~100 km (~0.95 degrees at 18.5 deg lat)
      expect(east - west, closeTo(0.95, 0.05));

      // Distance from center to north edge should be ~50 km
      final distToNorthKm = MathUtils.haversineDistanceMeters(centerLat, centerLon, north, centerLon) / 1000.0;
      expect(distToNorthKm, closeTo(50.0, 1.0));

      // Distance from center to east edge should be ~50 km
      final distToEastKm = MathUtils.haversineDistanceMeters(centerLat, centerLon, centerLat, east) / 1000.0;
      expect(distToEastKm, closeTo(50.0, 1.0));
    });

    test('Buffer remaining distance decreases as vehicle moves', () {
      final service = DynamicMapService();

      // Configure custom radius / buffer
      service.setRadiusKm(50.0);
      service.setBufferKm(25.0);

      expect(service.remainingBufferDistanceKm, equals(25.0));

      // Toggle auto-dynamic
      service.setAutoDynamicEnabled(false);
      expect(service.isAutoDynamicEnabled, isFalse);
      service.setAutoDynamicEnabled(true);
      expect(service.isAutoDynamicEnabled, isTrue);

      // Reset
      service.reset();
      expect(service.distanceMovedSinceCenterKm, equals(0.0));
      expect(service.activeCenterLat, isNull);
    });
  });

  group('Dynamic Map Engine - Pruning & Deletion Lifecycle', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('idr_dynamic_test_');
      OsmDownloadService.debugOverrideDir = tempDir;
    });

    tearDown(() async {
      OsmDownloadService.debugOverrideDir = null;
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('pruneDynamicCache preserves newest tiles and deletes older tiles', () async {
      // Create 5 dummy dynamic map files with staggered timestamps
      final file1 = File('${tempDir.path}${Platform.pathSeparator}dynamic_tile_18_50_73_80_1000.geojson');
      final file2 = File('${tempDir.path}${Platform.pathSeparator}dynamic_tile_18_50_73_80_2000.geojson');
      final file3 = File('${tempDir.path}${Platform.pathSeparator}dynamic_tile_18_50_73_80_3000.geojson');
      final file4 = File('${tempDir.path}${Platform.pathSeparator}dynamic_tile_18_50_73_80_4000.geojson');
      final file5 = File('${tempDir.path}${Platform.pathSeparator}dynamic_tile_18_50_73_80_5000.geojson');

      await file1.writeAsString('{}');
      await Future.delayed(const Duration(milliseconds: 20));
      await file2.writeAsString('{}');
      await Future.delayed(const Duration(milliseconds: 20));
      await file3.writeAsString('{}');
      await Future.delayed(const Duration(milliseconds: 20));
      await file4.writeAsString('{}');
      await Future.delayed(const Duration(milliseconds: 20));
      await file5.writeAsString('{}');

      // Also create a non-dynamic user map that should never be pruned
      final userCustomMap = File('${tempDir.path}${Platform.pathSeparator}mumbai_bkc_custom.geojson');
      await userCustomMap.writeAsString('{}');

      // Prune, keeping at most 2 files, and explicitly protecting file5
      final deleted = await OsmDownloadService.pruneDynamicCache(
        keepFilePath: file5.path,
        maxFilesToKeep: 2,
      );

      // Should have pruned 3 older dynamic tiles
      expect(deleted, equals(3));

      // file5 (newest and protected) must still exist
      expect(await file5.exists(), isTrue);
      // Non-dynamic user map must still exist
      expect(await userCustomMap.exists(), isTrue);

      // Oldest dynamic files should have been deleted
      expect(await file1.exists(), isFalse);
      expect(await file2.exists(), isFalse);
    });

    test('purgeAllDynamicMaps removes all dynamic tiles but leaves custom user maps intact', () async {
      final dyn1 = File('${tempDir.path}${Platform.pathSeparator}dynamic_tile_pune.geojson');
      final dyn2 = File('${tempDir.path}${Platform.pathSeparator}dynamic_tile_mumbai.geojson');
      final custom1 = File('${tempDir.path}${Platform.pathSeparator}custom_saved_map.geojson');

      await dyn1.writeAsString('{}');
      await dyn2.writeAsString('{}');
      await custom1.writeAsString('{}');

      final purged = await OsmDownloadService.purgeAllDynamicMaps();
      expect(purged, equals(2));

      expect(await dyn1.exists(), isFalse);
      expect(await dyn2.exists(), isFalse);
      expect(await custom1.exists(), isTrue);
    });
  });
}
