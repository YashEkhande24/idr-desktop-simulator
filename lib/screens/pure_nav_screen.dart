import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../core/math_utils.dart';
import '../models/nav_solution.dart';
import '../models/navigation_models.dart';
import '../services/idr_pipeline.dart';
import '../services/sensor_service.dart';
import '../widgets/destination_picker_sheet.dart';
import '../widgets/flutter_map_canvas.dart';
import '../widgets/oscilloscope_widget.dart';
import '../widgets/rotating_compass.dart';
import '../widgets/unified_tools_sheet.dart';

/// Pure Navigation Screen
///
/// Clean Google Maps style turn-by-turn navigation with streamlined controls:
/// - Full-bleed vector canvas with 3D tilt in Course-Up mode
/// - 4 floating action buttons (Search, Compass, Locate, Tools)
/// - Compact bottom sensor dock
/// - Top guidance banner with GNSS status
class PureNavScreen extends StatefulWidget {
  const PureNavScreen({super.key});

  @override
  State<PureNavScreen> createState() => _PureNavScreenState();
}

class _PureNavScreenState extends State<PureNavScreen> {
  bool _showDrawer = false;
  bool _isCourseUp = true; // Google Maps course-up driving mode default
  int _recenterCounter = 0;
  double _smoothSpeedKmh = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<IdrPipeline>().forceRefreshGps();
    });
  }

  @override
  Widget build(BuildContext context) {
    final pipeline = context.watch<IdrPipeline>();
    final solution = pipeline.latestSolution;

    return Scaffold(
      backgroundColor: const Color(0xFF030712),
      body: solution == null
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8)))
          : Stack(
              children: [
                // 1. Full-Bleed Vector Map Canvas (3D tilt in Course-Up mode)
                Positioned.fill(
                  child: FlutterMapCanvas(
                    solution: solution,
                    roadBranches: pipeline.mapSnapper.branches,
                    sensorService: pipeline.sensorService,
                    isCourseUp: _isCourseUp,
                    recenterTrigger: _recenterCounter,
                    onToggleCourseUp: () {
                      setState(() {
                        _isCourseUp = !_isCourseUp;
                      });
                    },
                    activeRoute: pipeline.navigationService.route,
                    onMapTap: (point) {
                      final tapDest = NavDestination(
                        name: 'Map Dropped Pin',
                        subtitle: 'Coordinates: ${point.latitude.toStringAsFixed(4)}°, ${point.longitude.toStringAsFixed(4)}°',
                        targetEnu: MathUtils.wgs84ToEnu(
                          lat: point.latitude,
                          lon: point.longitude,
                          refLat: pipeline.sensorService.refLat ?? point.latitude,
                          refLon: pipeline.sensorService.refLon ?? point.longitude,
                        ),
                        latitude: point.latitude,
                        longitude: point.longitude,
                        isCustomPin: true,
                      );
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => DestinationPickerSheet(
                          pipeline: pipeline,
                          initialDestination: tapDest,
                        ),
                      );
                    },

                  ),
                ),

                // 2. Top Floating Navigation Guidance Banner
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
                      child: _buildGoogleMapsNavHeader(context, pipeline, solution),
                    ),
                  ),
                ),

                // 3. Right Floating Action Controls (matches Google Maps chrome)
                Positioned(
                  top: 105,
                  right: 14,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Compass (White circle, red/silver 3D needle)
                      RotatingCompass(
                        headingDeg: solution.headingDeg,
                        isCourseUp: _isCourseUp,
                        onToggleMode: () {
                          setState(() {
                            _isCourseUp = !_isCourseUp;
                          });
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(_isCourseUp
                                  ? 'Course-Up 3D Driving Mode'
                                  : 'North-Up Flat Mode'),
                              duration: const Duration(milliseconds: 1400),
                              backgroundColor: const Color(0xFF0F172A),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 10),

                      // Search / Destination
                      _buildFloatingGlassButton(
                        icon: Icons.search,
                        tooltip: 'Where to?',
                        color: const Color(0xFF334155),
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => DestinationPickerSheet(pipeline: pipeline),
                          );
                        },
                      ),

                      const SizedBox(height: 10),

                      // Audio / Voice Guidance Toggle
                      _buildFloatingGlassButton(
                        icon: Icons.volume_up_outlined,
                        tooltip: 'Audio Guidance',
                        color: const Color(0xFF334155),
                        onTap: () {
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Voice guidance active'),
                              duration: Duration(milliseconds: 1200),
                              backgroundColor: Color(0xFF0F172A),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 10),

                      // Tools & Settings
                      _buildFloatingGlassButton(
                        icon: Icons.tune,
                        tooltip: 'Tools & Settings',
                        color: const Color(0xFF334155),
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => const UnifiedToolsSheet(),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                // 4. Floating Bottom-Left "Re-centre" Button (matches Google Maps)
                Positioned(
                  bottom: pipeline.navigationService.isNavigating ? 95 : 75,
                  left: 14,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () async {
                        setState(() {
                          _recenterCounter++;
                          _isCourseUp = true;
                        });
                        await pipeline.forceRefreshGps();
                      },
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.16),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.navigation, size: 16, color: Color(0xFF047857)),
                            const SizedBox(width: 6),
                            Text(
                              'Re-centre',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF047857),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // 5. Bottom Navigation Dock: ETA Card when navigating, or Sensor Dock when free-driving
                if (pipeline.navigationService.isNavigating)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                        child: _buildNavigationSummaryDock(context, pipeline),
                      ),
                    ),
                  )
                else
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                        child: _buildBottomSensorDock(pipeline, solution),
                      ),
                    ),
                  ),

                // 6. Optional Sliding Diagnostic Drawer
                if (_showDrawer)
                  Positioned(
                    bottom: 90,
                    left: 14,
                    right: 14,
                    child: _buildDiagnosticDrawer(solution),
                  ),
              ],
            ),
    );
  }

  /// Clean white floating circular button matching Google Maps navigation chrome
  Widget _buildFloatingGlassButton({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(icon, color: color, size: 21),
        ),
      ),
    );
  }

  /// Google Maps style turn-by-turn guidance header card with prominent GNSS status banner & live drift scorecard.
  Widget _buildGoogleMapsNavHeader(BuildContext context, IdrPipeline pipeline, NavSolution solution) {
    final isDenied = solution.isGnssDenied;
    final msg = solution.gpsStatusMessage?.toLowerCase() ?? '';
    String statusText;
    Color statusColor;

    if (msg.contains('disabled')) {
      statusText = 'GPS DISABLED';
      statusColor = const Color(0xFFEF4444);
    } else if (msg.contains('permission')) {
      statusText = 'NO PERMISSION';
      statusColor = const Color(0xFFEF4444);
    } else if (msg.contains('searching')) {
      statusText = 'SEARCHING GPS';
      statusColor = const Color(0xFFF59E0B);
    } else if (isDenied) {
      statusText = 'GNSS DENIED';
      statusColor = const Color(0xFFEF4444);
    } else if (solution.hdop > 2.5) {
      statusText = 'DEGRADED GNSS';
      statusColor = const Color(0xFFF59E0B);
    } else {
      statusText = 'GNSS ACTIVE';
      statusColor = const Color(0xFF10B981);
    }

    final roadName = solution.matchedRoadName ?? 'Open Road';
    final crossTrackText = solution.isMapMatched
        ? '±${solution.crossTrackMeters.abs().toStringAsFixed(1)}m'
        : 'TRACKING';

    final rawSpeed = solution.speedKmh;
    // Deadband: If speed < 0.8 km/h, snap firmly to 0.0
    final targetSpeed = rawSpeed < 0.8 ? 0.0 : rawSpeed;
    if (targetSpeed == 0.0) {
      _smoothSpeedKmh = 0.0;
    } else {
      _smoothSpeedKmh = _smoothSpeedKmh == 0.0
          ? targetSpeed
          : (_smoothSpeedKmh * 0.65 + targetSpeed * 0.35);
    }
    final displaySpeedStr = _smoothSpeedKmh.toStringAsFixed(1);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Mode & Live Coordinates Quick Bar
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // IDR Navigator Label
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7).withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF38BDF8)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.navigation, size: 12, color: Color(0xFF38BDF8)),
                    const SizedBox(width: 5),
                    Text(
                      'IDR NAVIGATOR',
                      style: GoogleFonts.rajdhani(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),

              // Geodetic Coordinates Pill
              if (solution.latitude != null && solution.longitude != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF1E293B)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.location_on, size: 11, color: Color(0xFF38BDF8)),
                      const SizedBox(width: 3),
                      Text(
                        '${solution.latitude!.abs().toStringAsFixed(4)}°${solution.latitude! >= 0 ? "N" : "S"}, ${solution.longitude!.abs().toStringAsFixed(4)}°${solution.longitude! >= 0 ? "E" : "W"}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFE2E8F0),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),

        // Main Guidance Card (or Turn-by-Turn Card if navigating)
        if (pipeline.navigationService.isNavigating && pipeline.navigationService.currentStep != null)
          _buildTurnByTurnGuidanceCard(context, pipeline, solution)
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF044E43), // Google Maps dark teal
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.28),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Maneuver / Direction Arrow
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.navigation,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Road Name & Guidance Subtitle
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          solution.isMapMatched ? 'Head towards' : 'Drive towards',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFFCCFBF1),
                          ),
                        ),
                        Text(
                          roadName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(Icons.turn_slight_left, size: 13, color: Color(0xFF99F6E4)),
                            const SizedBox(width: 3),
                            Text(
                              'Then ↰',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF99F6E4),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                solution.isMapMatched ? crossTrackText : (isDenied ? 'DR MODE' : 'TRACKING'),
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Live Speed & Status Badge Readout
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            displaySpeedStr,
                            style: GoogleFonts.rajdhani(
                              fontSize: 25,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            'KM/H',
                            style: GoogleFonts.rajdhani(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFFCCFBF1),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.28),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: statusColor.withValues(alpha: 0.8), width: 1.0),
                        ),
                        child: Text(
                          statusText,
                          style: GoogleFonts.inter(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

        // Location Service Disabled Alert Banner
        if (pipeline.gpsHardwareStatus == GpsHardwareStatus.serviceDisabled) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: const Color(0xFF991B1B),
              child: Row(
                children: [
                  const Icon(Icons.location_off, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Device Location (GPS) is turned OFF',
                      style: GoogleFonts.rajdhani(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => pipeline.openLocationSettings(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF991B1B),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                    ),
                    child: Text(
                      'TURN ON GPS',
                      style: GoogleFonts.rajdhani(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ] else if (pipeline.gpsHardwareStatus == GpsHardwareStatus.permissionDenied ||
            pipeline.gpsHardwareStatus == GpsHardwareStatus.permissionDeniedForever) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: const Color(0xFF991B1B),
              child: Row(
                children: [
                  const Icon(Icons.security, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Location permission is required',
                      style: GoogleFonts.rajdhani(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => pipeline.openAppSettings(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF991B1B),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                    ),
                    child: Text(
                      'GRANT ACCESS',
                      style: GoogleFonts.rajdhani(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],

        // Live GNSS Outage Drift Banner (Appears whenever GNSS is denied)
        if (isDenied) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF7F1D1D).withValues(alpha: 0.90),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFEF4444), width: 1.2),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.timer_outlined, size: 14, color: Color(0xFFFCA5A5)),
                        const SizedBox(width: 4),
                        Text(
                          'OUTAGE: ${_formatSeconds(solution.drOutageDurationSec)}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Icon(Icons.straighten, size: 14, color: Color(0xFFFCA5A5)),
                        const SizedBox(width: 4),
                        Text(
                          'DIST: ${solution.drDistanceTraveled.toStringAsFixed(0)}m',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: solution.drDriftPercent < 10.0
                            ? const Color(0xFF064E3B)
                            : const Color(0xFF991B1B),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: solution.drDriftPercent < 10.0
                              ? const Color(0xFF10B981)
                              : const Color(0xFFEF4444),
                        ),
                      ),
                      child: Text(
                        'DRIFT: ${solution.drDriftPercent.toStringAsFixed(1)}% ${solution.drDriftPercent < 10.0 ? "(PASS)" : "(FAIL)"}',
                        style: GoogleFonts.rajdhani(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: solution.drDriftPercent < 10.0
                              ? const Color(0xFF34D399)
                              : const Color(0xFFFCA5A5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Active Turn-by-Turn Maneuver Guidance Card (replaces default road card when navigating)
  Widget _buildTurnByTurnGuidanceCard(BuildContext context, IdrPipeline pipeline, NavSolution solution) {
    final nav = pipeline.navigationService;
    final step = nav.currentStep!;
    final isOffRoute = nav.isOffRoute;
    final hasArrived = nav.hasArrived;

    IconData maneuverIcon;
    switch (step.maneuver) {
      case ManeuverType.turnLeft:
        maneuverIcon = Icons.turn_left;
        break;
      case ManeuverType.turnRight:
        maneuverIcon = Icons.turn_right;
        break;
      case ManeuverType.slightLeft:
        maneuverIcon = Icons.turn_slight_left;
        break;
      case ManeuverType.slightRight:
        maneuverIcon = Icons.turn_slight_right;
        break;
      case ManeuverType.sharpLeft:
        maneuverIcon = Icons.turn_sharp_left;
        break;
      case ManeuverType.sharpRight:
        maneuverIcon = Icons.turn_sharp_right;
        break;
      case ManeuverType.uTurn:
        maneuverIcon = Icons.u_turn_left;
        break;
      case ManeuverType.arrive:
        maneuverIcon = Icons.flag;
        break;
      case ManeuverType.forkLeft:
        maneuverIcon = Icons.fork_left;
        break;
      case ManeuverType.forkRight:
        maneuverIcon = Icons.fork_right;
        break;
      case ManeuverType.depart:
      case ManeuverType.continueStraight:
        maneuverIcon = Icons.straight;
        break;
    }

    final Color bannerBgColor = isOffRoute
        ? const Color(0xFF78350F)
        : (hasArrived ? const Color(0xFF065F46) : const Color(0xFF044E43));

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: bannerBgColor, // Google Maps dark teal (or warning/arrival state)
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Large Directional Maneuver Icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(maneuverIcon, color: Colors.white, size: 30),
            ),
            const SizedBox(width: 12),

            // Countdown Distance & Instruction
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    hasArrived
                        ? 'ARRIVED'
                        : (isOffRoute ? 'OFF ROUTE' : nav.formatDistance(nav.distanceToNextManeuverMeters)),
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isOffRoute
                        ? 'Recalculating route...'
                        : (nav.destination != null ? 'towards ${nav.destination!.name}' : step.instruction),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFCCFBF1),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.turn_slight_left, size: 13, color: Color(0xFF99F6E4)),
                      const SizedBox(width: 3),
                      Text(
                        'Then ↰',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF99F6E4),
                        ),
                      ),
                      const Spacer(),
                      const Icon(Icons.auto_awesome, size: 16, color: Colors.white70),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // Cancel navigation button
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white70, size: 22),
              tooltip: 'End Navigation',
              onPressed: () {
                nav.cancelNavigation();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Navigation ended'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Google Maps style floating bottom ETA dock
  Widget _buildNavigationSummaryDock(BuildContext context, IdrPipeline pipeline) {
    final nav = pipeline.navigationService;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Close Navigation Button (X in circular grey background)
          InkWell(
            onTap: () {
              nav.cancelNavigation();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Navigation ended'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                color: Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Color(0xFF5F6368), size: 20),
            ),
          ),

          const SizedBox(width: 14),

          // Bold Green Travel Time & Distance / Clock Subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  nav.formatRemainingTime(),
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: const Color(0xFF137333), // Vibrant Google Maps green
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${nav.formatDistance(nav.remainingDistanceMeters)} • ${nav.formattedArrivalClock()}',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF5F6368),
                  ),
                ),
              ],
            ),
          ),

          // Route alternative split icon
          IconButton(
            icon: const Icon(Icons.alt_route, color: Color(0xFF5F6368), size: 24),
            tooltip: 'Alternative Routes',
            onPressed: () => nav.recalculateRoute(pipeline),
          ),
        ],
      ),
    );
  }

  String _formatSeconds(double seconds) {
    final int totalSec = seconds.toInt();
    final int m = totalSec ~/ 60;
    final int s = totalSec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// Clean white floating bottom sensor dock matching Google Maps design
  Widget _buildBottomSensorDock(IdrPipeline pipeline, NavSolution solution) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // IDR Drift Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFA7F3D0)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'DRIFT ',
                  style: GoogleFonts.inter(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF065F46),
                  ),
                ),
                Text(
                  '${solution.idrDriftError.toStringAsFixed(1)}m',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF047857),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 6),

          // Speed readout pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.psychology_outlined, size: 13, color: Color(0xFF0284C7)),
                const SizedBox(width: 2),
                Text(
                  '${solution.tcnSpeedKmh.toStringAsFixed(0)}k',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF334155),
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Start/Pause Toggle
          InkWell(
            onTap: () {
              if (pipeline.isRunning) {
                pipeline.pause();
              } else {
                pipeline.start();
              }
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: pipeline.isRunning
                    ? const Color(0xFFE8F5E9)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: pipeline.isRunning
                      ? const Color(0xFF10B981)
                      : const Color(0xFFCBD5E1),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    pipeline.isRunning ? Icons.pause : Icons.play_arrow,
                    size: 13,
                    color: pipeline.isRunning
                        ? const Color(0xFF047857)
                        : const Color(0xFF475569),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    pipeline.isRunning ? 'LIVE' : 'START',
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: pipeline.isRunning
                          ? const Color(0xFF047857)
                          : const Color(0xFF475569),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 5),

          // Diagnostics Expander
          InkWell(
            onTap: () => setState(() => _showDrawer = !_showDrawer),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: _showDrawer
                    ? const Color(0xFFE0F2FE)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _showDrawer ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1),
                ),
              ),
              child: Icon(
                _showDrawer ? Icons.expand_more : Icons.insights,
                size: 14,
                color: _showDrawer ? const Color(0xFF0284C7) : const Color(0xFF475569),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Collapsible diagnostic drawer showing real-time sensor oscilloscopes and detailed metrics.
  Widget _buildDiagnosticDrawer(NavSolution solution) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.7),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'LIVE SENSOR OSCILLOSCOPE & COVARIANCE',
                    style: GoogleFonts.rajdhani(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: const Color(0xFF38BDF8),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16, color: Color(0xFF94A3B8)),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => setState(() => _showDrawer = false),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 120,
                child: OscilloscopeWidget(
                  solution: solution,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
