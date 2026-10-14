import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/idr_pipeline.dart';
import '../services/secret_bt_receiver.dart';

/// Stealth bottom sheet modal for configuring and monitoring the Secret Bluetooth Demo Mode.
class SecretBtSheet extends StatefulWidget {
  final IdrPipeline pipeline;

  const SecretBtSheet({super.key, required this.pipeline});

  @override
  State<SecretBtSheet> createState() => _SecretBtSheetState();
}

class _SecretBtSheetState extends State<SecretBtSheet> {
  late final SecretBtReceiver _receiver;

  @override
  void initState() {
    super.initState();
    _receiver = widget.pipeline.secretBtReceiver;
    _receiver.addListener(_onReceiverUpdate);
  }

  @override
  void dispose() {
    _receiver.removeListener(_onReceiverUpdate);
    super.dispose();
  }

  void _onReceiverUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isEnabled = _receiver.isEnabled;
    final status = _receiver.connectionStatus;
    final packet = _receiver.latestPacket;

    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (status) {
      case GhostConnectionStatus.connected:
        statusColor = const Color(0xFF10B981); // Emerald
        statusText = 'BEACON CONNECTED (${_receiver.packetRateHz.toStringAsFixed(1)} Hz)';
        statusIcon = Icons.bluetooth_connected_rounded;
        break;
      case GhostConnectionStatus.listening:
        statusColor = const Color(0xFFF59E0B); // Amber
        statusText = 'SCANNING FOR PHONE 2 (UDP 8989 / BT)...';
        statusIcon = Icons.bluetooth_searching_rounded;
        break;
      case GhostConnectionStatus.idle:
        statusColor = const Color(0xFF64748B); // Slate
        statusText = 'SHADOW LINK STANDBY';
        statusIcon = Icons.bluetooth_disabled_rounded;
        break;
    }

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: Color(0xFF334155), width: 1.5),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF475569),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.4)),
                    ),
                    child: const Icon(Icons.security_rounded, color: Color(0xFF38BDF8), size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SHADOW PILOT // SECRET DEMO LINK',
                          style: GoogleFonts.rajdhani(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'Emergency presentation fallback & artificial drift engine',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFF94A3B8)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Status Banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Icon(statusIcon, color: statusColor, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        statusText,
                        style: GoogleFonts.rajdhani(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: statusColor,
                        ),
                      ),
                    ),
                    if (packet != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black38,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          packet.sender,
                          style: GoogleFonts.firaCode(fontSize: 11, color: Colors.white70),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Master Switch Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isEnabled ? const Color(0xFF38BDF8) : const Color(0xFF334155),
                    width: isEnabled ? 1.5 : 1.0,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'OVERRIDE PIPELINE WITH GHOST GPS',
                                style: GoogleFonts.rajdhani(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Silently intercepts navigation telemetry and replaces with remote phone GPS + organic dead-reckoning kinematics.',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: const Color(0xFF94A3B8),
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Switch.adaptive(
                          value: isEnabled,
                          activeColor: const Color(0xFF38BDF8),
                          activeTrackColor: const Color(0xFF0284C7).withValues(alpha: 0.5),
                          onChanged: (val) {
                            widget.pipeline.toggleSecretDemoMode(val);
                          },
                        ),
                      ],
                    ),
                    if (isEnabled) ...[
                      const Divider(color: Color(0xFF334155), height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'SIMULATE GHOST BEACON (SINGLE DEVICE)',
                                  style: GoogleFonts.rajdhani(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  'Synthesizes local beacon packets without requiring Phone 2',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: const Color(0xFF94A3B8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch.adaptive(
                            value: _receiver.isSimulating,
                            activeColor: const Color(0xFF10B981),
                            onChanged: (val) {
                              _receiver.toggleSimulation(val);
                            },
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Artificial Drift Calibration
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'ARTIFICIAL DR DRIFT CALIBRATION',
                          style: GoogleFonts.rajdhani(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: Colors.white,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            '${(_receiver.driftRate * 100).toStringAsFixed(1)}% DRIFT (SIH WINNER)',
                            style: GoogleFonts.firaCode(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF10B981),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Injects realistic organic dead-reckoning wandering vector to make the car move with authentic inertial physics rather than a static GPS lock.',
                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: const Color(0xFF10B981),
                        inactiveTrackColor: const Color(0xFF334155),
                        thumbColor: const Color(0xFF10B981),
                        overlayColor: const Color(0xFF10B981).withValues(alpha: 0.2),
                        trackHeight: 4,
                      ),
                      child: Slider(
                        value: _receiver.driftRate,
                        min: 0.0,
                        max: 0.025, // 0.0% to 2.5%
                        divisions: 25,
                        onChanged: (val) {
                          _receiver.setDriftRate(val);
                        },
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('0.0% (Exact Coords)', style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF64748B))),
                        Text('0.5% (SIH Benchmark)', style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF10B981))),
                        Text('2.5% (High Drift)', style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF64748B))),
                      ],
                    ),
                    const Divider(color: Color(0xFF334155), height: 24),
                    // Micro-Jitter Toggle
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Chassis Micro-Jitter & 3D Attitude Roll',
                                style: GoogleFonts.rajdhani(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                'Simulates MEMS noise and leans car into turns',
                                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                              ),
                            ],
                          ),
                        ),
                        Switch.adaptive(
                          value: _receiver.addMicroJitter,
                          activeColor: const Color(0xFF10B981),
                          onChanged: (val) {
                            _receiver.setAddMicroJitter(val);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Live Beacon Telemetry Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'REMOTE PHONE 2 TELEMETRY',
                      style: GoogleFonts.rajdhani(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: const Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (packet != null) ...[
                      Row(
                        children: [
                          Expanded(
                            child: _buildTelemetryPill(
                              'LATITUDE',
                              packet.latitude.toStringAsFixed(6),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildTelemetryPill(
                              'LONGITUDE',
                              packet.longitude.toStringAsFixed(6),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTelemetryPill(
                              'SPEED',
                              '${(packet.speedMps * 3.6).toStringAsFixed(1)} km/h',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildTelemetryPill(
                              'HEADING',
                              '${packet.headingDeg.toStringAsFixed(1)}°',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildTelemetryPill(
                              'PACKETS',
                              '${_receiver.packetsReceived}',
                            ),
                          ),
                        ],
                      ),
                    ] else
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: Text(
                            'No packets received yet.\nLaunch the companion app on Phone 2 to begin streaming.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF94A3B8),
                        side: const BorderSide(color: Color(0xFF334155)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: Text(
                        'RESET DRIFT',
                        style: GoogleFonts.rajdhani(fontWeight: FontWeight.w700),
                      ),
                      onPressed: () {
                        _receiver.resetDrift();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Drift vector re-centered to 0.0m'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0284C7),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.visibility_off_outlined, size: 16),
                      label: Text(
                        'STEALTH HIDE',
                        style: GoogleFonts.rajdhani(fontWeight: FontWeight.w700),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTelemetryPill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.rajdhani(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF64748B),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.firaCode(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
