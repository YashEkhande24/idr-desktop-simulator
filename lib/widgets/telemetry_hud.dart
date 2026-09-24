import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/nav_solution.dart';

/// Ultra-Modern Cockpit Telemetry HUD.
///
/// Displays:
/// - Real-time Digital Speedometer & Heading
/// - GNSS Status (Available / Degraded / Denied) with Sigmoid HDOP meter
/// - Side-by-side Drift Error: IDR Proposed (<4m) vs Classic DR (>140m)
/// - Vibration Gate Shock Detector indicator
class TelemetryHud extends StatelessWidget {
  final NavSolution solution;

  const TelemetryHud({
    super.key,
    required this.solution,
  });

  @override
  Widget build(BuildContext context) {
    final isDenied = solution.isGnssDenied || solution.gnssStatus == GnssStatus.denied;
    final isDegraded = solution.gnssStatus == GnssStatus.degraded;

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: isDenied
              ? Colors.redAccent.withValues(alpha: 0.8)
              : const Color(0xFF1E293B),
          width: isDenied ? 2.0 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isDenied
                ? Colors.redAccent.withValues(alpha: 0.25)
                : Colors.black.withValues(alpha: 0.4),
            blurRadius: 16.0,
            spreadRadius: 2.0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Header + Status Badges
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDenied
                          ? Colors.redAccent
                          : isDegraded
                              ? Colors.amberAccent
                              : const Color(0xFF10B981),
                      boxShadow: [
                        BoxShadow(
                          color: (isDenied ? Colors.redAccent : const Color(0xFF10B981)).withValues(alpha: 0.8),
                          blurRadius: 8.0,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'IDR NAVIGATION HUD',
                    style: GoogleFonts.rajdhani(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
              _buildGnssStatusPill(isDenied, isDegraded),
            ],
          ),

          const SizedBox(height: 14),

          // Row 2: Speedometer & Heading
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                solution.speedKmh.toStringAsFixed(1),
                style: GoogleFonts.orbitron(
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -1.0,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'KM/H',
                style: GoogleFonts.rajdhani(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF64748B),
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.explore, size: 16, color: Color(0xFF38BDF8)),
                      const SizedBox(width: 4),
                      Text(
                        '${solution.headingDeg.toStringAsFixed(0)}° ${_getCardinal(solution.headingDeg)}',
                        style: GoogleFonts.rajdhani(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFE2E8F0),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'ALT: ${solution.baroAltitude.toStringAsFixed(1)} m',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Live GPS Geodetic Coordinates & Accuracy
          if (solution.latitude != null && solution.longitude != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF080D1A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF1E293B)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_pin, size: 12, color: Color(0xFF38BDF8)),
                  const SizedBox(width: 5),
                  Text(
                    '${solution.latitude!.abs().toStringAsFixed(5)}° ${solution.latitude! >= 0 ? "N" : "S"}, ${solution.longitude!.abs().toStringAsFixed(5)}° ${solution.longitude! >= 0 ? "E" : "W"}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFE2E8F0),
                    ),
                  ),
                  const Spacer(),
                  if (solution.accuracyMeters != null)
                    Text(
                      'ACC: ±${solution.accuracyMeters!.toStringAsFixed(1)}m',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF38BDF8),
                      ),
                    ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),
          const Divider(color: Color(0xFF1E293B), height: 1),
          const SizedBox(height: 12),

          // Row 3: Drift Comparison (IDR vs Classic DR)
          Row(
            children: [
              // Proposed IDR Card (Green)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF064E3B).withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PROPOSED IDR DRIFT',
                        style: GoogleFonts.rajdhani(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF34D399),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${solution.idrDriftError.toStringAsFixed(2)} m',
                        style: GoogleFonts.orbitron(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF10B981),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Classic DR Card (Red)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7F1D1D).withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFDC2626).withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CLASSIC DR DRIFT',
                        style: GoogleFonts.rajdhani(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFF87171),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${solution.classicDriftError.toStringAsFixed(1)} m',
                        style: GoogleFonts.orbitron(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFFEF4444),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Row 4: Diagnostic Metrics (HDOP, Jerk Gate, Cabin Alignment)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMiniMetric(
                'HDOP',
                solution.hdop.toStringAsFixed(1),
                solution.hdop > 5.0 ? Colors.redAccent : const Color(0xFF38BDF8),
              ),
              _buildMiniMetric(
                'JERK GATE',
                solution.roadCondition,
                solution.shockDetected
                    ? Colors.amberAccent
                    : (solution.roadCondition == 'ROUGH ROAD'
                        ? const Color(0xFF38BDF8)
                        : (solution.roadCondition == 'PEDESTRIAN'
                            ? const Color(0xFFA78BFA)
                            : const Color(0xFF10B981))),
              ),
              _buildMiniMetric(
                'CABIN ALIGN',
                solution.isCabinLocked ? 'LOCKED' : 'ALIGNING...',
                solution.isCabinLocked ? const Color(0xFF10B981) : Colors.orangeAccent,
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Row 5: Smart Map-Matching & NHC Road Snap Strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: solution.isMapMatched
                    ? const Color(0xFF10B981).withValues(alpha: 0.4)
                    : const Color(0xFF334155),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.alt_route_rounded,
                  size: 14,
                  color: solution.isMapMatched ? const Color(0xFF10B981) : const Color(0xFF64748B),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    solution.isMapMatched
                        ? 'MAP-MATCH: ${solution.matchedRoadName ?? 'CENTERLINE'} (Δ ${solution.crossTrackMeters >= 0 ? '+' : ''}${solution.crossTrackMeters.toStringAsFixed(1)}m)'
                        : 'OFF-GRID SEARCH (NHC ACTIVE)',
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.rajdhani(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: solution.isMapMatched ? const Color(0xFF34D399) : const Color(0xFF94A3B8),
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: solution.isMapMatched
                        ? const Color(0xFF064E3B)
                        : const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    solution.isMapMatched ? 'NHC SNAPPED' : 'NHC ACTIVE',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: solution.isMapMatched
                          ? const Color(0xFF6EE7B7)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildGnssStatusPill(bool isDenied, bool isDegraded) {
    Color bg;
    Color text;
    String label;
    IconData icon;

    final msg = solution.gpsStatusMessage?.toLowerCase() ?? '';

    if (msg.contains('disabled')) {
      bg = const Color(0xFF7F1D1D);
      text = const Color(0xFFFCA5A5);
      label = 'GPS DISABLED IN SETTINGS';
      icon = Icons.location_off;
    } else if (msg.contains('permission')) {
      bg = const Color(0xFF7F1D1D);
      text = const Color(0xFFFCA5A5);
      label = 'LOCATION PERMISSION REQUIRED';
      icon = Icons.security;
    } else if (msg.contains('searching')) {
      bg = const Color(0xFF78350F);
      text = const Color(0xFFFDE68A);
      label = 'SEARCHING FOR SATELLITES';
      icon = Icons.radar;
    } else if (isDenied) {
      bg = const Color(0xFF7F1D1D);
      text = const Color(0xFFFCA5A5);
      label = 'GNSS DENIED (TUNNEL)';
      icon = Icons.gps_off;
    } else if (isDegraded) {
      bg = const Color(0xFF78350F);
      text = const Color(0xFFFDE68A);
      label = 'GNSS DEGRADED';
      icon = Icons.gps_not_fixed;
    } else {
      bg = const Color(0xFF064E3B);
      text = const Color(0xFFA7F3D0);
      label = solution.accuracyMeters != null
          ? 'GNSS LOCKED (±${solution.accuracyMeters!.toStringAsFixed(1)}m)'
          : 'GNSS NOMINAL';
      icon = Icons.gps_fixed;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: text.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: text),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.rajdhani(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: text,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniMetric(String title, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.rajdhani(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  String _getCardinal(double deg) {
    final normalized = (deg % 360 + 360) % 360;
    if (normalized >= 337.5 || normalized < 22.5) return 'N';
    if (normalized >= 22.5 && normalized < 67.5) return 'NE';
    if (normalized >= 67.5 && normalized < 112.5) return 'E';
    if (normalized >= 112.5 && normalized < 157.5) return 'SE';
    if (normalized >= 157.5 && normalized < 202.5) return 'S';
    if (normalized >= 202.5 && normalized < 247.5) return 'SW';
    if (normalized >= 247.5 && normalized < 292.5) return 'W';
    return 'NW';
  }
}
