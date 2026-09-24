import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Google Maps style interactive rotating compass rose.
///
/// - Displays 3D red/silver magnetic needle pointing to True North.
/// - When in Course-Up mode (heading-up), the needle rotates dynamically as the car turns.
/// - Tap toggles between North-Up and Course-Up (vehicle-centric navigation).
class RotatingCompass extends StatelessWidget {
  final double headingDeg;
  final bool isCourseUp;
  final VoidCallback onToggleMode;
  final double size;

  const RotatingCompass({
    super.key,
    required this.headingDeg,
    required this.isCourseUp,
    required this.onToggleMode,
    this.size = 46.0,
  });

  @override
  Widget build(BuildContext context) {
    // In Course-Up mode, True North points at -headingDeg relative to the screen.
    // In North-Up mode, North is always at 12 o'clock (angle 0).
    final needleAngleRad = isCourseUp ? -headingDeg * math.pi / 180.0 : 0.0;

    return GestureDetector(
      onTap: onToggleMode,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(
            color: const Color(0xFFE2E8F0),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Rotating Needle with Smooth Animation
            AnimatedRotation(
              turns: needleAngleRad / (2 * math.pi),
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: CustomPaint(
                size: Size(size * 0.65, size * 0.65),
                painter: _CompassNeedlePainter(),
              ),
            ),

            // North 'N' badge at the top
            Positioned(
              top: 2,
              child: AnimatedRotation(
                turns: needleAngleRad / (2 * math.pi),
                duration: const Duration(milliseconds: 180),
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 22),
                  child: Text(
                    'N',
                    style: GoogleFonts.inter(
                      fontSize: 7.5,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFFEA4335),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompassNeedlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final halfWidth = size.width * 0.16;
    final needleLength = size.height * 0.44;

    // 1. North Needle (Vibrant Red 3D Triangle)
    final northPath = Path()
      ..moveTo(cx, cy - needleLength) // North tip
      ..lineTo(cx + halfWidth, cy) // Right waist
      ..lineTo(cx, cy - 2) // Inner center
      ..close();

    final northPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFDC2626), Color(0xFFEF4444)],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ).createShader(Rect.fromLTWH(cx - halfWidth, cy - needleLength, halfWidth * 2, needleLength))
      ..style = PaintingStyle.fill;

    // North Left Facet (Darker red shadow for 3D bevel)
    final northShadowPath = Path()
      ..moveTo(cx, cy - needleLength)
      ..lineTo(cx - halfWidth, cy)
      ..lineTo(cx, cy - 2)
      ..close();

    final northShadowPaint = Paint()
      ..color = const Color(0xFFB91C1C)
      ..style = PaintingStyle.fill;

    // 2. South Needle (Silver White 3D Triangle)
    final southPath = Path()
      ..moveTo(cx, cy + needleLength) // South tip
      ..lineTo(cx + halfWidth, cy) // Right waist
      ..lineTo(cx, cy + 2)
      ..close();

    final southPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..style = PaintingStyle.fill;

    final southShadowPath = Path()
      ..moveTo(cx, cy + needleLength)
      ..lineTo(cx - halfWidth, cy)
      ..lineTo(cx, cy + 2)
      ..close();

    final southShadowPaint = Paint()
      ..color = const Color(0xFF94A3B8)
      ..style = PaintingStyle.fill;

    // Draw needle halves
    canvas.drawPath(southShadowPath, southShadowPaint);
    canvas.drawPath(southPath, southPaint);
    canvas.drawPath(northShadowPath, northShadowPaint);
    canvas.drawPath(northPath, northPaint);

    // Pivot Center Pin
    final pivotPaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(cx, cy), 3.0, pivotPaint);

    final pivotRingPaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(Offset(cx, cy), 3.0, pivotRingPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
