import '../core/math_utils.dart';

/// Types of road maneuvers for turn-by-turn guidance.
enum ManeuverType {
  depart,
  continueStraight,
  turnLeft,
  turnRight,
  slightLeft,
  slightRight,
  sharpLeft,
  sharpRight,
  uTurn,
  forkLeft,
  forkRight,
  arrive,
}

/// Individual turn instruction step along a planned route.
class RouteStep {
  final String instruction;
  final ManeuverType maneuver;
  final double distanceMeters;
  final Vec3 startPosEnu;
  final Vec3 endPosEnu;
  final String roadName;
  final double expectedSpeedMps;

  const RouteStep({
    required this.instruction,
    required this.maneuver,
    required this.distanceMeters,
    required this.startPosEnu,
    required this.endPosEnu,
    required this.roadName,
    this.expectedSpeedMps = 16.67, // ~60 km/h default
  });

  /// Duration in seconds based on expected road speed
  double get estimatedDurationSeconds =>
      expectedSpeedMps > 0 ? distanceMeters / expectedSpeedMps : 0.0;
}

/// Navigation destination with both local Cartesian ENU coordinates and WGS-84 geodetic coordinates.
class NavDestination {
  final String name;
  final String? subtitle;
  final Vec3 targetEnu;
  final double? latitude;
  final double? longitude;
  final bool isCustomPin;

  const NavDestination({
    required this.name,
    this.subtitle,
    required this.targetEnu,
    this.latitude,
    this.longitude,
    this.isCustomPin = false,
  });

  @override
  String toString() => 'NavDestination($name, enu: $targetEnu)';
}

/// Complete planned navigation route from vehicle to target destination.
class NavRoute {
  final NavDestination destination;
  final List<Vec3> points; // Polyline in local ENU
  final List<RouteStep> steps;
  final double totalDistanceMeters;
  final double estimatedDurationSeconds;
  final bool isOfflineAStar;

  const NavRoute({
    required this.destination,
    required this.points,
    required this.steps,
    required this.totalDistanceMeters,
    required this.estimatedDurationSeconds,
    this.isOfflineAStar = true,
  });

  double get totalDistanceKm => totalDistanceMeters / 1000.0;
  int get estimatedDurationMinutes => (estimatedDurationSeconds / 60.0).ceil();

  /// Formatted arrival clock time from current time
  String formattedEtaClock() {
    final eta = DateTime.now().add(Duration(seconds: estimatedDurationSeconds.round()));
    final hour = eta.hour > 12 ? eta.hour - 12 : (eta.hour == 0 ? 12 : eta.hour);
    final minute = eta.minute.toString().padLeft(2, '0');
    final period = eta.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}
