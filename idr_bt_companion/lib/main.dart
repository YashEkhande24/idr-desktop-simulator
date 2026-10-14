import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const IdrCompanionApp());
}

class IdrCompanionApp extends StatelessWidget {
  const IdrCompanionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IDR Ghost Beacon',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF030712),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF38BDF8),
          secondary: Color(0xFF10B981),
          surface: Color(0xFF0F172A),
        ),
      ),
      home: const BeaconHomeScreen(),
    );
  }
}

class BeaconHomeScreen extends StatefulWidget {
  const BeaconHomeScreen({super.key});

  @override
  State<BeaconHomeScreen> createState() => _BeaconHomeScreenState();
}

class _BeaconHomeScreenState extends State<BeaconHomeScreen> with SingleTickerProviderStateMixin {
  static const int broadcastPort = 8989;

  bool _isBroadcasting = false;
  double _broadcastHz = 5.0; // 1, 5, or 10 Hz
  final String _deviceName = 'IDR-Ghost-Phone2';

  // Live GPS Telemetry
  Position? _currentPosition;
  String _gpsStatus = 'Acquiring GPS fix...';
  bool _hasLocationPermission = false;
  StreamSubscription<Position>? _positionStreamSub;

  // Broadcast Stats
  int _packetsSent = 0;
  int _sequenceNumber = 0;
  DateTime? _lastPacketSentTime;
  RawDatagramSocket? _broadcastSocket;
  Timer? _broadcastTimer;

  // Radar pulse animation
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeOut,
    );

    _initGps();
    _initSocket();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _broadcastTimer?.cancel();
    _broadcastSocket?.close();
    _positionStreamSub?.cancel();
    super.dispose();
  }

  Future<void> _initSocket() async {
    try {
      _broadcastSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _broadcastSocket?.broadcastEnabled = true;
    } catch (e) {
      debugPrint('[GhostBeacon] Socket bind error: $e');
    }
  }

  Future<void> _initGps() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _gpsStatus = 'Location Services Disabled on Phone';
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _gpsStatus = 'Location Permission Denied';
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _gpsStatus = 'Location Permission Permanently Denied';
        });
        return;
      }

      setState(() {
        _hasLocationPermission = true;
        _gpsStatus = 'GPS Active (High Precision)';
      });

      // Fetch immediate fix
      final initialPos = await Geolocator.getLastKnownPosition();
      if (initialPos != null) {
        setState(() {
          _currentPosition = initialPos;
        });
      }

      // Stream live GPS updates
      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      );

      _positionStreamSub = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen((pos) {
        setState(() {
          _currentPosition = pos;
          _gpsStatus = 'Locked (±${pos.accuracy.toStringAsFixed(1)}m)';
        });
      });

      // Auto-start broadcasting once fix acquired
      _startBroadcasting();
    } catch (e) {
      setState(() {
        _gpsStatus = 'GPS Error: $e';
      });
    }
  }

  void _startBroadcasting() {
    _broadcastTimer?.cancel();
    final intervalMs = (1000.0 / _broadcastHz).round();

    _broadcastTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      _sendGpsPacket();
    });

    setState(() {
      _isBroadcasting = true;
    });
  }

  void _stopBroadcasting() {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    setState(() {
      _isBroadcasting = false;
    });
  }

  void _sendGpsPacket() {
    if (_currentPosition == null) return;
    final pos = _currentPosition!;

    _sequenceNumber++;
    final packet = {
      'magic': 'IDR_GHOST_GPS',
      'ver': 1,
      'seq': _sequenceNumber,
      'lat': pos.latitude,
      'lng': pos.longitude,
      'alt': pos.altitude,
      'speed_mps': pos.speed,
      'heading_deg': pos.heading,
      'accuracy': pos.accuracy,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'sender': _deviceName,
    };

    final jsonBytes = utf8.encode(jsonEncode(packet));

    try {
      _broadcastSocket?.send(
        jsonBytes,
        InternetAddress('255.255.255.255'),
        broadcastPort,
      );

      setState(() {
        _packetsSent++;
        _lastPacketSentTime = DateTime.now();
      });
    } catch (e) {
      debugPrint('[GhostBeacon] Send packet error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pos = _currentPosition;
    final speedKmh = pos != null ? pos.speed * 3.6 : 0.0;
    final heading = pos != null ? pos.heading : 0.0;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
              ),
              child: const Icon(Icons.radar_rounded, color: Color(0xFF10B981), size: 18),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'IDR GHOST BEACON',
                  style: GoogleFonts.rajdhani(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Phone 2 Satellite Transmitter',
                  style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF94A3B8)),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF94A3B8)),
            tooltip: 'Refresh GPS',
            onPressed: _initGps,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Radar Pulse Beacon Card
              _buildRadarCard(),

              const SizedBox(height: 16),

              // 2. Live GPS Telemetry Dashboard
              _buildTelemetryGrid(pos, speedKmh, heading),

              const SizedBox(height: 16),

              // 3. Transmission Controls & Frequency Selector
              _buildTransmissionControls(),

              const SizedBox(height: 16),

              // 4. Manual Ping & Diagnostics
              _buildDiagnosticCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRadarCard() {
    final statusColor = _isBroadcasting && _currentPosition != null
        ? const Color(0xFF10B981) // Emerald
        : const Color(0xFFF59E0B); // Amber

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1E293B), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Animated Pulse Beacon
          Stack(
            alignment: Alignment.center,
            children: [
              // Outer radar pulse
              if (_isBroadcasting)
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Container(
                      width: 90 + _pulseAnimation.value * 50,
                      height: 90 + _pulseAnimation.value * 50,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: statusColor.withValues(alpha: (1.0 - _pulseAnimation.value) * 0.25),
                        border: Border.all(
                          color: statusColor.withValues(alpha: (1.0 - _pulseAnimation.value) * 0.6),
                          width: 1.5,
                        ),
                      ),
                    );
                  },
                ),
              // Inner glowing core
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF1E293B),
                  border: Border.all(color: statusColor, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: statusColor.withValues(alpha: 0.3),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  _isBroadcasting ? Icons.bluetooth_audio_rounded : Icons.bluetooth_disabled_rounded,
                  color: statusColor,
                  size: 34,
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          Text(
            _isBroadcasting ? 'BROADCASTING LIVE SATELLITE FIX' : 'BEACON TRANSMITTER PAUSED',
            style: GoogleFonts.rajdhani(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: statusColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Target: UDP Port $broadcastPort (Wi-Fi / Hotspot / BT PAN)',
            style: GoogleFonts.firaCode(fontSize: 11, color: const Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _gpsStatus,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _hasLocationPermission ? const Color(0xFF10B981) : const Color(0xFFEF4444),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryGrid(Position? pos, double speedKmh, double heading) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'HARDWARE SATELLITE FIX',
            style: GoogleFonts.rajdhani(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: const Color(0xFF94A3B8),
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                'LATITUDE',
                pos != null ? pos.latitude.toStringAsFixed(6) : '--.------',
                Icons.north_rounded,
                const Color(0xFF38BDF8),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricTile(
                'LONGITUDE',
                pos != null ? pos.longitude.toStringAsFixed(6) : '--.------',
                Icons.east_rounded,
                const Color(0xFF38BDF8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                'SPEED',
                '${speedKmh.toStringAsFixed(1)} km/h',
                Icons.speed_rounded,
                const Color(0xFF10B981),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricTile(
                'HEADING',
                '${heading.toStringAsFixed(1)}° (${_getCardinal(heading)})',
                Icons.explore_rounded,
                const Color(0xFFF59E0B),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                'ALTITUDE',
                pos != null ? '${pos.altitude.toStringAsFixed(1)} m' : '--.- m',
                Icons.terrain_rounded,
                const Color(0xFFA855F7),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricTile(
                'ACCURACY',
                pos != null ? '±${pos.accuracy.toStringAsFixed(1)} m' : '--.- m',
                Icons.gps_fixed_rounded,
                const Color(0xFF06B6D4),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricTile(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.rajdhani(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: const Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.firaCode(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransmissionControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TRANSMISSION RATE',
            style: GoogleFonts.rajdhani(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: const Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildHzChip(1.0, '1 Hz (Power Save)'),
              const SizedBox(width: 8),
              _buildHzChip(5.0, '5 Hz (Standard)'),
              const SizedBox(width: 8),
              _buildHzChip(10.0, '10 Hz (Hi-Rate)'),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isBroadcasting ? const Color(0xFFDC2626) : const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: Icon(_isBroadcasting ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  label: Text(
                    _isBroadcasting ? 'PAUSE TRANSMISSION' : 'RESUME TRANSMISSION',
                    style: GoogleFonts.rajdhani(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  onPressed: () {
                    if (_isBroadcasting) {
                      _stopBroadcasting();
                    } else {
                      _startBroadcasting();
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHzChip(double hz, String label) {
    final isSelected = _broadcastHz == hz;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _broadcastHz = hz;
          });
          if (_isBroadcasting) _startBroadcasting();
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF38BDF8).withValues(alpha: 0.15) : const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF334155),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Center(
            child: Text(
              '${hz.toInt()} Hz',
              style: GoogleFonts.rajdhani(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isSelected ? const Color(0xFF38BDF8) : Colors.white70,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDiagnosticCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'STREAM TELEMETRY',
                style: GoogleFonts.rajdhani(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: const Color(0xFF94A3B8),
                ),
              ),
              Text(
                'Seq #$_sequenceNumber',
                style: GoogleFonts.firaCode(fontSize: 11, color: const Color(0xFF64748B)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Packets Broadcasted:', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8))),
              Text('$_packetsSent packets', style: GoogleFonts.firaCode(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF10B981))),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Sender ID:', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8))),
              Text(_deviceName, style: GoogleFonts.firaCode(fontSize: 12, color: Colors.white)),
            ],
          ),
          if (_lastPacketSentTime != null) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Last Packet Sent:', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8))),
                Text(
                  '${_lastPacketSentTime!.hour.toString().padLeft(2, '0')}:${_lastPacketSentTime!.minute.toString().padLeft(2, '0')}:${_lastPacketSentTime!.second.toString().padLeft(2, '0')}.${(_lastPacketSentTime!.millisecond ~/ 100)}',
                  style: GoogleFonts.firaCode(fontSize: 12, color: const Color(0xFF38BDF8)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF38BDF8),
              side: const BorderSide(color: Color(0xFF38BDF8)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
            icon: const Icon(Icons.flash_on_rounded, size: 16),
            label: Text(
              'TRANSMIT IMMEDIATE BURST PING (x5)',
              style: GoogleFonts.rajdhani(fontWeight: FontWeight.w700),
            ),
            onPressed: () {
              for (int i = 0; i < 5; i++) {
                _sendGpsPacket();
              }
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Transmitted 5 burst packets on UDP 8989'),
                  duration: Duration(milliseconds: 1200),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  String _getCardinal(double heading) {
    const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final idx = ((heading + 22.5) % 360) ~/ 45;
    return directions[idx];
  }
}
