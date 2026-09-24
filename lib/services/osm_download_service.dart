import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../core/math_utils.dart';

enum RoadLevel {
  highways('Highways Only', 'motorway|trunk|motorway_link|trunk_link', 'Expressways & National Highways (lightweight)'),
  arterials('Highways + Arterials', 'motorway|trunk|primary|secondary|motorway_link|trunk_link|primary_link|secondary_link', 'Adds State Highways & major city avenues'),
  minorRoads('Full Minor Grid', 'motorway|trunk|primary|secondary|tertiary|residential|service|unclassified|living_street|motorway_link|trunk_link|primary_link|secondary_link|tertiary_link', 'Complete street grid including residential & service lanes');

  final String label;
  final String osmFilter;
  final String description;

  const RoadLevel(this.label, this.osmFilter, this.description);
}

class MapPresetInfo {
  final String id;
  final String name;
  final String? assetPath;
  final String description;
  final int approxSegments;
  final bool hasElevated;
  final bool hasMinorRoads;

  const MapPresetInfo({
    required this.id,
    required this.name,
    this.assetPath,
    required this.description,
    required this.approxSegments,
    this.hasElevated = false,
    this.hasMinorRoads = false,
  });
}

class DownloadedMapFile {
  final String name;
  final String filePath;
  final int sizeBytes;
  final DateTime modifiedTime;

  DownloadedMapFile({
    required this.name,
    required this.filePath,
    required this.sizeBytes,
    required this.modifiedTime,
  });

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Service for managing bundled offline OSM maps and downloading new city/minor road grids in-app.
class OsmDownloadService {
  static const List<String> overpassMirrors = [
    'https://overpass-api.de/api/interpreter',
    'https://lz4.overpass-api.de/api/interpreter',
    'https://z.overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
  ];

  static const List<MapPresetInfo> bundledPresets = [
    MapPresetInfo(
      id: 'maharashtra_highways',
      name: 'Maharashtra Expressways & Viaducts',
      assetPath: 'assets/maps/maharashtra_highways.geojson',
      description: '2,983 segments: Mumbai-Pune Expwy, Atal Setu MTHL, NH-48 corridor, Panvel & Pune',
      approxSegments: 2983,
      hasElevated: true,
      hasMinorRoads: false,
    ),
    MapPresetInfo(
      id: 'pune_urban_full',
      name: 'Pune Urban Grid (with Minor Roads)',
      assetPath: 'assets/maps/pune_urban_full.geojson',
      description: '4,695 segments: Shivajinagar, FC Road, Kothrud, 2,100+ residential lanes & alleys',
      approxSegments: 4695,
      hasElevated: false,
      hasMinorRoads: true,
    ),
    MapPresetInfo(
      id: 'mumbai_pune_expressway',
      name: 'Mumbai-Pune Expressway (Bhor Ghat)',
      assetPath: 'assets/maps/mumbai_pune_expressway.geojson',
      description: 'Khandala tunnels, Madap & Bhatan underpasses with multi-tier flyover decks',
      approxSegments: 450,
      hasElevated: true,
      hasMinorRoads: false,
    ),
    MapPresetInfo(
      id: 'benchmark_course',
      name: 'Synthetic Benchmark Course',
      assetPath: null,
      description: 'Dual carriageway with 18m elevated flyover deck and parallel decoy service underpass',
      approxSegments: 5,
      hasElevated: true,
      hasMinorRoads: false,
    ),
  ];

  static Directory? debugOverrideDir;

  /// Get local maps storage directory
  static Future<Directory> getMapsDirectory() async {
    if (debugOverrideDir != null) {
      if (!await debugOverrideDir!.exists()) {
        await debugOverrideDir!.create(recursive: true);
      }
      return debugOverrideDir!;
    }
    final docsDir = await getApplicationDocumentsDirectory();
    final mapsDir = Directory('${docsDir.path}${Platform.pathSeparator}maps');
    if (!await mapsDir.exists()) {
      await mapsDir.create(recursive: true);
    }
    return mapsDir;
  }

  /// List all maps downloaded by the user locally
  static Future<List<DownloadedMapFile>> listDownloadedMaps() async {
    try {
      final dir = await getMapsDirectory();
      final entities = await dir.list().toList();
      final list = <DownloadedMapFile>[];

      for (final e in entities) {
        if (e is File && e.path.endsWith('.geojson')) {
          final stat = await e.stat();
          final filename = e.path.split(Platform.pathSeparator).last.replaceAll('.geojson', '');
          list.add(DownloadedMapFile(
            name: filename,
            filePath: e.path,
            sizeBytes: stat.size,
            modifiedTime: stat.modified,
          ));
        }
      }

      list.sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));
      return list;
    } catch (e) {
      debugPrint('Error listing downloaded maps: $e');
      return [];
    }
  }

  /// Delete a downloaded map file
  static Future<bool> deleteDownloadedMap(String filePath) async {
    try {
      final f = File(filePath);
      if (await f.exists()) {
        await f.delete();
        return true;
      }
    } catch (e) {
      debugPrint('Error deleting map: $e');
    }
    return false;
  }

  /// Download road network for a specified radius (in kilometers) around a center coordinate.
  static Future<File> downloadRadiusArea({
    required String mapName,
    required double centerLat,
    required double centerLon,
    required double radiusKm,
    required RoadLevel level,
    void Function(String status, double progress)? onProgress,
  }) async {
    const double rEarthKm = 6378.137;
    final dLatDeg = (radiusKm / rEarthKm) * (180.0 / math.pi);
    final cosLat = math.cos(MathUtils.degToRad(centerLat)).abs();
    final dLonDeg = (radiusKm / (rEarthKm * math.max(0.1, cosLat))) * (180.0 / math.pi);

    final south = centerLat - dLatDeg;
    final north = centerLat + dLatDeg;
    final west = centerLon - dLonDeg;
    final east = centerLon + dLonDeg;

    return await downloadArea(
      mapName: mapName,
      south: south,
      west: west,
      north: north,
      east: east,
      level: level,
      onProgress: onProgress,
    );
  }

  /// Automatically prune dynamic tile cache files.
  /// Keeps [keepFilePath] and at most [maxFilesToKeep] most recent dynamic tiles, deleting the rest.
  static Future<int> pruneDynamicCache({
    required String keepFilePath,
    int maxFilesToKeep = 2,
  }) async {
    int deletedCount = 0;
    try {
      final dir = await getMapsDirectory();
      final entities = await dir.list().toList();
      final dynamicFiles = <File>[];

      for (final e in entities) {
        if (e is File && e.path.endsWith('.geojson')) {
          final filename = e.path.split(Platform.pathSeparator).last;
          if (filename.startsWith('dynamic_tile_')) {
            dynamicFiles.add(e);
          }
        }
      }

      // Exclude keepFilePath from pruning candidates
      final candidates = dynamicFiles.where((f) => f.path != keepFilePath).toList();

      // Sort by modified time descending (newest first), with filename as fallback
      final fileStats = <File, DateTime>{};
      for (final f in candidates) {
        fileStats[f] = (await f.stat()).modified;
      }
      candidates.sort((a, b) {
        final cmp = fileStats[b]!.compareTo(fileStats[a]!);
        if (cmp != 0) return cmp;
        return b.path.compareTo(a.path);
      });

      // If maxFilesToKeep is 2, and keepFilePath is 1, keep (maxFilesToKeep - 1) among candidates
      final allowedRemaining = math.max(0, maxFilesToKeep - 1);
      for (int i = allowedRemaining; i < candidates.length; i++) {
        final f = candidates[i];
        try {
          await f.delete();
          deletedCount++;
          debugPrint('Pruned old dynamic map tile: ${f.path}');
        } catch (e) {
          debugPrint('Failed to delete map file: $e');
        }
      }
    } catch (e) {
      debugPrint('Error pruning dynamic cache: $e');
    }
    return deletedCount;
  }

  /// Delete all dynamic cache tiles from disk
  static Future<int> purgeAllDynamicMaps() async {
    int deletedCount = 0;
    try {
      final dir = await getMapsDirectory();
      final entities = await dir.list().toList();
      for (final e in entities) {
        if (e is File && e.path.endsWith('.geojson')) {
          final filename = e.path.split(Platform.pathSeparator).last;
          if (filename.startsWith('dynamic_tile_')) {
            try {
              await e.delete();
              deletedCount++;
            } catch (e) {
              debugPrint('Error deleting $filename: $e');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error purging all dynamic maps: $e');
    }
    return deletedCount;
  }

  /// Download road network from OpenStreetMap Overpass API directly within the app
  static Future<File> downloadArea({
    required String mapName,
    required double south,
    required double west,
    required double north,
    required double east,
    required RoadLevel level,
    void Function(String status, double progress)? onProgress,
  }) async {
    onProgress?.call('Connecting to OpenStreetMap...', 0.1);

    final safeName = mapName.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_').toLowerCase();
    final dir = await getMapsDirectory();
    final targetFile = File('${dir.path}${Platform.pathSeparator}$safeName.geojson');

    final overpassQuery = '''
    [out:json][timeout:90];
    (
      way["highway"~"${level.osmFilter}"]($south,$west,$north,$east);
    );
    out body geom;
    ''';

    onProgress?.call('Querying road vectors from server...', 0.25);

    Map<String, dynamic>? overpassData;
    String? lastError;

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 20);

    for (int i = 0; i < overpassMirrors.length; i++) {
      final mirror = overpassMirrors[i];
      try {
        onProgress?.call('Querying server mirror ${i + 1}/${overpassMirrors.length}...', 0.35 + (i * 0.1));
        final uri = Uri.parse('$mirror?data=${Uri.encodeComponent(overpassQuery)}');
        final request = await client.getUrl(uri);
        request.headers.set('User-Agent', 'IDR-DeadReckoning-SIH2026/1.0 (contact@idr-hackathon.org)');
        request.headers.set('Accept', 'application/json');

        final response = await request.close().timeout(const Duration(seconds: 90));
        if (response.statusCode == 200) {
          final responseBody = await response.transform(utf8.decoder).join();
          overpassData = jsonDecode(responseBody) as Map<String, dynamic>?;
          if (overpassData != null && overpassData.containsKey('elements')) {
            break;
          }
        } else {
          lastError = 'Server returned HTTP ${response.statusCode}';
        }
      } catch (e) {
        lastError = e.toString();
        debugPrint('Mirror $mirror failed: $e');
      }
    }

    client.close();

    if (overpassData == null) {
      throw Exception('Failed to download OSM data. All servers timed out or returned an error. ($lastError)');
    }

    onProgress?.call('Processing road geometry & elevations...', 0.75);

    final elements = overpassData['elements'] as List<dynamic>? ?? [];
    final features = <Map<String, dynamic>>[];

    for (final el in elements) {
      if (el is! Map<String, dynamic>) continue;
      if (el['type'] != 'way') continue;

      final geomNodes = el['geometry'] as List<dynamic>? ?? [];
      if (geomNodes.length < 2) continue;

      final coords = <List<double>>[];
      for (final pt in geomNodes) {
        if (pt is Map<String, dynamic>) {
          final lon = (pt['lon'] as num).toDouble();
          final lat = (pt['lat'] as num).toDouble();
          coords.add([lon, lat, 0.0]);
        }
      }

      final tags = (el['tags'] as Map<String, dynamic>?) ?? {};

      final feature = <String, dynamic>{
        'type': 'Feature',
        'id': el['id'],
        'properties': {
          'name': tags['name'] ?? tags['ref'] ?? tags['highway'] ?? 'Road',
          'ref': tags['ref'] ?? '',
          'highway': tags['highway'] ?? 'road',
          'bridge': tags['bridge'] ?? 'no',
          'tunnel': tags['tunnel'] ?? 'no',
          'layer': tags['layer'] ?? '0',
          'lanes': tags['lanes'] ?? '2',
          'maxspeed': tags['maxspeed'] ?? '50',
          'oneway': tags['oneway'] ?? 'no',
        },
        'geometry': {
          'type': 'LineString',
          'coordinates': coords,
        },
      };
      features.add(feature);
    }

    final geoJson = {
      'type': 'FeatureCollection',
      'generator': 'IDR OpenStreetMap Mobile Extractor',
      'features': features,
    };

    onProgress?.call('Saving offline road database (${features.length} roads)...', 0.90);

    await targetFile.writeAsString(jsonEncode(geoJson));

    onProgress?.call('Complete! Ready for offline navigation.', 1.0);

    return targetFile;
  }
}
