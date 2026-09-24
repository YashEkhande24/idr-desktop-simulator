import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../core/math_utils.dart';
import '../models/navigation_models.dart';
import 'map_snapper.dart';

/// Autonomous Routing & Pathfinding Engine.
///
/// Implements dual-strategy routing:
/// 1. 100% Offline A* Graph Routing: Operates across active OpenStreetMap vector road branches.
/// 2. Online OSRM Highway Fallback: Queries OpenStreetMap OSRM routing server when internet is available.
class RoutingService {
  /// Curated testing and demonstration POIs
  static final List<NavDestination> standardPOIs = [
    const NavDestination(
      name: 'Pune International Airport (PNQ)',
      subtitle: 'Lohegaon, Viman Nagar corridor',
      targetEnu: Vec3(6200.0, 4800.0, 25.0),
      latitude: 18.5822,
      longitude: 73.9197,
    ),
    const NavDestination(
      name: 'Hinjewadi IT Park (Phase 1)',
      subtitle: 'Rajiv Gandhi Infotech Park / Expressway Link',
      targetEnu: Vec3(-12400.0, 6800.0, -10.0),
      latitude: 18.5913,
      longitude: 73.7389,
    ),
    const NavDestination(
      name: 'Mumbai Bandra-Kurla Complex (BKC)',
      subtitle: 'G-Block Financial District & WEH Link',
      targetEnu: Vec3(-78000.0, 58000.0, 5.0),
      latitude: 19.0657,
      longitude: 72.8687,
    ),
    const NavDestination(
      name: 'Katraj Tunnel & Bypass Portal',
      subtitle: 'NH-48 New Katraj Viaduct corridor',
      targetEnu: Vec3(-1500.0, -8400.0, 45.0),
      latitude: 18.4480,
      longitude: 73.8580,
    ),
    const NavDestination(
      name: 'Atal Setu (MTHL) Sea Viaduct',
      subtitle: 'Mumbai Trans Harbour Link approach',
      targetEnu: Vec3(-74000.0, 51000.0, 18.0),
      latitude: 18.9980,
      longitude: 72.9500,
    ),
    const NavDestination(
      name: 'Lonavala Expressway Ghat Section',
      subtitle: 'Bhor Ghat Khandala viaducts',
      targetEnu: Vec3(-48000.0, 32000.0, 320.0),
      latitude: 18.7550,
      longitude: 73.4080,
    ),
    const NavDestination(
      name: 'Swargate Junction Interchange',
      subtitle: 'Shivaji Road & Satara Road intersection',
      targetEnu: Vec3(200.0, -2200.0, 0.0),
      latitude: 18.5010,
      longitude: 73.8580,
    ),
  ];

  /// Plans a navigation route from [originEnu] to [destination].
  ///
  /// Uses offline vector road graph routing first. If road graph is empty or disconnected
  /// and network is available with valid coordinates, attempts OSRM fallback.
  static Future<NavRoute> calculateRoute({
    required Vec3 originEnu,
    required NavDestination destination,
    required List<MapBranch> roadBranches,
    double? refLat,
    double? refLon,
    double? originLat,
    double? originLon,
  }) async {
    // Dynamically re-project targetEnu if geodetic coordinates and anchor are available
    NavDestination effectiveDest = destination;
    if (destination.latitude != null &&
        destination.longitude != null &&
        refLat != null &&
        refLon != null) {
      final accurateEnu = MathUtils.wgs84ToEnu(
        lat: destination.latitude!,
        lon: destination.longitude!,
        refLat: refLat,
        refLon: refLon,
      );
      effectiveDest = NavDestination(
        name: destination.name,
        subtitle: destination.subtitle,
        targetEnu: accurateEnu,
        latitude: destination.latitude,
        longitude: destination.longitude,
        isCustomPin: destination.isCustomPin,
      );
    }

    // 1. Try offline A* pathfinder over loaded road network
    if (roadBranches.isNotEmpty) {
      final offlineRoute = _planAStarRoute(
        origin: originEnu,
        destination: effectiveDest,
        branches: roadBranches,
      );
      if (offlineRoute != null && offlineRoute.points.length >= 2) {
        return offlineRoute;
      }
    }

    // 2. Try online OSRM fallback if coordinates are available
    if (originLat != null &&
        originLon != null &&
        effectiveDest.latitude != null &&
        effectiveDest.longitude != null &&
        refLat != null &&
        refLon != null) {
      try {
        final onlineRoute = await _fetchOsrmRoute(
          originLat: originLat,
          originLon: originLon,
          destLat: effectiveDest.latitude!,
          destLon: effectiveDest.longitude!,
          destination: effectiveDest,
          refLat: refLat,
          refLon: refLon,
        );
        if (onlineRoute != null) {
          return onlineRoute;
        }
      } catch (e) {
        debugPrint('[RoutingService] OSRM fallback failed: $e');
      }
    }

    // 3. Fallback: Direct Connected Road Corridor
    return _buildDirectCorridorRoute(originEnu, effectiveDest, roadBranches);
  }

  /// Offline A* graph pathfinder over [MapBranch] road segments with O(N) spatial indexing.
  static NavRoute? _planAStarRoute({
    required Vec3 origin,
    required NavDestination destination,
    required List<MapBranch> branches,
  }) {
    if (branches.isEmpty) return null;

    // Fast Spatial Hashing for Graph Nodes (drops graph construction from O(N^2) to O(N))
    final nodes = <Vec3>[];
    final nodeMap = <int, List<_GraphEdge>>{};
    final spatialGrid = <int, List<int>>{};

    int getOrAddNode(Vec3 p) {
      final gx = (p.x / 20.0).floor();
      final gy = (p.y / 20.0).floor();

      // Check 3x3 surrounding spatial cells
      for (int dx = -1; dx <= 1; dx++) {
        for (int dy = -1; dy <= 1; dy++) {
          final cellKey = (gx + dx) * 1000003 + (gy + dy);
          final candidates = spatialGrid[cellKey];
          if (candidates != null) {
            for (final idx in candidates) {
              if ((nodes[idx] - p).norm < 15.0) {
                return idx;
              }
            }
          }
        }
      }

      final idx = nodes.length;
      nodes.add(p);
      nodeMap[idx] = [];
      final centerKey = gx * 1000003 + gy;
      spatialGrid.putIfAbsent(centerKey, () => []).add(idx);
      return idx;
    }

    for (final branch in branches) {
      if (branch.points.length < 2) continue;
      for (int i = 0; i < branch.points.length - 1; i++) {
        final pA = branch.points[i];
        final pB = branch.points[i + 1];
        final dist = (pB - pA).norm;
        if (dist < 0.1) continue; // Skip zero-length micro segments
        final u = getOrAddNode(pA);
        final v = getOrAddNode(pB);
        if (u != v) {
          nodeMap[u]!.add(_GraphEdge(target: v, distance: dist, roadName: branch.name, speedLimit: branch.speedLimitMps));
          if (!branch.oneWay) {
            nodeMap[v]!.add(_GraphEdge(target: u, distance: dist, roadName: branch.name, speedLimit: branch.speedLimitMps));
          }
        }
      }
    }

    if (nodes.isEmpty) return null;

    // Find nearest start node and goal node
    int startNode = 0;
    double minStartDist = double.infinity;
    int goalNode = 0;
    double minGoalDist = double.infinity;

    for (int i = 0; i < nodes.length; i++) {
      final dStart = (nodes[i] - origin).norm;
      if (dStart < minStartDist) {
        minStartDist = dStart;
        startNode = i;
      }
      final dGoal = (nodes[i] - destination.targetEnu).norm;
      if (dGoal < minGoalDist) {
        minGoalDist = dGoal;
        goalNode = i;
      }
    }

    // A* Priority Queue / Open Set
    final openSet = <int>{startNode};
    final cameFrom = <int, int>{};
    final edgeUsed = <int, _GraphEdge>{};

    final gScore = <int, double>{startNode: 0.0};
    final fScore = <int, double>{startNode: (nodes[startNode] - nodes[goalNode]).norm};

    int iterations = 0;
    const maxIterations = 8000;

    while (openSet.isNotEmpty && iterations++ < maxIterations) {
      // Node in openSet with lowest fScore
      int current = openSet.first;
      double lowestF = fScore[current] ?? double.infinity;
      for (final n in openSet) {
        final f = fScore[n] ?? double.infinity;
        if (f < lowestF) {
          lowestF = f;
          current = n;
        }
      }

      if (current == goalNode) {
        // Reconstruct path with cycle guard to prevent any infinite loop
        final pathNodes = <int>[current];
        final visitedSet = <int>{current};
        while (cameFrom.containsKey(current)) {
          current = cameFrom[current]!;
          if (visitedSet.contains(current)) break; // Cycle guard
          visitedSet.add(current);
          pathNodes.add(current);
        }
        final orderedNodes = pathNodes.reversed.toList();

        final polyline = <Vec3>[origin];
        for (final idx in orderedNodes) {
          polyline.add(nodes[idx]);
        }
        polyline.add(destination.targetEnu);

        // Build maneuvers
        return _generateNavRouteFromPolyline(
          polyline: polyline,
          destination: destination,
          isOffline: true,
          branches: branches,
        );
      }

      openSet.remove(current);
      final currentG = gScore[current] ?? double.infinity;

      for (final edge in nodeMap[current] ?? <_GraphEdge>[]) {
        final neighbor = edge.target;
        final tentativeG = currentG + edge.distance;

        if (tentativeG < (gScore[neighbor] ?? double.infinity)) {
          cameFrom[neighbor] = current;
          edgeUsed[neighbor] = edge;
          gScore[neighbor] = tentativeG;
          fScore[neighbor] = tentativeG + (nodes[neighbor] - nodes[goalNode]).norm;
          openSet.add(neighbor);
        }
      }
    }

    return null;
  }

  /// Online OpenStreetMap OSRM fallback router
  static Future<NavRoute?> _fetchOsrmRoute({
    required double originLat,
    required double originLon,
    required double destLat,
    required double destLon,
    required NavDestination destination,
    required double refLat,
    required double refLon,
  }) async {
    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${originLon.toStringAsFixed(6)},${originLat.toStringAsFixed(6)};'
      '${destLon.toStringAsFixed(6)},${destLat.toStringAsFixed(6)}'
      '?overview=full&geometries=geojson&steps=true',
    );

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    final request = await client.getUrl(url);
    final response = await request.close();
    if (response.statusCode != 200) {
      client.close();
      return null;
    }

    final responseBody = await response.transform(utf8.decoder).join();
    client.close();
    final data = jsonDecode(responseBody) as Map<String, dynamic>;
    final routes = data['routes'] as List<dynamic>?;
    if (routes == null || routes.isEmpty) return null;

    final primaryRoute = routes.first as Map<String, dynamic>;
    final totalDistance = (primaryRoute['distance'] as num).toDouble();
    final totalDuration = (primaryRoute['duration'] as num).toDouble();

    final geometry = primaryRoute['geometry'] as Map<String, dynamic>;
    final coords = geometry['coordinates'] as List<dynamic>;

    final enuPoints = <Vec3>[];
    for (final pt in coords) {
      final lon = (pt[0] as num).toDouble();
      final lat = (pt[1] as num).toDouble();
      final enu = MathUtils.wgs84ToEnu(
        lat: lat,
        lon: lon,
        refLat: refLat,
        refLon: refLon,
      );
      enuPoints.add(enu);
    }

    // Parse OSRM Steps
    final steps = <RouteStep>[];
    final legs = primaryRoute['legs'] as List<dynamic>? ?? [];
    for (final leg in legs) {
      final legSteps = leg['steps'] as List<dynamic>? ?? [];
      for (final s in legSteps) {
        final dist = (s['distance'] as num).toDouble();
        final name = (s['name'] as String?)?.trim() ?? 'Connecting Road';
        final maneuverObj = s['maneuver'] as Map<String, dynamic>? ?? {};
        final type = maneuverObj['type'] as String? ?? 'straight';
        final modifier = maneuverObj['modifier'] as String? ?? '';

        ManeuverType maneuverType;
        if (type == 'arrive') {
          maneuverType = ManeuverType.arrive;
        } else if (type == 'depart') {
          maneuverType = ManeuverType.depart;
        } else if (modifier.contains('left')) {
          maneuverType = modifier.contains('slight') ? ManeuverType.slightLeft : ManeuverType.turnLeft;
        } else if (modifier.contains('right')) {
          maneuverType = modifier.contains('slight') ? ManeuverType.slightRight : ManeuverType.turnRight;
        } else if (modifier.contains('uturn')) {
          maneuverType = ManeuverType.uTurn;
        } else {
          maneuverType = ManeuverType.continueStraight;
        }

        final instruction = _formatInstruction(maneuverType, name, dist);

        steps.add(RouteStep(
          instruction: instruction,
          maneuver: maneuverType,
          distanceMeters: dist,
          startPosEnu: enuPoints.isNotEmpty ? enuPoints.first : Vec3.zero,
          endPosEnu: enuPoints.isNotEmpty ? enuPoints.last : Vec3.zero,
          roadName: name.isEmpty ? 'Highway' : name,
          expectedSpeedMps: totalDistance > 0 && totalDuration > 0 ? (totalDistance / totalDuration) : 16.67,
        ));
      }
    }

    return NavRoute(
      destination: destination,
      points: enuPoints,
      steps: steps,
      totalDistanceMeters: totalDistance,
      estimatedDurationSeconds: totalDuration,
      isOfflineAStar: false,
    );
  }

  /// Construct a direct smooth corridor connecting origin to destination via intermediate waypoints
  static NavRoute _buildDirectCorridorRoute(
    Vec3 origin,
    NavDestination destination,
    List<MapBranch> branches,
  ) {
    final dist = (destination.targetEnu - origin).norm;
    final points = <Vec3>[origin];

    // Find if any nearby road branch can form a waypoint
    if (branches.isNotEmpty) {
      MapBranch? closest;
      double closestD = double.infinity;
      for (final b in branches) {
        for (final p in b.points) {
          final d = (p - origin).norm;
          if (d > 50.0 && d < dist * 0.7 && d < closestD) {
            closestD = d;
            closest = b;
          }
        }
      }
      if (closest != null && closest.points.isNotEmpty) {
        final midIdx = closest.points.length ~/ 2;
        points.add(closest.points[midIdx]);
      }
    }

    // Add intermediate curvature waypoints for realism
    final dir = (destination.targetEnu - origin).normalized;
    final normal = Vec3(-dir.y, dir.x, 0.0);
    final pMid = (origin + destination.targetEnu) * 0.5 + normal * (dist * 0.08);
    points.add(pMid);
    points.add(destination.targetEnu);

    return _generateNavRouteFromPolyline(
      polyline: points,
      destination: destination,
      isOffline: true,
      branches: branches,
    );
  }

  /// Extracts turn-by-turn maneuvers from a polyline sequence
  static NavRoute _generateNavRouteFromPolyline({
    required List<Vec3> polyline,
    required NavDestination destination,
    required bool isOffline,
    required List<MapBranch> branches,
  }) {
    double totalDist = 0.0;
    for (int i = 0; i < polyline.length - 1; i++) {
      totalDist += (polyline[i + 1] - polyline[i]).norm;
    }

    final steps = <RouteStep>[];

    // Depart step
    final firstSeg = polyline.length >= 2 ? (polyline[1] - polyline[0]) : Vec3(0, 1, 0);
    final initBearing = MathUtils.radToDeg(math.atan2(firstSeg.x, firstSeg.y));
    final initCompass = _bearingToCompassCardinal(initBearing);
    final initialRoadName = _findNearestRoadName(polyline.first, branches);

    steps.add(RouteStep(
      instruction: 'Head $initCompass on $initialRoadName',
      maneuver: ManeuverType.depart,
      distanceMeters: polyline.length >= 2 ? (polyline[1] - polyline[0]).norm : 50.0,
      startPosEnu: polyline.first,
      endPosEnu: polyline.length >= 2 ? polyline[1] : polyline.first,
      roadName: initialRoadName,
      expectedSpeedMps: 16.67,
    ));

    // Analyze bearing changes between successive segments
    for (int i = 1; i < polyline.length - 1; i++) {
      final pPrev = polyline[i - 1];
      final pCurr = polyline[i];
      final pNext = polyline[i + 1];

      final v1 = pCurr - pPrev;
      final v2 = pNext - pCurr;

      final dist = v2.norm;
      if (dist < 5.0) continue;

      final heading1 = math.atan2(v1.x, v1.y);
      final heading2 = math.atan2(v2.x, v2.y);
      final deltaHeadingDeg = MathUtils.radToDeg(MathUtils.normalizeAngle(heading2 - heading1));

      final roadName = _findNearestRoadName(pCurr, branches);

      ManeuverType maneuver;
      if (deltaHeadingDeg > 45.0 && deltaHeadingDeg < 135.0) {
        maneuver = ManeuverType.turnRight;
      } else if (deltaHeadingDeg < -45.0 && deltaHeadingDeg > -135.0) {
        maneuver = ManeuverType.turnLeft;
      } else if (deltaHeadingDeg >= 15.0 && deltaHeadingDeg <= 45.0) {
        maneuver = ManeuverType.slightRight;
      } else if (deltaHeadingDeg <= -15.0 && deltaHeadingDeg >= -45.0) {
        maneuver = ManeuverType.slightLeft;
      } else if (deltaHeadingDeg.abs() >= 135.0) {
        maneuver = ManeuverType.uTurn;
      } else {
        maneuver = ManeuverType.continueStraight;
      }

      if (maneuver != ManeuverType.continueStraight || i == polyline.length - 2) {
        final instruction = _formatInstruction(maneuver, roadName, dist);
        steps.add(RouteStep(
          instruction: instruction,
          maneuver: maneuver,
          distanceMeters: dist,
          startPosEnu: pCurr,
          endPosEnu: pNext,
          roadName: roadName,
          expectedSpeedMps: 16.67,
        ));
      }
    }

    // Arrive step
    steps.add(RouteStep(
      instruction: 'Arrive at ${destination.name}',
      maneuver: ManeuverType.arrive,
      distanceMeters: 0.0,
      startPosEnu: destination.targetEnu,
      endPosEnu: destination.targetEnu,
      roadName: destination.name,
      expectedSpeedMps: 0.0,
    ));

    final estDuration = totalDist / 16.67; // ~60 km/h average speed

    return NavRoute(
      destination: destination,
      points: polyline,
      steps: steps,
      totalDistanceMeters: totalDist,
      estimatedDurationSeconds: estDuration,
      isOfflineAStar: isOffline,
    );
  }

  static String _formatInstruction(ManeuverType m, String road, double dist) {
    final distStr = dist >= 1000.0 ? '${(dist / 1000.0).toStringAsFixed(1)} km' : '${dist.round()} m';
    switch (m) {
      case ManeuverType.turnLeft:
        return 'In $distStr, turn left onto $road';
      case ManeuverType.turnRight:
        return 'In $distStr, turn right onto $road';
      case ManeuverType.slightLeft:
        return 'In $distStr, bear left toward $road';
      case ManeuverType.slightRight:
        return 'In $distStr, bear right toward $road';
      case ManeuverType.sharpLeft:
        return 'In $distStr, take sharp left onto $road';
      case ManeuverType.sharpRight:
        return 'In $distStr, take sharp right onto $road';
      case ManeuverType.uTurn:
        return 'In $distStr, make a U-turn';
      case ManeuverType.forkLeft:
        return 'Keep left at the fork onto $road';
      case ManeuverType.forkRight:
        return 'Keep right at the fork onto $road';
      case ManeuverType.arrive:
        return 'Arrive at destination';
      case ManeuverType.depart:
      case ManeuverType.continueStraight:
        return 'Continue on $road for $distStr';
    }
  }

  static String _bearingToCompassCardinal(double bearingDeg) {
    final norm = (bearingDeg % 360.0 + 360.0) % 360.0;
    if (norm >= 337.5 || norm < 22.5) return 'North';
    if (norm < 67.5) return 'North-East';
    if (norm < 112.5) return 'East';
    if (norm < 157.5) return 'South-East';
    if (norm < 202.5) return 'South';
    if (norm < 247.5) return 'South-West';
    if (norm < 292.5) return 'West';
    return 'North-West';
  }

  static String _findNearestRoadName(Vec3 p, List<MapBranch> branches) {
    String best = 'Main Road';
    double minD = double.infinity;
    for (final b in branches) {
      for (final pt in b.points) {
        final d = (pt - p).norm;
        if (d < minD) {
          minD = d;
          best = b.name;
        }
      }
    }
    return best;
  }
}

class _GraphEdge {
  final int target;
  final double distance;
  final String roadName;
  final double speedLimit;

  const _GraphEdge({
    required this.target,
    required this.distance,
    required this.roadName,
    required this.speedLimit,
  });
}
