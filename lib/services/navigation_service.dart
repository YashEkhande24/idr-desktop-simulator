import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../core/math_utils.dart';
import '../models/navigation_models.dart';
import 'idr_pipeline.dart';
import 'routing_service.dart';

/// Master Real-Time Turn-by-Turn Navigation Engine.
///
/// Tracks vehicle progress along the active planned route, computes distance-to-next-turn
/// countdowns, detects off-route departures, triggers automated re-routing, and announces arrival.
class NavigationService extends ChangeNotifier {
  bool _isNavigating = false;
  NavDestination? _destination;
  NavRoute? _route;

  int _currentStepIndex = 0;
  double _distanceToNextManeuverMeters = 0.0;
  double _remainingDistanceMeters = 0.0;
  double _remainingTimeSeconds = 0.0;
  bool _isOffRoute = false;
  bool _hasArrived = false;
  DateTime? _lastRerouteTime;
  bool _isRerouting = false;
  double _smoothedSpeedMps = 11.11;

  bool get isNavigating => _isNavigating;
  NavDestination? get destination => _destination;
  NavRoute? get route => _route;
  int get currentStepIndex => _currentStepIndex;
  double get distanceToNextManeuverMeters => _distanceToNextManeuverMeters;
  double get remainingDistanceMeters => _remainingDistanceMeters;
  double get remainingTimeSeconds => _remainingTimeSeconds;
  bool get isOffRoute => _isOffRoute;
  bool get hasArrived => _hasArrived;

  RouteStep? get currentStep {
    if (_route == null || _route!.steps.isEmpty) return null;
    if (_currentStepIndex < _route!.steps.length) {
      return _route!.steps[_currentStepIndex];
    }
    return _route!.steps.last;
  }

  RouteStep? get nextStep {
    if (_route == null || _route!.steps.isEmpty) return null;
    final nextIdx = _currentStepIndex + 1;
    if (nextIdx < _route!.steps.length) {
      return _route!.steps[nextIdx];
    }
    return null;
  }

  /// Formats distance in meters or kilometers
  String formatDistance(double meters) {
    if (meters >= 1000.0) {
      return '${(meters / 1000.0).toStringAsFixed(1)} km';
    }
    return '${meters.round()} m';
  }

  /// Formats remaining time in minutes
  String formatRemainingTime() {
    final mins = (_remainingTimeSeconds / 60.0).ceil();
    if (mins >= 60) {
      final hours = mins ~/ 60;
      final m = mins % 60;
      return '${hours}h ${m}m';
    }
    return '${math.max(1, mins)} min';
  }

  /// Estimated arrival clock time
  String formattedArrivalClock() {
    final eta = DateTime.now().add(Duration(seconds: _remainingTimeSeconds.round()));
    final hour = eta.hour > 12 ? eta.hour - 12 : (eta.hour == 0 ? 12 : eta.hour);
    final minute = eta.minute.toString().padLeft(2, '0');
    final period = eta.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  /// Initiates turn-by-turn guidance to [dest].
  Future<bool> startNavigation(NavDestination dest, IdrPipeline pipeline) async {
    final vehiclePos = pipeline.latestSolution?.idrState.position ?? Vec3.zero;
    final branches = pipeline.mapSnapper.branches;

    try {
      final plannedRoute = await RoutingService.calculateRoute(
        originEnu: vehiclePos,
        destination: dest,
        roadBranches: branches,
        refLat: pipeline.sensorService.refLat,
        refLon: pipeline.sensorService.refLon,
        originLat: pipeline.currentLatitude,
        originLon: pipeline.currentLongitude,
      );

      _destination = dest;
      _route = plannedRoute;
      _isNavigating = true;
      _currentStepIndex = 0;
      _hasArrived = false;
      _isOffRoute = false;
      _remainingDistanceMeters = plannedRoute.totalDistanceMeters;
      _remainingTimeSeconds = plannedRoute.estimatedDurationSeconds;
      _distanceToNextManeuverMeters = plannedRoute.steps.isNotEmpty
          ? plannedRoute.steps.first.distanceMeters
          : 0.0;

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[NavigationService] Error calculating route: $e');
      return false;
    }
  }

  /// Cancels active navigation guidance
  void cancelNavigation() {
    _isNavigating = false;
    _destination = null;
    _route = null;
    _currentStepIndex = 0;
    _hasArrived = false;
    _isOffRoute = false;
    _remainingDistanceMeters = 0.0;
    _remainingTimeSeconds = 0.0;
    _distanceToNextManeuverMeters = 0.0;
    notifyListeners();
  }

  /// Shifts all active route waypoints and destination coordinates when the ENU local origin moves.
  void translateRoute(Vec3 delta) {
    if (_destination != null) {
      _destination = NavDestination(
        name: _destination!.name,
        subtitle: _destination!.subtitle,
        targetEnu: _destination!.targetEnu + delta,
        latitude: _destination!.latitude,
        longitude: _destination!.longitude,
        isCustomPin: _destination!.isCustomPin,
      );
    }
    if (_route != null) {
      final shiftedPoints = _route!.points.map((p) => p + delta).toList();
      final shiftedSteps = _route!.steps.map((s) => RouteStep(
        instruction: s.instruction,
        maneuver: s.maneuver,
        distanceMeters: s.distanceMeters,
        startPosEnu: s.startPosEnu + delta,
        endPosEnu: s.endPosEnu + delta,
        roadName: s.roadName,
        expectedSpeedMps: s.expectedSpeedMps,
      )).toList();
      _route = NavRoute(
        destination: _destination ?? _route!.destination,
        points: shiftedPoints,
        steps: shiftedSteps,
        totalDistanceMeters: _route!.totalDistanceMeters,
        estimatedDurationSeconds: _route!.estimatedDurationSeconds,
        isOfflineAStar: _route!.isOfflineAStar,
      );
    }
    notifyListeners();
  }

  /// Updates vehicle progress along the route at real-time telemetry rates
  void updateVehicleProgress(Vec3 vehiclePos, double vehicleHeadingDeg, IdrPipeline pipeline) {
    if (!_isNavigating || _route == null || _route!.points.length < 2) return;

    final dest = _destination!;
    final dx = dest.targetEnu.x - vehiclePos.x;
    final dy = dest.targetEnu.y - vehiclePos.y;
    final dz = (dest.targetEnu.z - vehiclePos.z).abs();
    final dist2d = math.sqrt(dx * dx + dy * dy);

    // 1. Destination Arrival Check (< 25m horizontal and < 40m vertical, or full 3D norm < 25m)
    if ((dist2d < 25.0 && dz < 40.0) || (dest.targetEnu - vehiclePos).norm < 25.0) {
      _hasArrived = true;
      _isNavigating = false;
      _remainingDistanceMeters = 0.0;
      _distanceToNextManeuverMeters = 0.0;
      _remainingTimeSeconds = 0.0;
      notifyListeners();
      return;
    }

    // 2. Off-Route Cross-Track Deviation Check
    double minCrossTrack = double.infinity;
    int closestSegmentIdx = 0;
    final pts = _route!.points;
    Vec3 closestProjPoint = pts.isNotEmpty ? pts.first : vehiclePos;

    for (int i = 0; i < pts.length - 1; i++) {
      final pA = pts[i];
      final pB = pts[i + 1];
      final ab = pB - pA;
      final lenSq = ab.normSquared;
      if (lenSq < 1e-4) continue;

      final t = MathUtils.clamp((vehiclePos - pA).dot(ab) / lenSq, 0.0, 1.0);
      final pProj = pA + ab * t;
      final d = (vehiclePos - pProj).norm;

      if (d < minCrossTrack) {
        minCrossTrack = d;
        closestSegmentIdx = i;
        closestProjPoint = pProj;
      }
    }

    // If vehicle departed from route, flag off-route & auto-reroute
    // During GNSS outage/denial, relax cross-track tolerance to 120m to accommodate normal DR drift
    final bool isOutage = pipeline.latestSolution?.isGnssDenied == true;
    final double crossTrackThreshold = isOutage ? 120.0 : 65.0;

    if (minCrossTrack > crossTrackThreshold) {
      _isOffRoute = true;
      final now = DateTime.now();
      if (_lastRerouteTime == null || now.difference(_lastRerouteTime!).inSeconds >= 5) {
        _lastRerouteTime = now;
        debugPrint('[NavigationService] Vehicle off-route ($minCrossTrack m). Re-routing...');
        recalculateRoute(pipeline);
      }
    } else {
      _isOffRoute = false;
    }

    // 3. Step Progression & Maneuver Countdown
    if (_route!.steps.isNotEmpty) {
      final activeStep = currentStep!;
      final stepDx = activeStep.endPosEnu.x - vehiclePos.x;
      final stepDy = activeStep.endPosEnu.y - vehiclePos.y;
      final dist2dToEndOfStep = math.sqrt(stepDx * stepDx + stepDy * stepDy);
      _distanceToNextManeuverMeters = dist2dToEndOfStep;

      // Check if vehicle has driven past the junction along step heading
      final sVec = activeStep.endPosEnu - activeStep.startPosEnu;
      final pastJunction = sVec.normSquared > 1.0 &&
          (vehiclePos.x - activeStep.endPosEnu.x) * sVec.x + (vehiclePos.y - activeStep.endPosEnu.y) * sVec.y > 0.0;

      // Advance step when approaching within 25m of junction, or when past it within corridor (preventing high-speed skipped junction lock)
      final stepAdvanceThreshold = isOutage ? 35.0 : 25.0;
      final corridorThreshold = isOutage ? 80.0 : 65.0;
      if ((dist2dToEndOfStep < stepAdvanceThreshold || (pastJunction && dist2dToEndOfStep < corridorThreshold)) &&
          _currentStepIndex < _route!.steps.length - 1) {
        _currentStepIndex++;
        final nextDx = currentStep!.endPosEnu.x - vehiclePos.x;
        final nextDy = currentStep!.endPosEnu.y - vehiclePos.y;
        _distanceToNextManeuverMeters = math.sqrt(nextDx * nextDx + nextDy * nextDy);
        debugPrint('[NavigationService] Advanced to maneuver $_currentStepIndex: ${_route!.steps[_currentStepIndex].instruction}');
      }
    }

    // 4. Compute Remaining Distance along Polyline (along-track from projected point)
    double remDist = (pts[closestSegmentIdx + 1] - closestProjPoint).norm;
    for (int i = closestSegmentIdx + 1; i < pts.length - 1; i++) {
      remDist += (pts[i + 1] - pts[i]).norm;
    }
    _remainingDistanceMeters = remDist;

    // 5. Dynamic ETA
    final currentSpeed = (pipeline.latestSolution?.speedKmh ?? 0.0) / 3.6;
    if (currentSpeed > 2.0) {
      _smoothedSpeedMps = _smoothedSpeedMps * 0.8 + currentSpeed * 0.2;
    }
    final effectiveSpeed = currentSpeed > 2.0 ? currentSpeed : _smoothedSpeedMps;
    _remainingTimeSeconds = _remainingDistanceMeters / math.max(1.0, effectiveSpeed);

    notifyListeners();
  }

  /// Automatically re-plans route from current location to target destination
  Future<void> recalculateRoute(IdrPipeline pipeline) async {
    if (!_isNavigating || _destination == null || _isRerouting) return;
    _isRerouting = true;
    final vehiclePos = pipeline.latestSolution?.idrState.position ?? Vec3.zero;

    try {
      final newRoute = await RoutingService.calculateRoute(
        originEnu: vehiclePos,
        destination: _destination!,
        roadBranches: pipeline.mapSnapper.branches,
        refLat: pipeline.sensorService.refLat,
        refLon: pipeline.sensorService.refLon,
        originLat: pipeline.currentLatitude,
        originLon: pipeline.currentLongitude,
      );

      _route = newRoute;
      _currentStepIndex = 0;
      _isOffRoute = false;
      _remainingDistanceMeters = newRoute.totalDistanceMeters;
      _remainingTimeSeconds = newRoute.estimatedDurationSeconds;
      _distanceToNextManeuverMeters = newRoute.steps.isNotEmpty ? newRoute.steps.first.distanceMeters : 0.0;
      notifyListeners();
    } catch (e) {
      debugPrint('[NavigationService] Error recalculating route: $e');
    } finally {
      _isRerouting = false;
    }
  }
}
