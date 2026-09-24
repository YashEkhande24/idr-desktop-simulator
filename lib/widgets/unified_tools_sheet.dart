import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/idr_pipeline.dart';
import '../services/sensor_service.dart';
import '../widgets/oscilloscope_widget.dart';
import '../widgets/telemetry_hud.dart';
import '../widgets/offline_map_sheet.dart';
import '../screens/calibration_screen.dart';
import '../screens/comparison_screen.dart';

/// Unified Tools Sheet — Single tabbed bottom sheet replacing:
/// - Old `control_panel.dart` (Start/Pause, Tunnel, Pothole, Force Modes)
/// - Old `sensor_settings_sheet.dart` (Shock Gate, Locomotion Mode, ZUPT)
/// - CockpitScreen's TelemetryHud and Oscilloscope access
///
/// Three tabs: Controls · Tuning · Diagnostics
class UnifiedToolsSheet extends StatefulWidget {
  const UnifiedToolsSheet({super.key});

  @override
  State<UnifiedToolsSheet> createState() => _UnifiedToolsSheetState();
}

class _UnifiedToolsSheetState extends State<UnifiedToolsSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.80,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF0B132B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: Color(0xFF1E293B), width: 1.5),
        ),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Grab handle
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFF475569),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),

              // Tab Bar
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF1E293B)),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.5)),
                  ),
                  dividerColor: Colors.transparent,
                  labelColor: Colors.white,
                  unselectedLabelColor: const Color(0xFF64748B),
                  labelStyle: GoogleFonts.rajdhani(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                  unselectedLabelStyle: GoogleFonts.rajdhani(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                  tabs: const [
                    Tab(
                      icon: Icon(Icons.play_circle_outline, size: 18),
                      text: 'CONTROLS',
                      height: 52,
                    ),
                    Tab(
                      icon: Icon(Icons.tune, size: 18),
                      text: 'TUNING',
                      height: 52,
                    ),
                    Tab(
                      icon: Icon(Icons.insights, size: 18),
                      text: 'DIAGNOSTICS',
                      height: 52,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Tab Content
              Flexible(
                child: TabBarView(
                  controller: _tabController,
                  children: const [
                    _ControlsTab(),
                    _TuningTab(),
                    _DiagnosticsTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// TAB 1: CONTROLS
// ═══════════════════════════════════════════════════════════════
class _ControlsTab extends StatelessWidget {
  const _ControlsTab();

  @override
  Widget build(BuildContext context) {
    final pipeline = context.watch<IdrPipeline>();
    final isRunning = pipeline.isRunning;
    final isTunnel = pipeline.forceTunnelOutage;
    final isPothole = pipeline.forcePotholes;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // GPS Alert Banner
          if (pipeline.gpsHardwareStatus == GpsHardwareStatus.serviceDisabled)
            _buildGpsAlert(
              icon: Icons.location_off,
              text: 'Device Location (GPS) is turned OFF',
              buttonText: 'TURN ON GPS',
              onTap: () => pipeline.openLocationSettings(),
            )
          else if (pipeline.gpsHardwareStatus ==
                  GpsHardwareStatus.permissionDenied ||
              pipeline.gpsHardwareStatus ==
                  GpsHardwareStatus.permissionDeniedForever)
            _buildGpsAlert(
              icon: Icons.security,
              text: 'Location permission is required',
              buttonText: 'GRANT ACCESS',
              onTap: () => pipeline.openAppSettings(),
            ),

          const SizedBox(height: 12),

          // Start / Pause / Reset Row
          Row(
            children: [
              Expanded(
                flex: 5,
                child: _buildActionButton(
                  icon: isRunning ? Icons.pause : Icons.play_arrow,
                  label: isRunning ? 'PAUSE TRACKING' : 'START IDR',
                  color: isRunning
                      ? const Color(0xFF0284C7)
                      : const Color(0xFF059669),
                  onTap: () {
                    if (isRunning) {
                      pipeline.pause();
                    } else {
                      pipeline.start();
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              _buildSquareButton(
                icon: Icons.refresh,
                tooltip: 'Reset Pipeline',
                onTap: () => pipeline.reset(),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Tunnel + Pothole Row
          Row(
            children: [
              Expanded(
                child: _buildToggleCard(
                  icon: Icons.subway,
                  title: isTunnel ? 'TUNNEL ACTIVE' : 'SIMULATE TUNNEL',
                  subtitle:
                      isTunnel ? 'GNSS denied — DR mode' : 'Force GNSS outage',
                  isActive: isTunnel,
                  activeColor: const Color(0xFFEF4444),
                  onTap: () => pipeline.toggleTunnelOutage(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildToggleCard(
                  icon: Icons.vibration,
                  title: isPothole ? 'SHOCK ACTIVE' : 'INJECT POTHOLE',
                  subtitle: isPothole
                      ? 'Road disturbance on'
                      : 'Simulate road shock',
                  isActive: isPothole,
                  activeColor: Colors.amberAccent,
                  onTap: () => pipeline.togglePotholes(),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Offline Maps Section
          _buildSectionLabel('OFFLINE MAPS & ROAD DATA'),
          const SizedBox(height: 8),
          InkWell(
            onTap: () {
              Navigator.of(context).pop(); // close tools sheet first
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const OfflineMapSheet(),
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1E293B)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color:
                          const Color(0xFF38BDF8).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.layers_outlined,
                        color: Color(0xFF38BDF8), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Manage Offline Maps',
                          style: GoogleFonts.rajdhani(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'Download minor roads, view cached tiles',
                          style: GoogleFonts.rajdhani(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right,
                      color: Color(0xFF64748B), size: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGpsAlert({
    required IconData icon,
    required String text,
    required String buttonText,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF991B1B),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.rajdhani(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF991B1B),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: Size.zero,
            ),
            child: Text(
              buttonText,
              style: GoogleFonts.rajdhani(
                  fontSize: 10, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.rajdhani(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSquareButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: Icon(icon, color: const Color(0xFF94A3B8), size: 20),
        ),
      ),
    );
  }

  Widget _buildToggleCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isActive,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isActive
              ? activeColor.withValues(alpha: 0.15)
              : const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive
                ? activeColor
                : const Color(0xFF1E293B),
            width: isActive ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          children: [
            Icon(icon,
                color: isActive ? activeColor : const Color(0xFF64748B),
                size: 22),
            const SizedBox(height: 6),
            Text(
              title,
              style: GoogleFonts.rajdhani(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: isActive ? Colors.white : const Color(0xFF94A3B8),
              ),
            ),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.rajdhani(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: isActive ? activeColor : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Row(
      children: [
        Container(width: 3, height: 14, color: const Color(0xFF38BDF8)),
        const SizedBox(width: 8),
        Text(
          text,
          style: GoogleFonts.rajdhani(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: const Color(0xFF94A3B8),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// TAB 2: TUNING
// ═══════════════════════════════════════════════════════════════
class _TuningTab extends StatelessWidget {
  const _TuningTab();

  @override
  Widget build(BuildContext context) {
    final pipeline = context.watch<IdrPipeline>();
    final solution = pipeline.latestSolution;
    final currentThreshold = pipeline.shockThreshold;
    final isShock = solution?.shockDetected ?? false;
    final currentVariance = solution?.jerkVariance ?? 0.0;
    final isStationary = solution?.idrState.velocity.norm == 0.0;

    String activeMode;
    if (pipeline.forcePedestrian) {
      activeMode = 'PEDESTRIAN';
    } else if (pipeline.forceVehicle) {
      activeMode = 'VEHICLE';
    } else {
      activeMode = 'AUTO';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── SHOCK GATE ──
          _buildSectionHeader(
            icon: Icons.vibration,
            title: 'VIBRATION SHOCK GATE',
            trailing: isShock
                ? _buildBadge('SHOCK TRIP', const Color(0xFFEF4444))
                : _buildBadge('ARMED', const Color(0xFF10B981)),
          ),
          const SizedBox(height: 10),

          // Telemetry row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color:
                    isShock ? const Color(0xFFEF4444) : const Color(0xFF1E293B),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildMetric(
                    'JERK VAR',
                    currentVariance.toStringAsFixed(1),
                    currentVariance > currentThreshold
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF10B981)),
                _buildMetric('THRESHOLD', currentThreshold.toStringAsFixed(0),
                    const Color(0xFF38BDF8)),
                _buildMetric('ROAD', solution?.roadCondition ?? 'NORMAL',
                    isShock ? const Color(0xFFEF4444) : Colors.white),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Slider
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFF38BDF8),
              inactiveTrackColor: const Color(0xFF1E293B),
              thumbColor: const Color(0xFF38BDF8),
              overlayColor:
                  const Color(0xFF38BDF8).withValues(alpha: 0.2),
              trackHeight: 4,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: currentThreshold.clamp(50.0, 1500.0),
              min: 50.0,
              max: 1500.0,
              divisions: 58,
              onChanged: (val) => pipeline.setShockThreshold(val),
            ),
          ),

          // Presets
          Row(
            children: [
              _presetChip('Sensitive', 120.0, currentThreshold,
                  () => pipeline.setShockThreshold(120.0)),
              const SizedBox(width: 6),
              _presetChip('Balanced', 450.0, currentThreshold,
                  () => pipeline.setShockThreshold(450.0),
                  recommended: true),
              const SizedBox(width: 6),
              _presetChip('Rough', 800.0, currentThreshold,
                  () => pipeline.setShockThreshold(800.0)),
            ],
          ),

          const SizedBox(height: 20),

          // ── LOCOMOTION MODE ──
          _buildSectionHeader(
            icon: Icons.transfer_within_a_station,
            title: 'LOCOMOTION MODE',
            trailing: _buildBadge(activeMode, _modeColor(activeMode)),
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: _buildModeCard(
                  title: 'AUTO',
                  subtitle: 'AI Classifier',
                  icon: Icons.auto_awesome,
                  isSelected: activeMode == 'AUTO',
                  activeColor: const Color(0xFF38BDF8),
                  onTap: () => pipeline.setModeAuto(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildModeCard(
                  title: 'PEDESTRIAN',
                  subtitle: '<1.4 m/s',
                  icon: Icons.directions_walk,
                  isSelected: activeMode == 'PEDESTRIAN',
                  activeColor: const Color(0xFF2DD4BF),
                  onTap: () => pipeline.toggleForcePedestrian(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildModeCard(
                  title: 'VEHICLE',
                  subtitle: 'Drive + NHC',
                  icon: Icons.directions_car,
                  isSelected: activeMode == 'VEHICLE',
                  activeColor: const Color(0xFF818CF8),
                  onTap: () => pipeline.toggleForceVehicle(),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ── ZUPT & CALIBRATION ──
          _buildSectionHeader(
            icon: Icons.pan_tool_alt_outlined,
            title: 'ZUPT & CALIBRATION',
            trailing: isStationary
                ? _buildBadge('STANDSTILL', Colors.amberAccent)
                : _buildBadge('MOVING', const Color(0xFF10B981)),
          ),
          const SizedBox(height: 10),

          // ZUPT Release + Drift Reset
          Row(
            children: [
              Expanded(
                child: _buildActionCard(
                  title: 'Release ZUPT Lock',
                  subtitle: 'Free INS propagation',
                  buttonText: 'RELEASE',
                  buttonColor: const Color(0xFF38BDF8),
                  onTap: () {
                    pipeline.releaseStandstillLock();
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Standstill lock released'),
                        duration: Duration(seconds: 2),
                        backgroundColor: Color(0xFF0F172A),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionCard(
                  title: 'Reset Drift Counter',
                  subtitle: 'Re-zero position',
                  buttonText: 'RESET',
                  buttonColor: const Color(0xFF10B981),
                  onTap: () {
                    pipeline.resetDrift();
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Drift counter reset to 0.00 m'),
                        duration: Duration(seconds: 2),
                        backgroundColor: Color(0xFF064E3B),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Calibration shortcut
          InkWell(
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CalibrationScreen()),
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1E293B)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      pipeline.isCabinLocked
                          ? Icons.verified
                          : Icons.compass_calibration_outlined,
                      color: pipeline.isCabinLocked
                          ? const Color(0xFF10B981)
                          : const Color(0xFF94A3B8),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cabin Mount Calibration',
                          style: GoogleFonts.rajdhani(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          pipeline.isCabinLocked
                              ? 'Gravity vector locked ✓'
                              : 'Align IMU to dashboard mount',
                          style: GoogleFonts.rajdhani(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right,
                      color: Color(0xFF64748B), size: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required Widget trailing,
  }) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF38BDF8), size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.rajdhani(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: const Color(0xFF94A3B8),
            ),
          ),
        ),
        trailing,
      ],
    );
  }

  Widget _buildMetric(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.rajdhani(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF64748B))),
        const SizedBox(height: 2),
        Text(value,
            style: GoogleFonts.rajdhani(
                fontSize: 14, fontWeight: FontWeight.w800, color: color)),
      ],
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: GoogleFonts.rajdhani(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
          color: color,
        ),
      ),
    );
  }

  Color _modeColor(String mode) {
    switch (mode) {
      case 'PEDESTRIAN':
        return const Color(0xFF2DD4BF);
      case 'VEHICLE':
        return const Color(0xFF818CF8);
      default:
        return const Color(0xFF38BDF8);
    }
  }

  Widget _presetChip(
      String label, double target, double current, VoidCallback onTap,
      {bool recommended = false}) {
    final isSelected = (current - target).abs() < 15.0;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF38BDF8).withValues(alpha: 0.2)
                : const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF38BDF8)
                  : const Color(0xFF1E293B),
            ),
          ),
          child: Column(
            children: [
              Text(label,
                  style: GoogleFonts.rajdhani(
                      fontSize: 11,
                      fontWeight:
                          isSelected ? FontWeight.w800 : FontWeight.w700,
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFF94A3B8))),
              if (recommended)
                Text('REC',
                    style: GoogleFonts.rajdhani(
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF38BDF8))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.15)
              : const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? activeColor : const Color(0xFF1E293B),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          children: [
            Icon(icon,
                color: isSelected ? activeColor : const Color(0xFF64748B),
                size: 20),
            const SizedBox(height: 6),
            Text(title,
                style: GoogleFonts.rajdhani(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color:
                        isSelected ? Colors.white : const Color(0xFF94A3B8))),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.rajdhani(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color:
                        isSelected ? activeColor : const Color(0xFF64748B))),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required String title,
    required String subtitle,
    required String buttonText,
    required Color buttonColor,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: GoogleFonts.rajdhani(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
          Text(subtitle,
              style: GoogleFonts.rajdhani(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF94A3B8))),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: buttonColor),
                padding: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(buttonText,
                  style: GoogleFonts.rajdhani(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: buttonColor)),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// TAB 3: DIAGNOSTICS
// ═══════════════════════════════════════════════════════════════
class _DiagnosticsTab extends StatelessWidget {
  const _DiagnosticsTab();

  @override
  Widget build(BuildContext context) {
    final pipeline = context.watch<IdrPipeline>();
    final solution = pipeline.latestSolution;

    if (solution == null) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF38BDF8)));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Compact Telemetry HUD
          TelemetryHud(solution: solution),

          const SizedBox(height: 12),

          // Live Oscilloscope
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color:
                      const Color(0xFF38BDF8).withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LIVE SENSOR OSCILLOSCOPE',
                  style: GoogleFonts.rajdhani(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: const Color(0xFF38BDF8),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 120,
                  child: OscilloscopeWidget(solution: solution),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Judge Comparison View launcher
          InkWell(
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ComparisonScreen()),
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color:
                          const Color(0xFFF59E0B).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.compare_arrows_rounded,
                        color: Color(0xFFF59E0B), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SIH Judge Comparison View',
                          style: GoogleFonts.rajdhani(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'Side-by-side Classical DR vs AI IDR',
                          style: GoogleFonts.rajdhani(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right,
                      color: Color(0xFFF59E0B), size: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
