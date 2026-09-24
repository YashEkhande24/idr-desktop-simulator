import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/nav_solution.dart';

enum ScopeChannel {
  jerk,
  speed,
  altitude,
}

/// Real-Time Telemetry Oscilloscope.
///
/// Visualizes:
/// - Channel 1: Raw Jerk vs Gated Jerk Variance (Shock/Pothole Detection)
/// - Channel 2: TCN Estimated Speed vs EKF Forward Speed (km/h)
/// - Channel 3: Barometric Elevation (m) for Flyover / Underpass tracking
class OscilloscopeWidget extends StatefulWidget {
  final NavSolution solution;

  const OscilloscopeWidget({
    super.key,
    required this.solution,
  });

  @override
  State<OscilloscopeWidget> createState() => _OscilloscopeWidgetState();
}

class _OscilloscopeWidgetState extends State<OscilloscopeWidget> {
  ScopeChannel _selectedChannel = ScopeChannel.jerk;

  final List<FlSpot> _jerkSpots = [];
  final List<FlSpot> _speedSpots = [];
  final List<FlSpot> _altSpots = [];

  double _t = 0.0;
  static const int maxSpots = 80;

  @override
  void didUpdateWidget(covariant OscilloscopeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _t += 0.05;

    // Push new samples
    _jerkSpots.add(FlSpot(_t, widget.solution.jerkVariance));
    _speedSpots.add(FlSpot(_t, widget.solution.tcnEstimatedSpeed * 3.6));
    _altSpots.add(FlSpot(_t, widget.solution.baroAltitude));

    if (_jerkSpots.length > maxSpots) _jerkSpots.removeAt(0);
    if (_speedSpots.length > maxSpots) _speedSpots.removeAt(0);
    if (_altSpots.length > maxSpots) _altSpots.removeAt(0);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header + Channel Selector Tabs
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Text(
                'OSCILLOSCOPE',
                style: GoogleFonts.rajdhani(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: const Color(0xFF94A3B8),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _channelTab(ScopeChannel.jerk, 'JERK'),
                  const SizedBox(width: 4),
                  _channelTab(ScopeChannel.speed, 'SPEED'),
                  const SizedBox(width: 4),
                  _channelTab(ScopeChannel.altitude, 'ALT'),
                ],
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Graph Area
          SizedBox(
            height: 90,
            child: _buildSelectedChart(),
          ),
        ],
      ),
    );
  }

  Widget _channelTab(ScopeChannel channel, String label) {
    final isSelected = _selectedChannel == channel;
    return InkWell(
      onTap: () => setState(() => _selectedChannel = channel),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1E293B) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF334155),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.rajdhani(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedChart() {
    List<FlSpot> spots;
    Color strokeColor;
    double? thresholdLine;

    switch (_selectedChannel) {
      case ScopeChannel.jerk:
        spots = _jerkSpots;
        strokeColor = widget.solution.shockDetected ? Colors.amberAccent : const Color(0xFF10B981);
        thresholdLine = 35.0; // tau_jerk threshold
        break;
      case ScopeChannel.speed:
        spots = _speedSpots;
        strokeColor = const Color(0xFF38BDF8);
        break;
      case ScopeChannel.altitude:
        spots = _altSpots;
        strokeColor = const Color(0xFFA855F7);
        break;
    }

    if (spots.isEmpty) {
      return Center(
        child: Text(
          'Waiting for sensor telemetry...',
          style: GoogleFonts.rajdhani(fontSize: 12, color: Colors.white38),
        ),
      );
    }

    final minX = spots.first.x;
    final maxX = spots.last.x;

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => const FlLine(
            color: Color(0xFF1E293B),
            strokeWidth: 0.8,
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toStringAsFixed(0),
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    color: const Color(0xFF64748B),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        minX: minX,
        maxX: maxX,
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            if (thresholdLine != null)
              HorizontalLine(
                y: thresholdLine,
                color: Colors.redAccent.withValues(alpha: 0.7),
                strokeWidth: 1.2,
                dashArray: [4, 4],
                label: HorizontalLineLabel(
                  show: true,
                  alignment: Alignment.topRight,
                  style: GoogleFonts.rajdhani(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: Colors.redAccent,
                  ),
                  labelResolver: (line) => 'SHOCK THRESHOLD τ',
                ),
              ),
          ],
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.2,
            color: strokeColor,
            barWidth: 2.0,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: strokeColor.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}
