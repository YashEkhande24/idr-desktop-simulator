import 'package:flutter/material.dart';
import '../services/idr_pipeline.dart';
import 'car_3d_marker.dart';

/// Interactive Supercar Garage Modal for customizing the 3D vehicle avatar colorway.
class VehicleGarageSheet extends StatefulWidget {
  final IdrPipeline pipeline;

  const VehicleGarageSheet({super.key, required this.pipeline});

  @override
  State<VehicleGarageSheet> createState() => _VehicleGarageSheetState();
}

class _VehicleGarageSheetState extends State<VehicleGarageSheet>
    with SingleTickerProviderStateMixin {
  late VehicleColorway _selectedColorway;
  late AnimationController _rotationAnimController;
  double _manualAngleDeg = 25.0;
  bool _isInteracting = false;

  @override
  void initState() {
    super.initState();
    _selectedColorway = widget.pipeline.vehicleColorway;
    _rotationAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
  }

  @override
  void dispose() {
    _rotationAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: Color(0xFF334155), width: 1.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 30,
            spreadRadius: 5,
            offset: Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Drag Handle
              Center(
                child: Container(
                  width: 44,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: const Color(0xFF475569),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // 2. Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _selectedColorway.accentColor.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _selectedColorway.accentColor.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Icon(
                          Icons.palette_rounded,
                          color: _selectedColorway.accentColor,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Supercar Garage',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                          ),
                          Text(
                            'Choose your 3D navigation avatar',
                            style: TextStyle(
                              color: const Color(0xFF94A3B8),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFF94A3B8)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 3. 360° Interactive Showroom Stage
              GestureDetector(
                onPanStart: (_) {
                  setState(() {
                    _isInteracting = true;
                  });
                },
                onPanUpdate: (details) {
                  setState(() {
                    _manualAngleDeg = (_manualAngleDeg + details.delta.dx * 0.9) % 360.0;
                  });
                },
                onPanEnd: (_) {
                  setState(() {
                    _isInteracting = false;
                  });
                },
                child: AnimatedBuilder(
                  animation: _rotationAnimController,
                  builder: (context, child) {
                    final displayAngle = _isInteracting
                        ? _manualAngleDeg
                        : (_rotationAnimController.value * 360.0 + _manualAngleDeg) % 360.0;

                    return Container(
                      width: double.infinity,
                      height: 180,
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment.center,
                          radius: 0.75,
                          colors: [
                            _selectedColorway.accentColor.withValues(alpha: 0.12),
                            const Color(0xFF090D16),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _selectedColorway.accentColor.withValues(alpha: 0.25),
                          width: 1.2,
                        ),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Radial Showroom Pedestal Rings
                          Positioned(
                            bottom: 24,
                            child: Container(
                              width: 160,
                              height: 48,
                              decoration: BoxDecoration(
                                shape: BoxShape.rectangle,
                                borderRadius: BorderRadius.all(Radius.elliptical(160, 48)),
                                border: Border.all(
                                  color: _selectedColorway.accentColor.withValues(alpha: 0.35),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: _selectedColorway.accentColor.withValues(alpha: 0.18),
                                    blurRadius: 18,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // 3D Car Marker
                          Car3DMarker(
                            headingDeg: displayAngle,
                            size: 130.0,
                            colorway: _selectedColorway,
                            showHeadlightBeam: true,
                          ),

                          // Touch Hint
                          Positioned(
                            bottom: 8,
                            child: Row(
                              children: [
                                Icon(
                                  Icons.touch_app_outlined,
                                  color: const Color(0xFF64748B),
                                  size: 13,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Swipe horizontally to spin 360°',
                                  style: TextStyle(
                                    color: const Color(0xFF64748B),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Angle Indicator Badge
                          Positioned(
                            top: 10,
                            right: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF334155)),
                              ),
                              child: Text(
                                '${displayAngle.round()}°',
                                style: const TextStyle(
                                  color: Color(0xFFCBD5E1),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 18),

              // 4. Colorway Selection List
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'COLORWAYS',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // 5 Colorway Cards
              SizedBox(
                height: 82,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: VehicleColorway.values.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final colorway = VehicleColorway.values[index];
                    final isSelected = colorway == _selectedColorway;

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedColorway = colorway;
                        });
                        widget.pipeline.setVehicleColorway(colorway);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        width: 124,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? colorway.accentColor.withValues(alpha: 0.16)
                              : const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected
                                ? colorway.accentColor
                                : const Color(0xFF334155),
                            width: isSelected ? 2.0 : 1.0,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: colorway.accentColor.withValues(alpha: 0.3),
                                    blurRadius: 12,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: colorway.accentColor,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.8),
                                      width: 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: colorway.accentColor.withValues(alpha: 0.6),
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                ),
                                const Spacer(),
                                if (isSelected)
                                  Icon(
                                    Icons.check_circle_rounded,
                                    color: colorway.accentColor,
                                    size: 16,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              colorway.label,
                              style: TextStyle(
                                color: isSelected ? Colors.white : const Color(0xFFE2E8F0),
                                fontSize: 12.5,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              colorway.description,
                              style: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 9.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 18),

              // 5. Confirm / Apply Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () {
                    widget.pipeline.setVehicleColorway(_selectedColorway);
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            Icon(Icons.directions_car, color: _selectedColorway.accentColor),
                            const SizedBox(width: 10),
                            Text(
                              'Avatar updated to ${_selectedColorway.label}!',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        backgroundColor: const Color(0xFF0F172A),
                        duration: const Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    );
                  },
                  icon: const Icon(Icons.check, size: 20),
                  label: Text('Apply ${_selectedColorway.label}'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _selectedColorway.accentColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 3,
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
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
}
