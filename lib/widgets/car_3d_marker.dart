import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Photorealistic 3D Vehicle Navigation Avatar matching Google Maps styling.
/// Renders the studio-rendered 3D red car with ambient ground shadow,
/// true compass/course-up rotation, and smooth orientation.
class Car3DMarker extends StatelessWidget {
  final double headingDeg;
  final double pitchDeg;
  final double rollDeg;
  final double cameraElevationDeg;
  final double size;
  final bool isCourseUp;

  const Car3DMarker({
    super.key,
    required this.headingDeg,
    this.pitchDeg = 0.0,
    this.rollDeg = 0.0,
    this.cameraElevationDeg = 56.0,
    this.size = 72.0,
    this.isCourseUp = false,
  });

  @override
  Widget build(BuildContext context) {
    // In Course-Up mode, the map rotates to align with heading, so the 3D car points forward (0°).
    // In North-Up mode, the 3D car rotates to reflect true compass heading.
    final effectiveYawDeg = isCourseUp ? 0.0 : headingDeg;
    final rad = effectiveYawDeg * (math.pi / 180.0);

    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Transform.rotate(
          angle: rad,
          child: Image.asset(
            'assets/images/nav_car_3d.png',
            width: size,
            height: size,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
      ),
    );
  }
}
