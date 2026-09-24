import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../core/constants.dart';
import '../core/math_utils.dart';
import '../models/nav_solution.dart';
import '../models/sensor_data.dart';
import 'baseline_dr.dart';
import 'cabin_alignment.dart';
import 'dynamic_map_service.dart';
import 'ekf_3d.dart';
import 'map_snapper.dart';
import 'navigation_service.dart';
import 'osm_map_loader.dart';
import 'sensor_service.dart';
import 'tcn_speed_engine.dart';
import 'turn_detector.dart';
import 'vibration_gate.dart';
import 'native_bridge.dart';


/// Master Orchestration Pipeline for the Intelligent Dead Reckoning (IDR) System.
///
/// Seamlessly synchronizes:
/// - Cabin Tilt Alignment (Module 1)
/// - Kinetic Vibration Gate (Module 2)
/// - TCN Forward Speed Engine (Module 3)
/// - 6D EKF with Non-Holonomic Constraints (Module 4)
/// - Smart 3D Map-Matching Filter (Module 5)
/// - Classic Double-Integration Baseline (Module 6)
class IdrPipeline extends ChangeNotifier {
  final CabinAligner _aligner = CabinAligner();
  final VibrationGate _vibrationGate = VibrationGate();
  final TcnSpeedEngine _tcnSpeed = TcnSpeedEngine();
  final Ekf3D _ekf = Ekf3D();
  final BaselineDr _classicDr = BaselineDr();
  final MapSnapper _mapSnapper = MapSnapper(branches: []);
  final TurnDetector _turnDetector = TurnDetector();
  final NativeBridge _nativeBridge = NativeBridge.instance;

  int get activeRoadBranchCount => _mapSnapper.branches.length;
  bool get isNativeEngineActive => _nativeBridge.isAvailable;

  MapSnapper get mapSnapper => _mapSnapper;
  TurnDetector get turnDetector => _turnDetector;


  void _applyOsmMapResult(({List<MapBranch> branches, double refLat, double refLon, double refAlt}) result) {
    if (result.branches.isNotEmpty) {
      _mapSnapper.branches.clear();
      _mapSnapper.branches.addAll(result.branches);
      _sensorService.setReferenceAnchor(result.refLat, result.refLon, result.refAlt);
      _nativeBridge.setReferenceAnchor(result.refLat, result.refLon, result.refAlt);
      if (result.refLat != 0.0) {
        _ekf.setLatitude(result.refLat);
      }
      notifyListeners();
    }
  }

  /// Ingest and activate a custom offline OpenStreetMap GeoJSON road network (e.g. Maharashtra expressways).
  Future<void> loadOfflineOsmMap(
    String assetPath, {
    String? mapName,
    double? anchorLat,
    double? anchorLon,
    double? anchorAlt,
  }) async {
    try {
      final result = await OsmMapLoader.loadFromAsset(
        assetPath,
        anchorLat: anchorLat,
        anchorLon: anchorLon,
        anchorAlt: anchorAlt,
      );
      _applyOsmMapResult(result);
    } catch (e) {
      debugPrint('Error loading offline OSM map: $e');
    }
  }

  /// Ingest and activate a downloaded offline OpenStreetMap GeoJSON from local device storage.
  Future<void> loadOfflineOsmMapFromFile(
    File file, {
    String? mapName,
    double? anchorLat,
    double? anchorLon,
    double? anchorAlt,
  }) async {
    try {
      final result = await OsmMapLoader.loadFromFile(
        file,
        anchorLat: anchorLat,
        anchorLon: anchorLon,
        anchorAlt: anchorAlt,
      );
      _applyOsmMapResult(result);
    } catch (e) {
      debugPrint('Error loading offline OSM map file: $e');
    }
  }


  final SensorService _sensorService = SensorService();
  final DynamicMapService _dynamicMapService = DynamicMapService();
  final NavigationService _navigationService = NavigationService();

  SensorService get sensorService => _sensorService;
  DynamicMapService get dynamicMapService => _dynamicMapService;
  NavigationService get navigationService => _navigationService;
  bool _isRunning = false;
  Timer? _timer;

  // Manual interactive toggles
  bool _forceTunnelOutage = false;
  bool _forcePotholes = false;
  bool _forcePedestrian = false;
  bool _forceVehicle = false;

  // Trajectory history for map rendering (downsampled for smooth 60fps canvas)
  final List<Vec3> idrTrajectory = [];
  final List<Vec3> classicTrajectory = [];
  final List<Vec3> groundTruthTrajectory = [];
  static const int maxHistoryPoints = 800;
  int? _outageTrajectoryStartIndex;

  // Subscriptions for live sensor streams
  StreamSubscription<ImuSample>? _imuSub;
  StreamSubscription<GnssSample>? _gnssSub;
  StreamSubscription<BaroSample>? _baroSub;
  StreamSubscription<MagSample>? _magSub;
  StreamSubscription<GpsHardwareStatus>? _gpsStatusSub;
  double? _lastLiveImuTimestamp;
  NavSolution? _latestSolution;
  NavSolution? get latestSolution => _latestSolution;


  bool get isRunning => _isRunning;
  bool get forceTunnelOutage => _forceTunnelOutage;
  bool get forcePotholes => _forcePotholes;
  bool get forcePedestrian => _forcePedestrian;
  bool get forceVehicle => _forceVehicle;
  bool get isCabinLocked => _aligner.isLocked;
  double get cabinConfidence => _aligner.confidence;
  bool get isTcnModelLoaded => _tcnSpeed.isModelLoaded;
  double get shockThreshold => _vibrationGate.shockThreshold;

  void setShockThreshold(double value) {
    _vibrationGate.shockThreshold = value;
    notifyListeners();
  }

  void releaseStandstillLock() {
    _tcnSpeed.clearGnssForceStandstill();
    notifyListeners();
  }

  void setModeAuto() {
    _forcePedestrian = false;
    _forceVehicle = false;
    notifyListeners();
  }

  // Dead reckoning outage accumulation for real-time drift metrics
  double _drDistanceTraveled = 0.0;
  double _drOutageDurationSec = 0.0;
  Vec3? _lastDrPos;
  double? _latestGnssSpeed;

  // Live GNSS state tracking (for async GNSS updates in live mode)
  double _liveGnssHdop = 1.0;
  bool _liveGnssDenied = false;
  bool _liveGnssActive = false; // true once we've received at least one fix
  double? _latestLatitude;
  double? _latestLongitude;
  double? _latestAccuracyMeters;
  String? _latestGpsMessage;
  double _calibratedP0 = 1013.25;
  double? _lastBaroPressureHpa;
  final List<double> _baroAltHistory = [];
  double? _lastBaroTimestamp;

  GpsHardwareStatus get gpsHardwareStatus => _sensorService.gpsStatus;
  String? get gpsStatusMessage => _latestGpsMessage ?? _sensorService.lastGpsMessage;
  double? get currentLatitude => _latestLatitude ?? _sensorService.lastKnownPosition?.latitude;
  double? get currentLongitude => _latestLongitude ?? _sensorService.lastKnownPosition?.longitude;
  double? get currentAccuracyMeters => _latestAccuracyMeters ?? _sensorService.lastKnownPosition?.accuracy;

  Future<bool> openLocationSettings() => _sensorService.openLocationSettings();
  Future<bool> openAppSettings() => _sensorService.openAppSettings();
  Future<void> forceRefreshGps() async {
    await _sensorService.forceRefreshLocation();
    notifyListeners();
  }

  Vec3? _lastGnssPos;
  int _lastUiNotifyMs = 0;

  void _throttledNotifyListeners() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastUiNotifyMs >= 33) { // ~30 FPS
      _lastUiNotifyMs = now;
      notifyListeners();
    }
  }

  IdrPipeline() {
    _initDefaultSolution();
    _initTcnModel();
    _navigationService.addListener(notifyListeners);
    // Eagerly start GPS acquisition so coordinates are available on first frame
    _sensorService.start();
    // Auto-start the pipeline so GNSS stream is subscribed and the 50km
    // dynamic map auto-download triggers on first GPS fix.
    start();
  }

  Future<void> _initTcnModel() async {
    final loaded = await _tcnSpeed.loadModel();
    if (loaded) {
      notifyListeners();
    }
  }

  void _initDefaultSolution() {
    _latestSolution = NavSolution(
      timestamp: 0.0,
      idrState: _ekf.state,
      classicDrState: _classicDr.state,
      gnssStatus: GnssStatus.available,
      hdop: 1.0,
      isGnssDenied: false,
      idrDriftError: 0.0,
      classicDriftError: 0.0,
      shockDetected: false,
      rawJerk: 0.0,
      jerkVariance: 0.0,
      tcnEstimatedSpeed: 0.0,
      baroAltitude: 0.0,
      cabinConfidence: 0.0,
      isCabinLocked: false,
      mountPitchDeg: 0.0,
      mountRollDeg: 0.0,
      isTcnModelLoaded: _tcnSpeed.isModelLoaded,
      latitude: _latestLatitude ?? _sensorService.lastKnownPosition?.latitude,
      longitude: _latestLongitude ?? _sensorService.lastKnownPosition?.longitude,
      accuracyMeters: _latestAccuracyMeters ?? _sensorService.lastKnownPosition?.accuracy,
      gpsStatusMessage: _latestGpsMessage ?? _sensorService.lastGpsMessage,
    );
  }


  void start() {
    if (_isRunning) return;
    _isRunning = true;

    _sensorService.start();
    _imuSub?.cancel();
    _gnssSub?.cancel();
    _baroSub?.cancel();
    _magSub?.cancel();
    _gpsStatusSub?.cancel();
    
    _imuSub = _sensorService.imuStream.listen(_processLiveImu);
    _gnssSub = _sensorService.gnssStream.listen(_processLiveGnss);
    _baroSub = _sensorService.baroStream.listen(_processLiveBaro);
    _magSub = _sensorService.magStream.listen(_processLiveMag);
    _gpsStatusSub = _sensorService.gpsStatusStream.listen((status) {
      _latestGpsMessage = _sensorService.lastGpsMessage;
      notifyListeners();
    });

    notifyListeners();
  }

  void pause() {
    _isRunning = false;
    _timer?.cancel();
    _timer = null;
    _imuSub?.cancel();
    _gnssSub?.cancel();
    _baroSub?.cancel();
    _magSub?.cancel();
    _gpsStatusSub?.cancel();
    _imuSub = null;
    _gnssSub = null;
    _baroSub = null;
    _magSub = null;
    _gpsStatusSub = null;
    _lastLiveImuTimestamp = null;
    notifyListeners();
  }

  void reset() {
    final wasRunning = _isRunning;
    pause();

    _aligner.reset();
    _vibrationGate.reset();
    _tcnSpeed.reset();
    _ekf.reset();
    _classicDr.reset();
    _turnDetector.reset();
    _nativeBridge.reset();
    _dynamicMapService.reset();
    _navigationService.cancelNavigation();
    _sensorService.resetReferenceAnchor();
    _drDistanceTraveled = 0.0;
    _drOutageDurationSec = 0.0;
    _lastDrPos = null;
    _latestGnssSpeed = null;
    _liveGnssHdop = 1.0;
    _liveGnssDenied = false;
    _liveGnssActive = false;
    _latestLatitude = null;
    _latestLongitude = null;
    _latestAccuracyMeters = null;
    _latestGpsMessage = null;
    _calibratedP0 = 1013.25;
    _lastBaroPressureHpa = null;
    _baroAltHistory.clear();
    _lastBaroTimestamp = null;

    idrTrajectory.clear();
    classicTrajectory.clear();
    groundTruthTrajectory.clear();
    _outageTrajectoryStartIndex = null;

    _initDefaultSolution();
    if (wasRunning) {
      start();
    } else {
      notifyListeners();
    }
  }

  void toggleTunnelOutage() {
    _forceTunnelOutage = !_forceTunnelOutage;
    _nativeBridge.setOutage(_forceTunnelOutage);
    if (_forceTunnelOutage) {
      _tcnSpeed.clearGnssForceStandstill();
    }
    notifyListeners();
  }

  void togglePotholes() {
    _forcePotholes = !_forcePotholes;
    notifyListeners();
  }

  void forceCalibrateCabin() {
    _aligner.forceCalibrate();
    notifyListeners();
  }

  /// Reset dead-reckoning drift counter and anchor to current position
  void resetDrift() {
    _drDistanceTraveled = 0.0;
    _drOutageDurationSec = 0.0;
    _lastDrPos = null;
    _classicDr.syncWithGnss(
      position: _ekf.state.position,
      velocity: _ekf.state.velocity,
      yaw: _ekf.state.yaw,
    );
    if (_nativeBridge.isAvailable) {
      _nativeBridge.reset();
    }
    notifyListeners();
  }

  // --- Live Sensor Handlers ---
  void _processLiveImu(ImuSample imu) {
    if (!_isRunning) return;
    double dt = IdrConstants.dtImu;
    if (_lastLiveImuTimestamp != null) {
      final diff = imu.timestamp - _lastLiveImuTimestamp!;
      if (diff > 0.002 && diff < 0.1) {
        dt = diff;
      }
    }
    _lastLiveImuTimestamp = imu.timestamp;

    _processFullStep(
      imu: imu,
      dt: dt,
    );
  }

  void _processLiveMag(MagSample mag) {
    if (!_isRunning) return;
    final bNorm = mag.magneticField.norm;
    // Quasi-Static Magnetic Field (QSMF) check: reject severe electromagnetic interference
    if (bNorm > 0.0 && (bNorm < 15.0 || bNorm > 80.0)) return;

    // Magnetic inclination (dip angle) invariance check
    final gRef = _aligner.lowPassGravity ?? const Vec3(0.0, 0.0, 9.80665);
    final dip = MathUtils.magneticDipAngle(mag.magneticField, gRef);
    if (dip.abs() > 1.45) return; // Reject extreme perpendicular magnetic field distortions

    final enuRad = MathUtils.compassToEnuRad(mag.headingDeg);
    _ekf.updateCompass(enuRad, isStationary: _tcnSpeed.isStationary, magneticFieldNorm: bNorm);
    _nativeBridge.processMag(mag);
  }

  void toggleForcePedestrian() {
    _forcePedestrian = !_forcePedestrian;
    if (_forcePedestrian) _forceVehicle = false;
    notifyListeners();
  }

  void toggleForceVehicle() {
    _forceVehicle = !_forceVehicle;
    if (_forceVehicle) _forcePedestrian = false;
    notifyListeners();
  }

  void _processLiveGnss(GnssSample gnss) {
    if (!_isRunning) return;

    var effectiveGnss = gnss;
    if (_forceTunnelOutage) {
      effectiveGnss = GnssSample(
        timestamp: gnss.timestamp,
        position: gnss.position,
        latitude: gnss.latitude,
        longitude: gnss.longitude,
        altitude: gnss.altitude,
        speed: 0.0,
        heading: gnss.heading,
        hdop: 25.0,
        isDenied: true,
      );
    }

    // Track live GNSS state so _processFullStep can use correct status
    _liveGnssActive = true;
    _liveGnssHdop = effectiveGnss.hdop;
    _liveGnssDenied = effectiveGnss.isDenied;
    _latestGnssSpeed = effectiveGnss.isDenied ? null : effectiveGnss.speed;
    _latestLatitude = effectiveGnss.latitude;
    _latestLongitude = effectiveGnss.longitude;
    _latestAccuracyMeters = effectiveGnss.accuracy;
    _latestGpsMessage = _sensorService.lastGpsMessage;
    if (effectiveGnss.latitude != 0.0) {
      _ekf.setLatitude(effectiveGnss.latitude);
    }

    // Hardware latency compensation (OOSM forward extrapolation):
    // Android GNSS baseband chip has an intrinsic computation delay of ~150ms.
    // Forward-extrapolate coordinates along Doppler velocity vector to match current epoch:
    var gnssX = effectiveGnss.x;
    var gnssY = effectiveGnss.y;
    var gnssZ = effectiveGnss.z;
    if (!effectiveGnss.isDenied && effectiveGnss.speed > 0.8 && effectiveGnss.hdop <= 4.0) {
      const double tauDelay = 0.15; // 150 ms typical Android GNSS baseband delay
      final courseEnuRad = MathUtils.compassToEnuRad(effectiveGnss.heading);
      gnssX += effectiveGnss.speed * math.cos(courseEnuRad) * tauDelay;
      gnssY += effectiveGnss.speed * math.sin(courseEnuRad) * tauDelay;
    }

    _ekf.updateGnss(
      gnssX: gnssX,
      gnssY: gnssY,
      gnssZ: gnssZ,
      hdop: effectiveGnss.hdop,
      isDenied: effectiveGnss.isDenied,
    );
    if (!effectiveGnss.isDenied) {
      if (effectiveGnss.speed > 0.8 && effectiveGnss.hdop <= 4.0) {
        final courseEnuRad = MathUtils.compassToEnuRad(effectiveGnss.heading);
        final vEast = effectiveGnss.speed * math.cos(courseEnuRad);
        final vNorth = effectiveGnss.speed * math.sin(courseEnuRad);
        _ekf.updateGnssVelocityVector(
          vEast: vEast,
          vNorth: vNorth,
          hdop: effectiveGnss.hdop,
          isDenied: false,
        );
      } else {
        _ekf.updateGnssSpeed(effectiveGnss.speed, effectiveGnss.hdop);
      }
    }
    _nativeBridge.processGnss(effectiveGnss);
    _nativeBridge.syncGnssSpeed(effectiveGnss.speed, effectiveGnss.hdop, effectiveGnss.isDenied);
    _tcnSpeed.synchronizeGnssSpeed(
      effectiveGnss.speed,
      effectiveGnss.hdop,
      isDenied: effectiveGnss.isDenied,
    );

    // Online Recursive Least Squares (RLS) Speed Calibration & Bias Trimming:
    if (!effectiveGnss.isDenied && effectiveGnss.speed > 2.0 && effectiveGnss.hdop <= 4.0) {
      _tcnSpeed.updateRlsCalibration(effectiveGnss.speed, effectiveGnss.hdop);
      final speedError = effectiveGnss.speed - _tcnSpeed.estimatedSpeed;
      _tcnSpeed.applyBiasCorrection(speedError * 0.05);
    }

    // Dynamic local sea-level base pressure P0 calibration from accurate GNSS:
    if (!effectiveGnss.isDenied && effectiveGnss.hdop <= 2.5 && effectiveGnss.altitude != 0.0 && _lastBaroPressureHpa != null) {
      final p0Est = MathUtils.calibratedSeaLevelPressure(_lastBaroPressureHpa!, effectiveGnss.altitude);
      if (p0Est >= 940.0 && p0Est <= 1070.0) {
        _calibratedP0 = _calibratedP0 * 0.98 + p0Est * 0.02;
      }
    }

    // Heading update from GNSS Doppler ground track course or position displacement:
    if (!effectiveGnss.isDenied) {
      if (effectiveGnss.speed > 0.8 && effectiveGnss.hdop <= 4.0) {
        final courseEnuRad = MathUtils.compassToEnuRad(effectiveGnss.heading);
        _ekf.updateCourse(courseEnuRad, effectiveGnss.speed, hdop: effectiveGnss.hdop);
      } else if (_lastGnssPos != null && !_tcnSpeed.isStationary && _ekf.forwardSpeed > 1.2) {
        // ONLY update course from position displacement if the vehicle is actively driving forward
        final dPos = effectiveGnss.position - _lastGnssPos!;
        final dDist = dPos.norm;
        if (dDist >= 3.0 && effectiveGnss.hdop <= 3.5) {
          final groundBearingRad = math.atan2(dPos.x, dPos.y); // Compass bearing
          final groundEnuRad = MathUtils.compassToEnuRad(MathUtils.radToDeg(groundBearingRad));
          _ekf.updateCourse(groundEnuRad, effectiveGnss.speed, hdop: effectiveGnss.hdop);
        }
      }
      _lastGnssPos = effectiveGnss.position;
    }

    // Sync Classic DR when GNSS is nominal so it doesn't accumulate drift
    if (!effectiveGnss.isDenied && effectiveGnss.hdop <= 5.0) {
      _classicDr.syncWithGnss(
        position: _ekf.state.position,
        velocity: _ekf.state.velocity,
        yaw: _ekf.state.yaw,
      );
    }

    // Dynamic 50km radius map management & 25km buffer tracking
    if (!effectiveGnss.isDenied && (effectiveGnss.latitude != 0.0 || effectiveGnss.longitude != 0.0)) {
      _dynamicMapService.onLocationUpdate(
        effectiveGnss.latitude,
        effectiveGnss.longitude,
        this,
      );
    }

    // Immediately trigger UI rebuild on fresh GNSS position fix
    notifyListeners();
  }

  void _processLiveBaro(BaroSample baro) {
    if (!_isRunning) return;
    _lastBaroPressureHpa = baro.pressureHpa;
    final alt = (_calibratedP0 != 1013.25 && baro.pressureHpa > 0.0)
        ? MathUtils.altitudeFromCalibratedPressure(baro.pressureHpa, _calibratedP0)
        : baro.altitude;
    _baroAltHistory.add(alt);
    if (_baroAltHistory.length > 5) _baroAltHistory.removeAt(0);

    double dtBaro = 0.10;
    if (_lastBaroTimestamp != null) {
      final diff = baro.timestamp - _lastBaroTimestamp!;
      if (diff > 0.02 && diff < 0.50) dtBaro = diff;
    }
    _lastBaroTimestamp = baro.timestamp;

    _ekf.updateBarometer(alt);
    if (_baroAltHistory.length >= 3) {
      final climbRate = MathUtils.savitzkyGolayDerivative5Scalar(_baroAltHistory, dtBaro);
      _ekf.updateBaroClimbRate(climbRate);
    }
    _nativeBridge.processBaro(baro);
  }

  // --- Core IDR Processing Step ---
  void _processFullStep({
    required ImuSample imu,
    BaroSample? baro,
    GnssSample? gnss,
    Vec3? gtPos,
    double? gtSpeed,
    double dt = 0.01,
  }) {
    // 1. Module 1: Cabin Alignment (Mahony SO(3) observer + TCN motion gating)
    _aligner.ingest(
      imu.accel,
      imu.gyro,
      vTcn: _tcnSpeed.estimatedSpeed,
      tcnVariance: _tcnSpeed.estimatedVariance,
      dt: dt,
    );
    final aVeh = _aligner.transformAccel(imu.accel);
    final fVeh = _aligner.transformSpecificForce(imu.accel);
    final wVeh = _aligner.transformGyro(imu.gyro);

    // Current attitude Euler angles for terrain slope pitch compensation and banking
    final currentEuler = _ekf.state.attitude; // roll (x), pitch (y), yaw (z)

    // 2. Module 3: TCN Speed Engine & Standstill Check (Skog GLRT)
    final isShockPrev = _vibrationGate.isShockDetected;
    final vTcn = _tcnSpeed.predict(
      vehicleAccel: aVeh,
      vehicleGyro: wVeh,
      isShockGateActive: isShockPrev,
      dt: dt,
      pitchRad: currentEuler.y,
      rollRad: currentEuler.x,
    );
    // Use dynamic standstill detector from TCN / ZUPT.
    // Do not permanently block motion while aligner is converging.
    final isStationary = _tcnSpeed.isStationary;
    final isPedestrian = _forcePedestrian ? true : (_forceVehicle ? false : _tcnSpeed.isPedestrian);

    // 3. Module 2: Kinetic Vibration Gate (Huber M-estimation + TCN uncertainty fusion)
    _vibrationGate.process(
      aVeh,
      dt,
      isStationary: isStationary,
      isPedestrian: isPedestrian,
      tcnVariance: _tcnSpeed.estimatedVariance,
    );
    final isShock = _vibrationGate.isShockDetected;
    final qInflation = _vibrationGate.getCovarianceInflation();

    // Turn Profiling with TCN speed coupling
    _turnDetector.processYawRate(wVeh.z, dt, vTcn: isStationary ? 0.0 : vTcn);

    // 4. Module 4: 6-State 3D EKF Propagation & Constraints (Eqns 17-24)
    if (isStationary) {
      _ekf.applyStandstill(wVeh.z, aVeh.x);
    }

    final effectiveSpeed = isStationary ? 0.0 : vTcn;

    // In live mode, completely skip EKF position propagation when stationary
    // to eliminate micro-drift from noisy accelerometer integration at rest.
    final skipPropagate = isStationary;

    if (!skipPropagate) {
      _ekf.predict(
        vehicleAccel: aVeh,
        vehicleGyro: wVeh,
        dt: dt,
        qInflation: qInflation,
        vTcn: effectiveSpeed,
        wv: _vibrationGate.trustWeight,
        tcnVariance: _tcnSpeed.estimatedVariance,
        vehicleSpecificForce: fVeh,
      );
    }
    // Apply vehicle Non-Holonomic Constraints (NHC) only in vehicle driving mode.
    // When pedestrian mode is active, human movement is holonomic (sidestepping, turning in place).
    if (!isPedestrian) {
      _ekf.applyNhc();
    }
    _ekf.updateTcnSpeed(effectiveSpeed, variance: _tcnSpeed.estimatedVariance);

    // Turn Velocity Update: reinforce forward velocity with centripetal speed during curve negotiation
    if (_turnDetector.isTurning && _tcnSpeed.centripetalSpeed != null && !isPedestrian && !isStationary) {
      _ekf.updateTurnVelocity(_tcnSpeed.centripetalSpeed!, variance: 0.35);
    }

    // Straight-Line Zero Angular Rate Update (ZARU):
    // When driving straight on highways at speed without turning, continuously calibrate gyro z-bias in real time
    if (!isPedestrian && !isStationary && effectiveSpeed >= 8.0 && !_turnDetector.isTurning && wVeh.z.abs() < 0.015 && aVeh.y.abs() < 0.25) {
      _ekf.applyZaru(wVeh.z, dt);
    }

    // Cruising Zero Acceleration Update (ZACU):
    // When cruising straight at high speed with low longitudinal variance, calibrate forward accelerometer bias
    if (!isPedestrian && !isStationary && effectiveSpeed >= 10.0 && !_turnDetector.isTurning && wVeh.z.abs() < 0.015 && aVeh.x.abs() < 0.20 && aVeh.y.abs() < 0.20) {
      _ekf.applyZacu(aVeh.x, dt);
    }

    if (baro != null) {
      _lastBaroPressureHpa = baro.pressureHpa;
      final alt = (_calibratedP0 != 1013.25 && baro.pressureHpa > 0.0)
          ? MathUtils.altitudeFromCalibratedPressure(baro.pressureHpa, _calibratedP0)
          : baro.altitude;
      _baroAltHistory.add(alt);
      if (_baroAltHistory.length > 5) _baroAltHistory.removeAt(0);
      _ekf.updateBarometer(alt);
      if (_baroAltHistory.length >= 3) {
        final climbRate = MathUtils.savitzkyGolayDerivative5Scalar(_baroAltHistory, dt);
        _ekf.updateBaroClimbRate(climbRate);
      }
    }

    if (gnss != null) {
      _ekf.updateGnss(
        gnssX: gnss.x,
        gnssY: gnss.y,
        gnssZ: gnss.z,
        hdop: gnss.hdop,
        isDenied: gnss.isDenied,
      );
      if (!gnss.isDenied) {
        if (_turnDetector.isTurning && gnss.speed > 3.0) {
          _ekf.adaptMountLeverArm(
            measuredLatAccel: aVeh.y,
            yawRate: wVeh.z,
            gnssSpeed: gnss.speed,
            dt: dt,
          );
        }
        if (gnss.speed > 0.8 && gnss.hdop <= 4.0) {
          final courseEnuRad = MathUtils.compassToEnuRad(gnss.heading);
          final vEast = gnss.speed * math.cos(courseEnuRad);
          final vNorth = gnss.speed * math.sin(courseEnuRad);
          _ekf.updateGnssVelocityVector(
            vEast: vEast,
            vNorth: vNorth,
            hdop: gnss.hdop,
            isDenied: false,
          );
        } else {
          _ekf.updateGnssSpeed(gnss.speed, gnss.hdop);
        }
      }
      _tcnSpeed.synchronizeGnssSpeed(gnss.speed, gnss.hdop);

      if (!gnss.isDenied && gnss.speed > 1.2 && gnss.hdop <= 3.0) {
        final courseEnuRad = MathUtils.compassToEnuRad(gnss.heading);
        _ekf.updateCourse(courseEnuRad, gnss.speed, hdop: gnss.hdop);
      }
    }

    // Determine GNSS status — in live mode, use stored async GNSS state
    final currentHdop = _liveGnssHdop;
    final isDenied = (_liveGnssDenied || _forceTunnelOutage);
    if (isDenied) {
      _tcnSpeed.clearGnssForceStandstill();
    }
    GnssStatus status = GnssStatus.available;
    if (isDenied || !_liveGnssActive) {
      status = GnssStatus.denied;
    } else if (currentHdop > 2.5) {
      status = GnssStatus.degraded;
    }

    final isGnssNominal = !isDenied && currentHdop <= 5.0 && _liveGnssActive;

    // 5. Module 5: Smart 3D Map-Matching Filter (OSM Offline Road Network Constraint)
    // Snaps drifting EKF trajectory onto the road centerline using clamped orthogonal projection
    // with 3D elevation and heading disambiguation (preventing false snap onto flyovers or service roads).
    // Bypassed during pedestrian mode so walking users are not dragged into vehicular highway lanes.
    MapSnapResult? match;
    final shouldApplyMapSnap = !isPedestrian;
    final currentIdrPos = _ekf.state.position;

    if (shouldApplyMapSnap) {
      final effectiveHdop = isDenied ? 25.0 : currentHdop;
      match = _mapSnapper.snapWithHeading(
        _ekf.state.position,
        _ekf.state.yaw,
        hdop: effectiveHdop,
        vTcn: effectiveSpeed,
        tcnVariance: _tcnSpeed.estimatedVariance,
      );

      if (match != null) {
        final sigmaMap = _mapSnapper.lateralSigma(effectiveHdop, match);
        final laneDb = _mapSnapper.laneDeadband(match);
        _ekf.updateMapMatchingIterated(
          normal2D: match.normal2D,
          crossTrackDistance: match.crossTrackDistance,
          sigma: sigmaMap,
          roadElevation: match.snappedPoint.z,
          laneDeadbandM: laneDb,
        );

        // Heading Drift Protection: constrain gyro heading to road azimuth during GNSS outage
        if (isDenied) {
          _ekf.updateMapHeading(match.roadHeadingRad, match.confidence);
        }
      }
    }

    // Feed updates into Pure C++ engine when available
    if (_nativeBridge.isAvailable) {
      _nativeBridge.setPedestrianMode(isPedestrian);
      _nativeBridge.setOutage(isDenied);
      _nativeBridge.updateTcnSpeed(effectiveSpeed, _tcnSpeed.estimatedVariance);
      _nativeBridge.processImu(imu);
      if (baro != null) _nativeBridge.processBaro(baro);

      if (shouldApplyMapSnap && match != null) {
        final effectiveHdop = isDenied ? 25.0 : currentHdop;
        final sigmaMap = _mapSnapper.lateralSigma(effectiveHdop, match);
        _nativeBridge.updateMapMatching(
          normal2D: match.normal2D,
          crossTrackDistance: match.crossTrackDistance,
          sigma: sigmaMap,
          roadElevation: match.snappedPoint.z,
        );
        if (isDenied) {
          _nativeBridge.updateMapHeading(match.roadHeadingRad, match.confidence);
        }
      }
    }



    // 6. Module 6: Classic Double-Integration Baseline
    // While GNSS is nominal, anchor Classic DR to true/IDR navigation state.
    // Unassisted open-loop double integration begins accumulating ONLY when GNSS is denied or in a tunnel!
    if (isGnssNominal) {
      _classicDr.syncWithGnss(
        position: _ekf.state.position,
        velocity: _ekf.state.velocity,
        yaw: _ekf.state.yaw,
      );
    } else if (isStationary) {
      // Freeze velocity to zero during standstill so stationary sensor noise doesn't accumulate
      _classicDr.syncWithGnss(
        position: _classicDr.state.position,
        velocity: Vec3.zero,
        yaw: _classicDr.state.yaw,
      );
    } else {
      _classicDr.step(
        vehicleAccel: aVeh,
        vehicleGyro: wVeh,
        dt: dt,
      );
    }

    // Trajectory recordings (keep latest points)
    final currentClassicPos = _classicDr.state.position;

    // Accumulate outage distance and duration metrics for live drift counter
    if (isDenied) {
      _drOutageDurationSec += dt;
      if (_lastDrPos != null && !isStationary) {
        _drDistanceTraveled += (currentIdrPos - _lastDrPos!).norm;
      }
      _lastDrPos = currentIdrPos;
      _outageTrajectoryStartIndex ??= idrTrajectory.length;
    } else {
      // Re-acquisition event: if we just emerged from an outage, backward-smooth the recorded outage points!
      if (_outageTrajectoryStartIndex != null && _outageTrajectoryStartIndex! < idrTrajectory.length - 1) {
        final terminalCorrection = currentIdrPos - idrTrajectory.last;
        if (terminalCorrection.norm > 0.5 && terminalCorrection.norm < 120.0) {
          final smoothed = MathUtils.smoothOutageTrajectory(
            trajectory: idrTrajectory,
            outageStartIndex: _outageTrajectoryStartIndex!,
            terminalCorrection: terminalCorrection,
          );
          idrTrajectory.clear();
          idrTrajectory.addAll(smoothed);
        }
      }
      _outageTrajectoryStartIndex = null;
      _drOutageDurationSec = 0.0;
      _drDistanceTraveled = 0.0;
      _lastDrPos = null;
    }

    if (idrTrajectory.isEmpty || (currentIdrPos - idrTrajectory.last).normSquared > 0.3) {
      idrTrajectory.add(currentIdrPos);
      classicTrajectory.add(currentClassicPos);
      if (gtPos != null) {
        groundTruthTrajectory.add(gtPos);
      }
      if (idrTrajectory.length > maxHistoryPoints) {
        idrTrajectory.removeAt(0);
        classicTrajectory.removeAt(0);
        if (groundTruthTrajectory.isNotEmpty) {
          groundTruthTrajectory.removeAt(0);
        }
      }
    }

    // Compute error metrics
    final refPoint = gtPos ?? currentIdrPos;
    final idrError = (currentIdrPos - refPoint).norm;
    final classicError = isGnssNominal ? 0.0 : (currentClassicPos - refPoint).norm;

    final reportedGnssSpeed = isDenied ? null : _latestGnssSpeed;

    double? solLat = _latestLatitude;
    double? solLon = _latestLongitude;
    if (_liveGnssActive && !isDenied && _latestLatitude != null && _latestLongitude != null) {
      // GPS is locked — use raw receiver coordinates directly (most accurate)
      solLat = _latestLatitude;
      solLon = _latestLongitude;
    } else if (_sensorService.refLat != null && _sensorService.refLon != null) {
      // GNSS denied / dead reckoning — exact WGS84 ellipsoidal inverse geodesy
      final wgs = MathUtils.enuToWgs84(
        enu: currentIdrPos,
        refLat: _sensorService.refLat!,
        refLon: _sensorService.refLon!,
        refAlt: _sensorService.refAlt ?? 0.0,
      );
      solLat = wgs.latitude;
      solLon = wgs.longitude;
    }

    if (solLat != null && solLon != null) {
      _dynamicMapService.onLocationUpdate(solLat, solLon, this);
    }

    // Real-Time Turn-by-Turn Navigation Progress Tracking
    if (_navigationService.isNavigating) {
      _navigationService.updateVehicleProgress(currentIdrPos, MathUtils.enuToCompassDeg(_ekf.state.yaw), this);
    }

    NavSolution? nativeSol;
    if (_nativeBridge.isAvailable) {
      nativeSol = _nativeBridge.getNavSolution(
        groundTruthPos: gtPos,
        groundTruthSpeed: gtSpeed,
        gnssSpeed: reportedGnssSpeed,
        drDistanceTraveled: _drDistanceTraveled,
        drOutageDurationSec: _drOutageDurationSec,
        isTcnModelLoaded: _tcnSpeed.isModelLoaded,
        isMapMatched: match != null,
        matchedRoadName: match?.branchName,
        crossTrackMeters: match?.crossTrackDistance ?? 0.0,
        latitude: solLat,
        longitude: solLon,
        accuracyMeters: _latestAccuracyMeters ?? _sensorService.lastKnownPosition?.accuracy,
        gpsStatusMessage: _latestGpsMessage ?? _sensorService.lastGpsMessage,
      );
    }

    _latestSolution = nativeSol ?? NavSolution(
      timestamp: imu.timestamp,
      idrState: _ekf.state,
      classicDrState: _classicDr.state,
      groundTruthPos: gtPos,
      groundTruthSpeed: gtSpeed,
      gnssStatus: status,
      hdop: currentHdop,
      isGnssDenied: isDenied,
      idrDriftError: idrError,
      classicDriftError: classicError,
      shockDetected: isShock,
      rawJerk: _vibrationGate.lastRawJerk,
      jerkVariance: _vibrationGate.lastVariance,
      tcnEstimatedSpeed: vTcn,
      baroAltitude: baro?.altitude ?? _ekf.state.pz,
      cabinConfidence: _aligner.confidence,
      isCabinLocked: _aligner.isLocked,
      mountPitchDeg: _aligner.mountPitchDeg,
      mountRollDeg: _aligner.mountRollDeg,
      isPedestrian: isPedestrian,
      tcnVariance: _tcnSpeed.estimatedVariance,
      roadCondition: _vibrationGate.roadConditionString,
      isMapMatched: match != null,
      matchedRoadName: match?.branchName,
      crossTrackMeters: match?.crossTrackDistance ?? 0.0,
      gnssSpeed: reportedGnssSpeed,
      drDistanceTraveled: _drDistanceTraveled,
      drOutageDurationSec: _drOutageDurationSec,
      isTcnModelLoaded: _tcnSpeed.isModelLoaded,
      latitude: solLat,
      longitude: solLon,
      accuracyMeters: _latestAccuracyMeters ?? _sensorService.lastKnownPosition?.accuracy,
      gpsStatusMessage: _latestGpsMessage ?? _sensorService.lastGpsMessage,
    );

    // Smoothly notify listeners for dead-reckoned position updates at ~30 FPS
    _throttledNotifyListeners();
  }

  bool _isDisposed = false;

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _isRunning = false;
    _imuSub?.cancel();
    _gnssSub?.cancel();
    _baroSub?.cancel();
    _magSub?.cancel();
    _gpsStatusSub?.cancel();
    _imuSub = null;
    _gnssSub = null;
    _baroSub = null;
    _magSub = null;
    _gpsStatusSub = null;
    _navigationService.removeListener(notifyListeners);
    _timer?.cancel();
    _sensorService.dispose();
    super.dispose();
  }
}
