import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/idr_pipeline.dart';

/// Interactive Cabin Mount Calibration Wizard.
///
/// Features:
/// - Visual 2D Bubble Level / Artificial Horizon
/// - Live Mount Pitch and Roll readout (degrees)
/// - Step-by-step guidance for dashboard cradle mounting
/// - Instant Gravity Calibration Lock
class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key});

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  bool _isCalibrating = false;

  void _triggerCalibration(IdrPipeline pipeline) {
    setState(() => _isCalibrating = true);
    Future.delayed(const Duration(milliseconds: 1500), () {
      pipeline.forceCalibrateCabin();
      if (mounted) {
        setState(() => _isCalibrating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF059669),
            content: Text('Cabin alignment locked successfully!'),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pipeline = context.watch<IdrPipeline>();
    final sol = pipeline.latestSolution;
    final pitch = sol?.mountPitchDeg ?? 0.0;
    final roll = sol?.mountRollDeg ?? 0.0;
    final isLocked = pipeline.isCabinLocked;
    final confidence = pipeline.cabinConfidence;

    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: Text(
          'CABIN MOUNT CALIBRATION',
          style: GoogleFonts.rajdhani(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              // Instructions Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF1E293B)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Color(0xFF38BDF8), size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Mount your phone securely on the car cradle or dashboard. Keep the vehicle stationary for 2 seconds to align the IMU gravity vector.',
                        style: GoogleFonts.rajdhani(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Artificial Horizon / Bubble Level
              Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF0F172A),
                  border: Border.all(
                    color: isLocked ? const Color(0xFF10B981) : const Color(0xFF38BDF8),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (isLocked ? const Color(0xFF10B981) : const Color(0xFF38BDF8)).withValues(alpha: 0.25),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Crosshair lines
                    Container(width: 1, height: 160, color: const Color(0xFF1E293B)),
                    Container(width: 160, height: 1, color: const Color(0xFF1E293B)),

                    // Bubble
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 100),
                      left: 100 + (roll * 1.5).clamp(-70.0, 70.0) - 15,
                      top: 100 - (pitch * 1.5).clamp(-70.0, 70.0) - 15,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isLocked ? const Color(0xFF10B981) : const Color(0xFF38BDF8),
                          boxShadow: [
                            BoxShadow(
                              color: (isLocked ? const Color(0xFF10B981) : const Color(0xFF38BDF8)).withValues(alpha: 0.8),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Target center ring
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24, width: 1.5),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Angle Readouts
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _angleCard('MOUNT PITCH', '${pitch.toStringAsFixed(1)}°'),
                  const SizedBox(width: 16),
                  _angleCard('MOUNT ROLL', '${roll.toStringAsFixed(1)}°'),
                  const SizedBox(width: 16),
                  _angleCard('CONFIDENCE', '${(confidence * 100).toStringAsFixed(0)}%'),
                ],
              ),

              const Spacer(),

              // Calibration Action Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isCalibrating ? null : () => _triggerCalibration(pipeline),
                  icon: _isCalibrating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.lock_clock),
                  label: Text(
                    _isCalibrating ? 'LOCKING GRAVITY...' : 'LOCK CABIN ALIGNMENT',
                    style: GoogleFonts.rajdhani(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _angleCard(String title, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: GoogleFonts.rajdhani(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.orbitron(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
