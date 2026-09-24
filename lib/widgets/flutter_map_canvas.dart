import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/nav_solution.dart';
import '../models/navigation_models.dart';
import '../services/map_snapper.dart';
import '../services/sensor_service.dart';
import 'car_3d_marker.dart';

class FlutterMapCanvas extends StatefulWidget {
  final NavSolution solution;
  final List<MapBranch> roadBranches;
  final SensorService sensorService;
  final bool isCourseUp;
  final VoidCallback? onToggleCourseUp;
  final NavRoute? activeRoute;
  final void Function(LatLng)? onMapTap;

  final int recenterTrigger;

  const FlutterMapCanvas({
    super.key,
    required this.solution,
    required this.roadBranches,
    required this.sensorService,
    this.isCourseUp = false,
    this.onToggleCourseUp,
    this.activeRoute,
    this.onMapTap,
    this.recenterTrigger = 0,
  });

  @override
  State<FlutterMapCanvas> createState() => _FlutterMapCanvasState();
}

class _FlutterMapCanvasState extends State<FlutterMapCanvas> {
  final MapController _mapController = MapController();
  bool _autoFollow = true;
  double _currentZoom = 15.0;
  bool _isMapReady = false;
  bool _hasInitialCentered = false;
  double _lastCameraRotation = 0.0;

  // Convert ENU coordinates (used by our branches) back to WGS84 LatLng
  LatLng? _enuToLatLng(double x, double y) {
    final refLat = widget.sensorService.refLat;
    final refLon = widget.sensorService.refLon;
    if (refLat == null || refLon == null) return null;

    const double rEarth = 6378137.0;
    final refLatRad = refLat * math.pi / 180.0;
    
    final lat = refLat + (y / rEarth) * (180.0 / math.pi);
    final lon = refLon + (x / (rEarth * math.cos(refLatRad))) * (180.0 / math.pi);
    return LatLng(lat, lon);
  }

  @override
  void didUpdateWidget(FlutterMapCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.recenterTrigger != oldWidget.recenterTrigger) {
      _recenterOnVehicle();
      return;
    }
    if (_isMapReady && widget.solution.latitude != null && widget.solution.longitude != null) {
      final currentPos = LatLng(widget.solution.latitude!, widget.solution.longitude!);
      if (!_hasInitialCentered || _autoFollow) {
        _hasInitialCentered = true;
        _mapController.move(currentPos, _currentZoom);
        if (widget.isCourseUp) {
          _updateCameraHeading(-widget.solution.headingDeg);
        } else {
          _updateCameraHeading(0.0);
        }
      }
    }
  }

  void _updateCameraHeading(double targetRotDeg) {
    var diff = (targetRotDeg - _lastCameraRotation) % 360.0;
    if (diff > 180.0) diff -= 360.0;
    if (diff < -180.0) diff += 360.0;

    // Deadband: avoid microscopic camera adjustments (< 0.8 degrees)
    if (diff.abs() < 0.8) return;

    // Smooth exponential approach (alpha = 0.25)
    final newRot = _lastCameraRotation + diff * 0.25;
    _lastCameraRotation = (newRot % 360.0 + 360.0) % 360.0;
    _mapController.rotate(_lastCameraRotation);
  }

  void _recenterOnVehicle() {
    setState(() {
      _autoFollow = true;
    });
    final lat = widget.solution.latitude ?? widget.sensorService.refLat;
    final lon = widget.solution.longitude ?? widget.sensorService.refLon;
    if (lat != null && lon != null) {
      _mapController.move(LatLng(lat, lon), _currentZoom);
      _lastCameraRotation = widget.isCourseUp ? -widget.solution.headingDeg : 0.0;
      _mapController.rotate(_lastCameraRotation);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Current vehicle location
    LatLng vehiclePos;
    if (widget.solution.latitude != null && widget.solution.longitude != null) {
      vehiclePos = LatLng(widget.solution.latitude!, widget.solution.longitude!);
    } else if (widget.sensorService.refLat != null && widget.sensorService.refLon != null) {
      vehiclePos = LatLng(widget.sensorService.refLat!, widget.sensorService.refLon!);
    } else {
      // Default to active geographic region instead of 0,0 Atlantic Ocean
      vehiclePos = const LatLng(19.8477, 75.2564);
    }

    // Convert local ENU branches into Polyline map layers
    final List<Polyline> polylines = [];
    for (final branch in widget.roadBranches) {
      if (branch.points.length < 2) continue;
      
      final List<LatLng> pts = [];
      for (final p in branch.points) {
        final ll = _enuToLatLng(p.x, p.y);
        if (ll != null) pts.add(ll);
      }

      if (pts.isNotEmpty) {
        Color pColor = const Color(0xFF334155).withValues(alpha: 0.75); // minor
        double pWidth = 3.5;
        
        if (branch.isTunnel || branch.name.contains('Tunnel')) {
          pColor = const Color(0xFFF59E0B).withValues(alpha: 0.85);
          pWidth = 5.5;
        } else if (branch.isElevated || branch.name.contains('Flyover')) {
          pColor = const Color(0xFF0284C7).withValues(alpha: 0.95);
          pWidth = 6.5;
        } else if (branch.name.contains('Highway') || branch.name.contains('NH')) {
          pColor = const Color(0xFF475569);
          pWidth = 5.5;
        }

        polylines.add(
          Polyline(
            points: pts,
            color: pColor,
            strokeWidth: pWidth,
          ),
        );
      }
    }

    // Prepare active route polyline if present
    final List<Polyline> routePolylines = [];
    if (widget.activeRoute != null) {
      final routePts = widget.activeRoute!.points
          .map((p) => _enuToLatLng(p.x, p.y))
          .whereType<LatLng>()
          .toList();
      if (routePts.length >= 2) {
        routePolylines.add(
          Polyline(
            points: routePts,
            color: const Color(0xFF3B82F6), // Bright blue route
            strokeWidth: 6.0,
            strokeCap: StrokeCap.round,
            strokeJoin: StrokeJoin.round,
          ),
        );
      }
    }

    // Vehicle orientation:
    // Car3DMarker renders a full real-time 3D polygonal vehicle mesh in perspective!
    final effectiveHeading = widget.isCourseUp ? 0.0 : widget.solution.headingDeg;

    final List<Marker> markers = [
      Marker(
        point: vehiclePos,
        width: 72,
        height: 72,
        alignment: Alignment.center,
        child: Car3DMarker(
          headingDeg: effectiveHeading,
          isCourseUp: widget.isCourseUp,
          size: 72.0,
        ),
      ),
    ];

    if (widget.activeRoute != null) {
      LatLng? destPos;
      if (widget.activeRoute!.destination.latitude != null &&
          widget.activeRoute!.destination.longitude != null) {
        destPos = LatLng(
          widget.activeRoute!.destination.latitude!,
          widget.activeRoute!.destination.longitude!,
        );
      } else {
        destPos = _enuToLatLng(
          widget.activeRoute!.destination.targetEnu.x,
          widget.activeRoute!.destination.targetEnu.y,
        );
      }

      if (destPos != null) {
        markers.add(
          Marker(
            point: destPos,
            width: 36,
            height: 36,
            alignment: Alignment.topCenter,
            child: const Icon(
              Icons.location_on,
              color: Color(0xFFEF4444),
              size: 36,
            ),
          ),
        );
      }
    }

    // Build the core map widget
    Widget mapWidget = FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: vehiclePos,
        initialZoom: _currentZoom,
        onMapReady: () {
          _isMapReady = true;
          final lat = widget.solution.latitude ?? widget.sensorService.refLat;
          final lon = widget.solution.longitude ?? widget.sensorService.refLon;
          if (lat != null && lon != null) {
            _hasInitialCentered = true;
            _mapController.move(LatLng(lat, lon), _currentZoom);
            if (widget.isCourseUp) {
              _mapController.rotate(-widget.solution.headingDeg);
            }
          }
        },
        onPositionChanged: (position, hasGesture) {
          if (hasGesture) {
            setState(() {
              _autoFollow = false;
              _currentZoom = position.zoom;
            });
          }
        },
        onTap: (tapPosition, point) {
          if (widget.onMapTap != null) {
            widget.onMapTap!(point);
          }
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.idr.navigator',
        ),
        PolylineLayer(
          polylines: [
            ...polylines,
            ...routePolylines,
          ],
        ),
        MarkerLayer(
          markers: markers,
        ),
      ],
    );

    return Stack(
      children: [
        // Clean, full-bleed unwarped map viewport matching Google Maps
        Positioned.fill(child: mapWidget),

        // Floating "RE-CENTER" Action Pill
        if (!_autoFollow)
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _recenterOnVehicle,
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFF38BDF8), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0284C7).withValues(alpha: 0.35),
                          blurRadius: 14,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.navigation, size: 18, color: Color(0xFF38BDF8)),
                        const SizedBox(width: 8),
                        Text(
                          'RE-CENTER',
                          style: GoogleFonts.rajdhani(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
