import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import '../core/math_utils.dart';
import 'map_snapper.dart';

/// Module 5: Offline OpenStreetMap (OSM) Road Network Ingestion Engine.
///
/// Ingests standardized GeoJSON / Overpass extracts containing road polylines
/// (LineString/MultiLineString) and projects geodetic WGS84 coordinates into
/// the local metric Cartesian ENU (East-North-Up) frame for real-time 3D Map Snapping.
class OsmMapLoader {
  /// Parses a GeoJSON string into a list of [MapBranch] objects.
  ///
  /// [geoJsonString]: GeoJSON FeatureCollection containing LineString highway features.
  /// [anchorLat]: Reference latitude in degrees. If null, the first node is used.
  /// [anchorLon]: Reference longitude in degrees. If null, the first node is used.
  /// [anchorAlt]: Reference altitude in meters. If null, defaults to 0.0m.
  static ({
    List<MapBranch> branches,
    double refLat,
    double refLon,
    double refAlt,
  }) parseGeoJson(
    String geoJsonString, {
    double? anchorLat,
    double? anchorLon,
    double? anchorAlt,
  }) {
    final dynamic decoded = jsonDecode(geoJsonString);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid GeoJSON: root must be a JSON object');
    }

    final features = <Map<String, dynamic>>[];
    final type = decoded['type'] as String?;

    if (type == 'FeatureCollection') {
      final list = decoded['features'] as List<dynamic>? ?? [];
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          features.add(item);
        }
      }
    } else if (type == 'Feature') {
      features.add(decoded);
    } else {
      throw FormatException('Unsupported GeoJSON type: $type');
    }

    // Determine reference anchor if not explicitly provided
    double? refLat = anchorLat;
    double? refLon = anchorLon;
    double? refAlt = anchorAlt;

    if (refLat == null || refLon == null) {
      for (final feature in features) {
        final geom = feature['geometry'] as Map<String, dynamic>?;
        if (geom == null) continue;
        final geomType = geom['type'] as String?;
        final coords = geom['coordinates'] as List<dynamic>?;
        if (coords == null || coords.isEmpty) continue;

        if (geomType == 'LineString' && coords.first is List) {
          final pt = coords.first as List;
          if (pt.length >= 2) {
            refLon = (pt[0] as num).toDouble();
            refLat = (pt[1] as num).toDouble();
            refAlt = pt.length >= 3 ? (pt[2] as num).toDouble() : 0.0;
            break;
          }
        }
      }
    }

    refLat ??= 0.0;
    refLon ??= 0.0;
    refAlt ??= 0.0;

    final branches = <MapBranch>[];

    for (final feature in features) {
      final geom = feature['geometry'] as Map<String, dynamic>?;
      if (geom == null) continue;

      final geomType = geom['type'] as String?;
      final props = (feature['properties'] as Map<String, dynamic>?) ?? {};

      // Road Metadata Extraction
      final name = props['name'] as String? ??
          props['ref'] as String? ??
          props['highway'] as String? ??
          'Unnamed Road';
      final bridge = props['bridge'] as String?;
      final tunnel = props['tunnel'] as String?;
      final layer = props['layer'];
      final int layerNum = (layer is num)
          ? layer.toInt()
          : (layer is String ? int.tryParse(layer) ?? 0 : 0);

      // Elevated deck identification (Flyovers, Viaducts, Elevated Expressways)
      final isElevated = (bridge == 'yes') || (layerNum > 0);
      final isTunnel = (tunnel == 'yes') || (layerNum < 0);

      // Speed limit extraction
      final maxspeedStr = props['maxspeed'] as String?;
      double speedLimitMps = 16.67; // ~60 km/h default
      if (maxspeedStr != null) {
        final val = double.tryParse(maxspeedStr.replaceAll(RegExp(r'[^0-9.]'), ''));
        if (val != null) {
          speedLimitMps = val / 3.6;
        }
      }

      final oneway = (props['oneway'] == 'yes') || (props['oneway'] == '1');

      final lanesStr = props['lanes'] as String?;
      int lanes = 2;
      if (lanesStr != null) {
        final parsed = int.tryParse(lanesStr.replaceAll(RegExp(r'[^0-9]'), ''));
        if (parsed != null && parsed > 0 && parsed <= 12) {
          lanes = parsed;
        }
      }

      // Coordinate Extraction & Local Projection
      if (geomType == 'LineString') {
        final coordsList = geom['coordinates'] as List<dynamic>? ?? [];
        final points = _convertCoordsToEnu(
          coordsList,
          refLat: refLat,
          refLon: refLon,
          refAlt: refAlt,
        );

        if (points.length >= 2) {
          branches.add(MapBranch(
            name: name,
            points: points,
            isElevated: isElevated,
            isTunnel: isTunnel,
            speedLimitMps: speedLimitMps,
            oneWay: oneway,
            lanes: lanes,
          ));
        }
      } else if (geomType == 'MultiLineString') {
        final multiCoords = geom['coordinates'] as List<dynamic>? ?? [];
        for (int i = 0; i < multiCoords.length; i++) {
          final segment = multiCoords[i] as List<dynamic>? ?? [];
          final points = _convertCoordsToEnu(
            segment,
            refLat: refLat,
            refLon: refLon,
            refAlt: refAlt,
          );

          if (points.length >= 2) {
            branches.add(MapBranch(
              name: '$name (Part ${i + 1})',
              points: points,
              isElevated: isElevated,
              isTunnel: isTunnel,
              speedLimitMps: speedLimitMps,
              oneWay: oneway,
              lanes: lanes,
            ));
          }
        }
      }
    }

    return (
      branches: branches,
      refLat: refLat,
      refLon: refLon,
      refAlt: refAlt,
    );
  }

  /// Load an offline GeoJSON map asset from Flutter bundle.
  static Future<({
    List<MapBranch> branches,
    double refLat,
    double refLon,
    double refAlt,
  })> loadFromAsset(
    String assetPath, {
    double? anchorLat,
    double? anchorLon,
    double? anchorAlt,
  }) async {
    final rawJson = await rootBundle.loadString(assetPath);
    return parseGeoJson(
      rawJson,
      anchorLat: anchorLat,
      anchorLon: anchorLon,
      anchorAlt: anchorAlt,
    );
  }

  /// Load an offline GeoJSON map from a file on device filesystem.
  static Future<({
    List<MapBranch> branches,
    double refLat,
    double refLon,
    double refAlt,
  })> loadFromFile(
    File file, {
    double? anchorLat,
    double? anchorLon,
    double? anchorAlt,
  }) async {
    final rawJson = await file.readAsString();
    return parseGeoJson(
      rawJson,
      anchorLat: anchorLat,
      anchorLon: anchorLon,
      anchorAlt: anchorAlt,
    );
  }

  static List<Vec3> _convertCoordsToEnu(
    List<dynamic> coordsList, {
    required double refLat,
    required double refLon,
    required double refAlt,
  }) {
    final points = <Vec3>[];

    for (final coord in coordsList) {
      if (coord is List && coord.length >= 2) {
        final lon = (coord[0] as num).toDouble();
        final lat = (coord[1] as num).toDouble();
        final alt = coord.length >= 3 ? (coord[2] as num).toDouble() : refAlt;

        final enu = MathUtils.wgs84ToEnu(
          lat: lat,
          lon: lon,
          alt: alt,
          refLat: refLat,
          refLon: refLon,
          refAlt: refAlt,
        );
        points.add(enu);
      }
    }

    return points;
  }
}
