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

  /// Updates vehicle progress along the route at real-time telemetry rates
  void updateVehicleProgress(Vec3 vehiclePos, double vehicleHeadingDeg, IdrPipeline pipeline) {
    if (!_isNavigating || _route == null || _route!.points.length < 2) return;

    final dest = _destination!;
    final distToDestination = (dest.targetEnu - vehiclePos).norm;

    // 1. Destination Arrival Check (< 25m)
    if (distToDestination < 25.0) {
      _hasArrived = true;
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
      }
    }

    // If vehicle departed > 65m from route, flag off-route & auto-reroute
    if (minCrossTrack > 65.0) {
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
      final distToEndOfStep = (activeStep.endPosEnu - vehiclePos).norm;
      _distanceToNextManeuverMeters = distToEndOfStep;

      // Advance step when approaching within 25m of junction or past it
      if (distToEndOfStep < 25.0 && _currentStepIndex < _route!.steps.length - 1) {
        _currentStepIndex++;
        debugPrint('[NavigationService] Advanced to maneuver $_currentStepIndex: ${_route!.steps[_currentStepIndex].instruction}');
      }
    }

    // 4. Compute Remaining Distance along Polyline
    double remDist = (pts[closestSegmentIdx + 1] - vehiclePos).norm;
    for (int i = closestSegmentIdx + 1; i < pts.length - 1; i++) {
      remDist += (pts[i + 1] - pts[i]).norm;
    }
    _remainingDistanceMeters = remDist;

    // 5. Dynamic ETA
    final currentSpeed = pipeline.latestSolution?.idrState.speed ?? 0.0;
    final effectiveSpeed = currentSpeed > 3.0 ? currentSpeed : 16.67; // fallback ~60 km/h
    _remainingTimeSeconds = _remainingDistanceMeters / effectiveSpeed;

    notifyListeners();
  }

  /// Automatically re-plans route from current location to target destination
  Future<void> recalculateRoute(IdrPipeline pipeline) async {
    if (!_isNavigating || _destination == null) return;
    final vehiclePos = pipeline.latestSolution?.idrState.position ?? Vec3.zero;

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
  }
}
