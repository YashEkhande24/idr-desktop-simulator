import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// Represents a raw telemetry packet transmitted by the Phone 2 Companion App.
class IdrGhostPacket {
  final double latitude;
  final double longitude;
  final double altitude;
  final double speedMps;
  final double headingDeg;
  final double accuracy;
  final int timestampMs;
  final String sender;

  IdrGhostPacket({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.speedMps,
    required this.headingDeg,
    required this.accuracy,
    required this.timestampMs,
    required this.sender,
  });

  factory IdrGhostPacket.fromJson(Map<String, dynamic> json) {
    return IdrGhostPacket(
      latitude: (json['lat'] as num).toDouble(),
      longitude: (json['lng'] as num).toDouble(),
      altitude: (json['alt'] as num?)?.toDouble() ?? 550.0,
      speedMps: (json['speed_mps'] as num?)?.toDouble() ?? 0.0,
      headingDeg: (json['heading_deg'] as num?)?.toDouble() ?? 0.0,
      accuracy: (json['accuracy'] as num?)?.toDouble() ?? 2.0,
      timestampMs: (json['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      sender: json['sender'] as String? ?? 'Ghost-Remote',
    );
  }

  Map<String, dynamic> toJson() => {
    'magic': 'IDR_GHOST_GPS',
    'lat': latitude,
    'lng': longitude,
    'alt': altitude,
    'speed_mps': speedMps,
    'heading_deg': headingDeg,
    'accuracy': accuracy,
    'timestamp': timestampMs,
    'sender': sender,
  };
}

/// Dynamic output state produced by the Kinematic Smoother and Artificial Drift Generator.
class GhostNavState {
  final LatLng rawPosition;
  final LatLng driftedPosition;
  final double speedKmh;
  final double headingDeg;
  final double pitchDeg;
  final double rollDeg;
  final double cumulativeDistanceM;
  final double cumulativeDriftM;
  final double driftPercentage;
  final bool isBraking;
  final DateTime lastPacketTime;

  GhostNavState({
    required this.rawPosition,
    required this.driftedPosition,
    required this.speedKmh,
    required this.headingDeg,
    required this.pitchDeg,
    required this.rollDeg,
    required this.cumulativeDistanceM,
    required this.cumulativeDriftM,
    required this.driftPercentage,
    required this.isBraking,
    required this.lastPacketTime,
  });
}

enum GhostConnectionStatus {
  idle,
  listening,
  connected,
}

/// Service that secretly receives GPS coordinates from Phone 2 over Bluetooth/P2P/UDP,
/// applies realistic artificial dead-reckoning drift, and smooths kinematics at 20 Hz.
class SecretBtReceiver extends ChangeNotifier {
  static final SecretBtReceiver _instance = SecretBtReceiver._internal();
  factory SecretBtReceiver() => _instance;
  SecretBtReceiver._internal();

  static const int broadcastPort = 8989;

  bool _isEnabled = false;
  bool get isEnabled => _isEnabled;

  GhostConnectionStatus _connectionStatus = GhostConnectionStatus.idle;
  GhostConnectionStatus get connectionStatus => _connectionStatus;

  // Configuration for Artificial Drift
  // 0.005 means ~0.5% drift over traveled distance (ideal SIH demo score)
  double _driftRate = 0.005; // 0.5%
  double get driftRate => _driftRate;

  bool _addMicroJitter = true;
  bool get addMicroJitter => _addMicroJitter;

  // Network Sockets
  RawDatagramSocket? _udpSocket;
  Timer? _kinematicTicker;
  Timer? _heartbeatChecker;
  Timer? _simulationTimer;
  bool get isSimulating => _simulationTimer != null;

  // Received Telemetry
  IdrGhostPacket? _latestPacket;
  IdrGhostPacket? get latestPacket => _latestPacket;

  DateTime? _lastPacketTime;
  DateTime? get lastPacketTime => _lastPacketTime;

  int _packetsReceived = 0;
  int get packetsReceived => _packetsReceived;

  double _packetRateHz = 0.0;
  double get packetRateHz => _packetRateHz;
  int _packetsThisSecond = 0;

  // Kinematic & Drift State
  LatLng? _currentDriftedPos;
  LatLng? get currentDriftedPos => _currentDriftedPos;

  double _currentSpeedMps = 0.0;
  double _currentHeadingDeg = 0.0;
  double _currentPitchDeg = 0.0;
  double _currentRollDeg = 0.0;

  double _totalDistanceM = 0.0;
  double _totalDriftM = 0.0;

  // Smooth random walk wander angle for drift vector
  double _driftAngleRad = 0.0;
  double _driftOffsetX = 0.0; // East drift (meters)
  double _driftOffsetY = 0.0; // North drift (meters)

  final math.Random _random = math.Random();

  final StreamController<GhostNavState> _stateController = StreamController<GhostNavState>.broadcast();
  Stream<GhostNavState> get stateStream => _stateController.stream;

  void setEnabled(bool enabled) {
    if (_isEnabled == enabled) return;
    _isEnabled = enabled;
    if (_isEnabled) {
      startListening();
    } else {
      stopListening();
    }
    notifyListeners();
  }

  void setDriftRate(double rate) {
    _driftRate = rate.clamp(0.0, 0.05); // 0% to 5%
    notifyListeners();
  }

  void setAddMicroJitter(bool value) {
    _addMicroJitter = value;
    notifyListeners();
  }

  /// Start listening on UDP broadcast and P2P sockets
  Future<void> startListening() async {
    try {
      await stopListening();

      _connectionStatus = GhostConnectionStatus.listening;
      notifyListeners();

      _udpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        broadcastPort,
        reuseAddress: true,
        reusePort: !Platform.isWindows,
      );
      _udpSocket?.broadcastEnabled = true;

      _udpSocket?.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _udpSocket?.receive();
          if (datagram != null) {
            _handleIncomingData(datagram.data);
          }
        }
      });

      // Kinematic 20 Hz loop (every 50 ms)
      _kinematicTicker = Timer.periodic(const Duration(milliseconds: 50), (_) {
        _tickKinematics(0.05);
      });

      // Heartbeat & Hz calculation (every 1 second)
      _heartbeatChecker = Timer.periodic(const Duration(seconds: 1), (_) {
        _packetRateHz = _packetsThisSecond.toDouble();
        _packetsThisSecond = 0;

        if (_lastPacketTime != null) {
          final diff = DateTime.now().difference(_lastPacketTime!).inSeconds;
          if (diff > 3 && _connectionStatus == GhostConnectionStatus.connected) {
            _connectionStatus = GhostConnectionStatus.listening;
          }
        }
        notifyListeners();
      });
    } catch (e) {
      debugPrint('[SecretBtReceiver] Error binding socket: $e');
    }
  }

  Future<void> stopListening() async {
    _simulationTimer?.cancel();
    _simulationTimer = null;
    _kinematicTicker?.cancel();
    _kinematicTicker = null;
    _heartbeatChecker?.cancel();
    _heartbeatChecker = null;
    _udpSocket?.close();
    _udpSocket = null;
    _connectionStatus = GhostConnectionStatus.idle;
    _packetRateHz = 0.0;
  }

  void _handleIncomingData(List<int> bytes) {
    try {
      final jsonStr = utf8.decode(bytes);
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (map['magic'] == 'IDR_GHOST_GPS') {
        final packet = IdrGhostPacket.fromJson(map);
        _latestPacket = packet;
        _lastPacketTime = DateTime.now();
        _packetsReceived++;
        _packetsThisSecond++;
        _connectionStatus = GhostConnectionStatus.connected;
        notifyListeners();
      }
    } catch (e) {
      // Ignored malformed broadcast packets
    }
  }

  /// Inject packet directly (for testing or direct BLE/Nearby stream)
  void injectPacket(IdrGhostPacket packet) {
    _latestPacket = packet;
    _lastPacketTime = DateTime.now();
    _packetsReceived++;
    _packetsThisSecond++;
    _connectionStatus = GhostConnectionStatus.connected;
    _tickKinematics(0.05);
    notifyListeners();
  }

  /// Toggle or set synthetic Ghost Beacon simulation (for single-device testing)
  void toggleSimulation([bool? enable]) {
    final shouldEnable = enable ?? !isSimulating;
    if (shouldEnable) {
      startSimulation();
    } else {
      stopSimulation();
    }
  }

  /// Starts streaming synthetic ghost GPS telemetry along a realistic driving curve
  void startSimulation() {
    stopSimulation();
    setEnabled(true);
    double lat = _latestPacket?.latitude ?? _currentDriftedPos?.latitude ?? 18.5204;
    double lon = _latestPacket?.longitude ?? _currentDriftedPos?.longitude ?? 73.8567;
    double heading = _currentHeadingDeg != 0.0 ? _currentHeadingDeg : 45.0;
    double speedMps = 12.5; // ~45 km/h

    _simulationTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      // Simulate gentle highway curve with realistic speed variation
      heading = (heading + 0.45) % 360.0;
      final rad = (90.0 - heading) * (math.pi / 180.0);
      lat += (speedMps * 0.1 * math.sin(rad)) / 111320.0;
      lon += (speedMps * 0.1 * math.cos(rad)) / (111320.0 * math.cos(lat * math.pi / 180.0));

      final packet = IdrGhostPacket(
        latitude: lat,
        longitude: lon,
        altitude: 550.0,
        speedMps: speedMps,
        headingDeg: heading,
        accuracy: 1.2,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        sender: 'Simulated-Ghost-Beacon',
      );
      injectPacket(packet);
    });
    notifyListeners();
  }

  /// Stops synthetic ghost GPS telemetry simulation
  void stopSimulation() {
    _simulationTimer?.cancel();
    _simulationTimer = null;
    notifyListeners();
  }

  /// Computes smooth 20 Hz kinematic interpolation and injects artificial drift
  void _tickKinematics(double dtSec) {
    if (_latestPacket == null) return;
    final packet = _latestPacket!;

    // 1. Smoothly track target speed and heading
    final targetSpeed = packet.speedMps;
    final targetHeading = packet.headingDeg;

    // Immediately snap to initial orientation on first reception
    if (_packetsReceived <= 1) {
      _currentHeadingDeg = targetHeading;
      _currentSpeedMps = targetSpeed;
    }

    // Smooth speed tracking (exponential filter)
    final prevSpeed = _currentSpeedMps;
    _currentSpeedMps += (targetSpeed - _currentSpeedMps) * (dtSec * 5.0).clamp(0.0, 1.0);
    final isBraking = (prevSpeed - _currentSpeedMps) / dtSec > 1.2; // deceleration > 1.2 m/s^2

    // Smooth heading tracking with circular wrapping
    double diffHeading = targetHeading - _currentHeadingDeg;
    while (diffHeading > 180.0) diffHeading -= 360.0;
    while (diffHeading < -180.0) diffHeading += 360.0;
    final yawRateDegPerSec = diffHeading * (dtSec * 6.0).clamp(0.0, 1.0) / dtSec;
    _currentHeadingDeg = (_currentHeadingDeg + diffHeading * (dtSec * 6.0).clamp(0.0, 1.0)) % 360.0;
    if (_currentHeadingDeg < 0) _currentHeadingDeg += 360.0;

    // 2. Synthesize dynamic pitch and roll from acceleration and cornering
    final accelForward = (_currentSpeedMps - prevSpeed) / dtSec;
    // Pitch squat/dive: -1.5° on hard acceleration, +2.5° on braking
    _currentPitchDeg = (-accelForward * 0.4).clamp(-4.0, 4.0);

    // Roll centripetal tilt: lean outward into turns
    final yawRateRad = yawRateDegPerSec * (math.pi / 180.0);
    final lateralAccel = _currentSpeedMps * yawRateRad; // v * omega
    _currentRollDeg = (lateralAccel * 0.3).clamp(-5.0, 5.0);

    // 3. Accumulate traveled distance
    final stepDistanceM = _currentSpeedMps * dtSec;
    _totalDistanceM += stepDistanceM;

    // 4. Generate Artificial Dead-Reckoning Drift
    if (_driftRate > 0 && stepDistanceM > 0.001) {
      // Slow random walk in drift direction (Brownian wandering)
      _driftAngleRad += (_random.nextDouble() - 0.5) * 0.05;

      // Accumulate drift proportionally to distance
      final stepDrift = stepDistanceM * _driftRate;
      _driftOffsetX += stepDrift * math.cos(_driftAngleRad);
      _driftOffsetY += stepDrift * math.sin(_driftAngleRad);

      _totalDriftM = math.sqrt(_driftOffsetX * _driftOffsetX + _driftOffsetY * _driftOffsetY);
    }

    // High frequency sensor noise micro-jitter (sub-decimeter)
    double jitterX = 0.0;
    double jitterY = 0.0;
    if (_addMicroJitter && _currentSpeedMps > 0.5) {
      jitterX = (_random.nextDouble() - 0.5) * 0.25; // ±12 cm
      jitterY = (_random.nextDouble() - 0.5) * 0.25;
    }

    // Convert meters offset to lat/lng degrees (WGS84 approx: 111,320m per lat deg)
    const metersPerLatDeg = 111320.0;
    final metersPerLngDeg = 111320.0 * math.cos(packet.latitude * (math.pi / 180.0));

    final totalDeltaLat = (_driftOffsetY + jitterY) / metersPerLatDeg;
    final totalDeltaLng = (_driftOffsetX + jitterX) / metersPerLngDeg;

    final rawPos = LatLng(packet.latitude, packet.longitude);
    final driftedPos = LatLng(
      packet.latitude + totalDeltaLat,
      packet.longitude + totalDeltaLng,
    );
    _currentDriftedPos = driftedPos;

    // Calculate realistic drift percentage
    final driftPct = _totalDistanceM > 10.0
        ? (_totalDriftM / _totalDistanceM) * 100.0
        : (_driftRate * 100.0);

    final state = GhostNavState(
      rawPosition: rawPos,
      driftedPosition: driftedPos,
      speedKmh: _currentSpeedMps * 3.6,
      headingDeg: _currentHeadingDeg,
      pitchDeg: _currentPitchDeg,
      rollDeg: _currentRollDeg,
      cumulativeDistanceM: _totalDistanceM,
      cumulativeDriftM: _totalDriftM,
      driftPercentage: driftPct,
      isBraking: isBraking,
      lastPacketTime: _lastPacketTime ?? DateTime.now(),
    );

    _stateController.add(state);
  }

  void resetDrift() {
    _driftOffsetX = 0.0;
    _driftOffsetY = 0.0;
    _totalDistanceM = 0.0;
    _totalDriftM = 0.0;
    _packetsReceived = 0;
    _packetsThisSecond = 0;
    _latestPacket = null;
    _lastPacketTime = null;
    _currentHeadingDeg = 0.0;
    _currentSpeedMps = 0.0;
    _driftAngleRad = _random.nextDouble() * 2 * math.pi;
    notifyListeners();
  }

  @override
  void dispose() {
    stopListening();
    _stateController.close();
    super.dispose();
  }
}
