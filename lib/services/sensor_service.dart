import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import '../core/math_utils.dart';
import '../models/sensor_data.dart';

enum GpsHardwareStatus {
  serviceDisabled,        // Device GPS toggle is OFF
  permissionDenied,       // User denied location permission
  permissionDeniedForever,// User permanently denied permission (needs app settings)
  searching,              // Permissions OK, service ON, awaiting satellite lock
  locked,                 // Active fix received and streaming
  error,                  // Hardware or stream exception
}

/// Live Hardware Sensor Ingestion Service.
///
/// Interfaces directly with smartphone hardware:
/// 1. Accelerometer & Gyroscope (100 Hz) via sensors_plus.
/// 2. GNSS Fixes (1 Hz) with WGS-84 -> Local ENU projection via geolocator.
/// 3. Barometer fallback / elevation tracking.
class SensorService {
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  StreamSubscription<MagnetometerEvent>? _magSub;
  StreamSubscription<Position>? _gpsSub;
  StreamSubscription<ServiceStatus>? _serviceStatusSub;
  Timer? _autoRetryTimer;
  static const String _cacheFileName = 'last_known_position.json';

  final StreamController<ImuSample> _imuController = StreamController<ImuSample>.broadcast();
  final StreamController<GnssSample> _gnssController = StreamController<GnssSample>.broadcast();
  final StreamController<BaroSample> _baroController = StreamController<BaroSample>.broadcast();
  final StreamController<MagSample> _magController = StreamController<MagSample>.broadcast();
  final StreamController<GpsHardwareStatus> _gpsStatusController = StreamController<GpsHardwareStatus>.broadcast();

  Stream<ImuSample> get imuStream => _imuController.stream;
  Stream<GnssSample> get gnssStream => _gnssController.stream;
  Stream<BaroSample> get baroStream => _baroController.stream;
  Stream<MagSample> get magStream => _magController.stream;
  Stream<GpsHardwareStatus> get gpsStatusStream => _gpsStatusController.stream;

  GpsHardwareStatus _gpsStatus = GpsHardwareStatus.searching;
  GpsHardwareStatus get gpsStatus => _gpsStatus;
  String? _lastGpsMessage;
  String? get lastGpsMessage => _lastGpsMessage;

  Position? _lastKnownPosition;
  Position? get lastKnownPosition => _lastKnownPosition;

  // Local ENU reference anchor
  double? _refLat;
  double? _refLon;
  double? _refAlt;

  double? get refLat => _refLat;
  double? get refLon => _refLon;
  double? get refAlt => _refAlt;

  Vec3 _lastRawAccel = Vec3.zero;
  Vec3 _lastRawGyro = Vec3.zero;
  Vec3 _lastRawMag = Vec3.zero;

  bool _isListening = false;
  bool get isListening => _isListening;

  void _updateGpsStatus(GpsHardwareStatus status, String? message) {
    _gpsStatus = status;
    _lastGpsMessage = message;
    if (!_gpsStatusController.isClosed) {
      _gpsStatusController.add(status);
    }
  }

  /// Request permissions, check hardware toggles, and start hardware sensor listening.
  Future<bool> start() async {
    if (_isListening) return true;

    // 1. Accelerometer (using gameInterval ~50-60 Hz for optimal stability without burst jitter)
    try {
      _accelSub = accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval).listen(
        (event) {
          _lastRawAccel = Vec3(event.x, event.y, event.z);
          _emitImuSample();
        },
        onError: (err) => debugPrint('Accel stream error: $err'),
      );
    } catch (e) {
      debugPrint('Accel not available: $e');
    }

    // 2. Gyroscope
    try {
      _gyroSub = gyroscopeEventStream(samplingPeriod: SensorInterval.gameInterval).listen(
        (event) {
          _lastRawGyro = Vec3(event.x, event.y, event.z);
        },
        onError: (err) => debugPrint('Gyro stream error: $err'),
      );
    } catch (e) {
      debugPrint('Gyro not available: $e');
    }

    // 3. Magnetometer (Electronic Compass)
    try {
      _magSub = magnetometerEventStream(samplingPeriod: SensorInterval.gameInterval).listen(
        (event) {
          _lastRawMag = Vec3(event.x, event.y, event.z);
          _emitMagSample();
        },
        onError: (err) => debugPrint('Magnetometer stream note: $err'),
      );
    } catch (e) {
      debugPrint('Magnetometer not available: $e');
    }

    // Pre-load persistent cached position so map immediately centers on user's city
    await _loadCachedPositionFromDisk();

    // Dynamically listen to system location toggles (e.g. user toggles GPS in quick settings)
    _serviceStatusSub?.cancel();
    try {
      _serviceStatusSub = Geolocator.getServiceStatusStream().listen((ServiceStatus status) {
        debugPrint('[SensorService] Device location service status changed: $status');
        if (status == ServiceStatus.enabled) {
          initGps();
        } else {
          _updateGpsStatus(GpsHardwareStatus.serviceDisabled, 'Location services are disabled in device settings');
        }
      });
    } catch (e) {
      debugPrint('[SensorService] Service status stream note: $e');
    }

    // Auto-retry timer to connect seamlessly as soon as user enables location
    _autoRetryTimer?.cancel();
    _autoRetryTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!_isListening) {
        timer.cancel();
        return;
      }
      if (_gpsStatus == GpsHardwareStatus.serviceDisabled) {
        final enabled = await Geolocator.isLocationServiceEnabled();
        if (enabled) {
          debugPrint('[SensorService] Location service now active, auto-connecting GPS...');
          await initGps();
        }
      }
    });

    // 4. GNSS Position with instant cached fix & continuous streaming
    await initGps();

    _isListening = true;
    return true;
  }

  /// Initialize GNSS hardware: verifies location service toggle, requests permissions,
  /// obtains instant cached position, fires active GPS fix, and begins stream.
  Future<void> initGps() async {
    try {
      // 1. Immediate instant fix from cache (<50ms) to unblock UI & anchor immediately
      try {
        final cached = await Geolocator.getLastKnownPosition();
        if (cached != null) {
          _lastKnownPosition = cached;
          _handleGpsPosition(cached);
          _updateGpsStatus(GpsHardwareStatus.locked, 'Instant fix (±${cached.accuracy.toStringAsFixed(1)}m)');
        }
      } catch (e) {
        debugPrint('Last known position note: $e');
      }

      final isServiceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isServiceEnabled) {
        _updateGpsStatus(GpsHardwareStatus.serviceDisabled, 'Location services are disabled in device settings');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        _updateGpsStatus(GpsHardwareStatus.permissionDenied, 'Location permission denied by user');
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        _updateGpsStatus(GpsHardwareStatus.permissionDeniedForever, 'Location permission permanently denied. Enable in app settings.');
        return;
      }

      _updateGpsStatus(GpsHardwareStatus.searching, 'Searching for GNSS satellites...');

      // 2. Active single-shot request to force GPS / Fused provider to lock
      Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          timeLimit: Duration(seconds: 8),
        ),
      ).then((pos) {
        _lastKnownPosition = pos;
        _handleGpsPosition(pos);
        _updateGpsStatus(GpsHardwareStatus.locked, 'GNSS Locked (±${pos.accuracy.toStringAsFixed(1)}m)');
      }).catchError((e) {
        debugPrint('Active current position note: $e');
      });

      // 3. Continuous 1 Hz position stream
      await _startGpsStream();
    } catch (e) {
      _updateGpsStatus(GpsHardwareStatus.error, e.toString());
      debugPrint('GNSS Init error: $e');
    }
  }

  Future<void> _startGpsStream() async {
    await _gpsSub?.cancel();
    _gpsSub = null;

    LocationSettings locationSettings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: 0,
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      );
    }

    _gpsSub = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (Position pos) {
        _lastKnownPosition = pos;
        _handleGpsPosition(pos);
        _updateGpsStatus(GpsHardwareStatus.locked, 'Live GNSS (±${pos.accuracy.toStringAsFixed(1)}m)');
      },
      onError: (err) {
        debugPrint('GPS stream error: $err');
        _updateGpsStatus(GpsHardwareStatus.error, err.toString());
      },
    );
  }

  /// Open device system location settings page (e.g. to turn on GPS)
  Future<bool> openLocationSettings() async {
    return await Geolocator.openLocationSettings();
  }

  /// Open application permission settings page (e.g. when deniedForever)
  Future<bool> openAppSettings() async {
    return await Geolocator.openAppSettings();
  }

  /// Force a fresh GPS lock attempt
  Future<void> forceRefreshLocation() async {
    await initGps();
  }

  void _emitImuSample() {
    final nowSec = DateTime.now().millisecondsSinceEpoch / 1000.0;
    _imuController.add(ImuSample(
      timestamp: nowSec,
      accel: _lastRawAccel,
      gyro: _lastRawGyro,
    ));
  }

  Vec3? _filteredMag;
  Vec3? _filteredGravityForMag;
  double? _lastEmittedHeading;

  void _emitMagSample() {
    if (_lastRawAccel.norm < 1.0) return;
    
    // Low-pass filter magnetic field and gravity to eliminate high-frequency 50 Hz jitter
    _filteredMag = _filteredMag == null
        ? _lastRawMag
        : _filteredMag! * 0.92 + _lastRawMag * 0.08;
    _filteredGravityForMag = _filteredGravityForMag == null
        ? _lastRawAccel
        : _filteredGravityForMag! * 0.90 + _lastRawAccel * 0.10;

    // Reject severe electromagnetic anomalies (Earth magnetic field is 25-65 uT)
    final magNorm = _filteredMag!.norm;
    if (magNorm < 15.0 || magNorm > 130.0) return;

    final headingRad = MathUtils.computeTiltCompensatedHeading(
      gravity: _filteredGravityForMag!,
      magneticField: _filteredMag!,
    );

    // Angular deadband: avoid emitting sub-degree micro-jitter (< 1.2 degrees)
    if (_lastEmittedHeading != null) {
      final diff = MathUtils.normalizeAngle(headingRad - _lastEmittedHeading!).abs();
      if (diff < 0.02) return;
    }
    _lastEmittedHeading = headingRad;

    final nowSec = DateTime.now().millisecondsSinceEpoch / 1000.0;
    _magController.add(MagSample(
      timestamp: nowSec,
      magneticField: _filteredMag!,
      headingRad: headingRad,
    ));
  }

  void _handleGpsPosition(Position pos) {
    final nowSec = DateTime.now().millisecondsSinceEpoch / 1000.0;

    // Anchor reference origin on first fix
    _refLat ??= pos.latitude;
    _refLon ??= pos.longitude;
    _refAlt ??= pos.altitude;

    // Convert WGS84 lat/lon to local ENU meters
    const double rEarth = 6378137.0; // meters
    final latRad = MathUtils.degToRad(pos.latitude);
    final refLatRad = MathUtils.degToRad(_refLat!);

    final dLat = latRad - refLatRad;
    final dLon = MathUtils.degToRad(pos.longitude - _refLon!);

    final localX = dLon * rEarth * math.cos(refLatRad);
    final localY = dLat * rEarth;
    final localZ = pos.altitude - _refAlt!;

    // Convert horizontal accuracy to HDOP approximation
    // Android accuracy is 68th-percentile radius. HDOP ≈ accuracy / UERE.
    // Use UERE ~5.0m (conservative for modern multi-constellation receivers).
    final approxHdop = math.max(1.0, pos.accuracy / 5.0);

    _gnssController.add(GnssSample(
      timestamp: nowSec,
      position: Vec3(localX, localY, localZ),
      latitude: pos.latitude,
      longitude: pos.longitude,
      altitude: pos.altitude,
      speed: pos.speed,
      heading: pos.heading,
      hdop: approxHdop,
      accuracy: pos.accuracy,
      isDenied: false,
    ));

    // Emit altitude sample to barometer channel
    _baroController.add(BaroSample(
      timestamp: nowSec,
      pressureHpa: 1013.25,
      altitude: localZ,
    ));

    // Persist position to disk for instant cold-boot map loading
    _savePositionToDisk(pos);
  }

  Future<void> _loadCachedPositionFromDisk() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_cacheFileName');
      if (await file.exists()) {
        final content = await file.readAsString();
        final map = jsonDecode(content) as Map<String, dynamic>;
        final lat = (map['lat'] as num).toDouble();
        final lon = (map['lon'] as num).toDouble();
        final alt = (map['alt'] as num?)?.toDouble() ?? 0.0;
        final acc = (map['acc'] as num?)?.toDouble() ?? 10.0;

        _refLat ??= lat;
        _refLon ??= lon;
        _refAlt ??= alt;

        final cachedPos = Position(
          longitude: lon,
          latitude: lat,
          timestamp: DateTime.now(),
          accuracy: acc,
          altitude: alt,
          altitudeAccuracy: 10.0,
          heading: 0.0,
          headingAccuracy: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
        );

        _lastKnownPosition ??= cachedPos;
        _handleGpsPosition(cachedPos);
        debugPrint('[SensorService] Loaded persistent last-known position: $lat, $lon');
      }
    } catch (e) {
      debugPrint('[SensorService] Cache load error: $e');
    }
  }

  Future<void> _savePositionToDisk(Position pos) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_cacheFileName');
      final data = {
        'lat': pos.latitude,
        'lon': pos.longitude,
        'alt': pos.altitude,
        'acc': pos.accuracy,
        'timestamp': pos.timestamp.millisecondsSinceEpoch,
      };
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('[SensorService] Cache save error: $e');
    }
  }

  Future<void> stop() async {
    await _accelSub?.cancel();
    await _gyroSub?.cancel();
    await _magSub?.cancel();
    await _gpsSub?.cancel();
    await _serviceStatusSub?.cancel();
    _autoRetryTimer?.cancel();
    _accelSub = null;
    _gyroSub = null;
    _magSub = null;
    _gpsSub = null;
    _serviceStatusSub = null;
    _autoRetryTimer = null;
    _isListening = false;
  }

  void setReferenceAnchor(double lat, double lon, double alt) {
    _refLat = lat;
    _refLon = lon;
    _refAlt = alt;
  }

  void resetReferenceAnchor() {
    _refLat = null;
    _refLon = null;
    _refAlt = null;
  }

  void dispose() {
    stop();
    _imuController.close();
    _gnssController.close();
    _baroController.close();
    _magController.close();
    _gpsStatusController.close();
  }
}
