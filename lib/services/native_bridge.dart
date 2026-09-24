import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import '../core/math_utils.dart';
import '../models/ekf_state.dart';
import '../models/nav_solution.dart';
import '../models/sensor_data.dart';

/// C-compatible representation of NavSolution matching idr/c_api.h
final class IdrNavSolutionC extends Struct {
  @Double()
  external double timestamp;
  @Double()
  external double px;
  @Double()
  external double py;
  @Double()
  external double pz;
  @Double()
  external double vx;
  @Double()
  external double vy;
  @Double()
  external double vz;
  @Double()
  external double yawRad;
  @Double()
  external double headingDeg;
  @Double()
  external double rollRad;
  @Double()
  external double pitchRad;
  @Double()
  external double positionStd;
  @Double()
  external double hdop;
  @Double()
  external double trustWeight;
  @Int32()
  external int isShock;
  @Int32()
  external int isStandstill;
  @Int32()
  external int isOutage;
  @Double()
  external double idrDrift;
  @Double()
  external double classicDrift;

  // Extended diagnostics
  @Double()
  external double gyroBiasZ;
  @Double()
  external double accelBiasX;
  @Double()
  external double forwardSpeed;
  @Double()
  external double climbRate;
  @Double()
  external double cabinConfidence;
  @Int32()
  external int isCabinLocked;
  @Int32()
  external int isPedestrian;
  @Double()
  external double rawJerk;
  @Double()
  external double jerkVariance;
  @Double()
  external double covPxx;
  @Double()
  external double covPyy;
  @Double()
  external double covPzz;
  @Double()
  external double covPyaw;
  @Double()
  external double covPvfwd;
  @Double()
  external double covPvz;
}

// C function types
typedef _CreateNative = Pointer<Void> Function();
typedef _DestroyNative = Void Function(Pointer<Void>);
typedef _ResetNative = Void Function(Pointer<Void>);
typedef _ProcessImuNative = Void Function(
    Pointer<Void>, Double, Double, Double, Double, Double, Double, Double);
typedef _ProcessGnssNative = Void Function(
    Pointer<Void>, Double, Double, Double, Double, Double, Double, Double);
typedef _ProcessBaroNative = Void Function(Pointer<Void>, Double, Double);
typedef _ProcessMagNative = Void Function(
    Pointer<Void>, Double, Double, Double, Double, Double);
typedef _UpdateMapMatchingNative = Void Function(
    Pointer<Void>, Double, Double, Double, Double, Double);
typedef _UpdateMapHeadingNative = Void Function(
    Pointer<Void>, Double, Double);
typedef _UpdateTcnSpeedNative = Void Function(
    Pointer<Void>, Double, Double);
typedef _SetPedestrianModeNative = Void Function(Pointer<Void>, Int32);
typedef _IsPedestrianNative = Int32 Function(Pointer<Void>);
typedef _SetReferenceAnchorNative = Void Function(
    Pointer<Void>, Double, Double, Double);
typedef _SyncGnssSpeedNative = Void Function(
    Pointer<Void>, Double, Double, Int32);
typedef _SetOutageNative = Void Function(Pointer<Void>, Int32);
typedef _ToggleOutageNative = Void Function(Pointer<Void>);
typedef _IsOutageNative = Int32 Function(Pointer<Void>);
typedef _GetSolutionNative = Void Function(
    Pointer<Void>, Pointer<IdrNavSolutionC>);

// Dart function signatures
typedef _CreateDart = Pointer<Void> Function();
typedef _DestroyDart = void Function(Pointer<Void>);
typedef _ResetDart = void Function(Pointer<Void>);
typedef _ProcessImuDart = void Function(
    Pointer<Void>, double, double, double, double, double, double, double);
typedef _ProcessGnssDart = void Function(
    Pointer<Void>, double, double, double, double, double, double, double);
typedef _ProcessBaroDart = void Function(Pointer<Void>, double, double);
typedef _ProcessMagDart = void Function(
    Pointer<Void>, double, double, double, double, double);
typedef _UpdateMapMatchingDart = void Function(
    Pointer<Void>, double, double, double, double, double);
typedef _UpdateMapHeadingDart = void Function(
    Pointer<Void>, double, double);
typedef _UpdateTcnSpeedDart = void Function(
    Pointer<Void>, double, double);
typedef _SetPedestrianModeDart = void Function(Pointer<Void>, int);
typedef _IsPedestrianDart = int Function(Pointer<Void>);
typedef _SetReferenceAnchorDart = void Function(
    Pointer<Void>, double, double, double);
typedef _SyncGnssSpeedDart = void Function(
    Pointer<Void>, double, double, int);
typedef _SetOutageDart = void Function(Pointer<Void>, int);
typedef _ToggleOutageDart = void Function(Pointer<Void>);
typedef _IsOutageDart = int Function(Pointer<Void>);
typedef _GetSolutionDart = void Function(
    Pointer<Void>, Pointer<IdrNavSolutionC>);

/// High-Performance C++ Math Engine FFI Bridge for Intelligent Dead Reckoning.
///
/// Dispatches 100 Hz IMU kinematic updates, 6-State 3D EKF matrix operations,
/// NHC constraints, ZUPT standstill detection, vibration gating, and baseline DR
/// directly into the native C++ library with Eigen SIMD acceleration.
class NativeBridge {
  static NativeBridge? _instance;
  static NativeBridge get instance => _instance ??= NativeBridge._();

  DynamicLibrary? _dylib;
  Pointer<Void>? _pipelineHandle;
  Pointer<IdrNavSolutionC>? _solutionBuffer;
  bool _isAvailable = false;

  late _CreateDart _create;
  late _DestroyDart _destroy;
  late _ResetDart _reset;
  late _ProcessImuDart _processImu;
  late _ProcessGnssDart _processGnss;
  late _ProcessBaroDart _processBaro;
  late _ProcessMagDart _processMag;
  late _UpdateMapMatchingDart _updateMapMatching;
  late _UpdateMapHeadingDart _updateMapHeading;
  late _UpdateTcnSpeedDart _updateTcnSpeed;
  late _SetPedestrianModeDart _setPedestrianMode;
  late _IsPedestrianDart _isPedestrian;
  late _SetReferenceAnchorDart _setReferenceAnchor;
  late _SyncGnssSpeedDart _syncGnssSpeed;
  late _SetOutageDart _setOutage;
  late _ToggleOutageDart _toggleOutage;
  late _IsOutageDart _isOutage;
  late _GetSolutionDart _getSolution;

  bool get isAvailable => _isAvailable;

  NativeBridge._() {
    _initDylib();
  }

  void _initDylib() {
    try {
      if (Platform.isAndroid) {
        _dylib = DynamicLibrary.open('libidr_core.so');
      } else if (Platform.isWindows) {
        try {
          _dylib = DynamicLibrary.open('idr_core.dll');
        } catch (_) {
          _dylib = DynamicLibrary.process();
        }
      } else if (Platform.isLinux) {
        _dylib = DynamicLibrary.open('libidr_core.so');
      } else if (Platform.isMacOS || Platform.isIOS) {
        _dylib = DynamicLibrary.process();
      }

      if (_dylib != null) {
        _create = _dylib!
            .lookup<NativeFunction<_CreateNative>>('idr_pipeline_create')
            .asFunction();
        _destroy = _dylib!
            .lookup<NativeFunction<_DestroyNative>>('idr_pipeline_destroy')
            .asFunction();
        _reset = _dylib!
            .lookup<NativeFunction<_ResetNative>>('idr_pipeline_reset')
            .asFunction();
        _processImu = _dylib!
            .lookup<NativeFunction<_ProcessImuNative>>('idr_pipeline_process_imu')
            .asFunction();
        _processGnss = _dylib!
            .lookup<NativeFunction<_ProcessGnssNative>>('idr_pipeline_process_gnss')
            .asFunction();
        _processBaro = _dylib!
            .lookup<NativeFunction<_ProcessBaroNative>>('idr_pipeline_process_baro')
            .asFunction();
        _processMag = _dylib!
            .lookup<NativeFunction<_ProcessMagNative>>('idr_pipeline_process_mag')
            .asFunction();
        _updateMapMatching = _dylib!
            .lookup<NativeFunction<_UpdateMapMatchingNative>>(
                'idr_pipeline_update_map_matching')
            .asFunction();
        _updateMapHeading = _dylib!
            .lookup<NativeFunction<_UpdateMapHeadingNative>>(
                'idr_pipeline_update_map_heading')
            .asFunction();
        _updateTcnSpeed = _dylib!
            .lookup<NativeFunction<_UpdateTcnSpeedNative>>(
                'idr_pipeline_update_tcn_speed')
            .asFunction();
        _setPedestrianMode = _dylib!
            .lookup<NativeFunction<_SetPedestrianModeNative>>(
                'idr_pipeline_set_pedestrian_mode')
            .asFunction();
        _isPedestrian = _dylib!
            .lookup<NativeFunction<_IsPedestrianNative>>(
                'idr_pipeline_is_pedestrian')
            .asFunction();
        _setReferenceAnchor = _dylib!
            .lookup<NativeFunction<_SetReferenceAnchorNative>>(
                'idr_pipeline_set_reference_anchor')
            .asFunction();
        _syncGnssSpeed = _dylib!
            .lookup<NativeFunction<_SyncGnssSpeedNative>>(
                'idr_pipeline_sync_gnss_speed')
            .asFunction();
        _setOutage = _dylib!
            .lookup<NativeFunction<_SetOutageNative>>('idr_pipeline_set_outage')
            .asFunction();
        _toggleOutage = _dylib!
            .lookup<NativeFunction<_ToggleOutageNative>>(
                'idr_pipeline_toggle_outage')
            .asFunction();
        _isOutage = _dylib!
            .lookup<NativeFunction<_IsOutageNative>>('idr_pipeline_is_outage')
            .asFunction();
        _getSolution = _dylib!
            .lookup<NativeFunction<_GetSolutionNative>>(
                'idr_pipeline_get_solution')
            .asFunction();

        _pipelineHandle = _create();
        _solutionBuffer = calloc<IdrNavSolutionC>();
        _isAvailable = true;
        debugPrint('[NativeBridge] Pure C++ IDR Core engine initialized successfully via FFI.');
      }
    } catch (e) {
      debugPrint('[NativeBridge] Native C++ library not available in this environment: $e');
      _isAvailable = false;
    }
  }

  void reset() {
    if (_isAvailable && _pipelineHandle != null) {
      _reset(_pipelineHandle!);
    }
  }

  void processImu(ImuSample sample) {
    if (!_isAvailable || _pipelineHandle == null) return;
    _processImu(
      _pipelineHandle!,
      sample.timestamp,
      sample.accel.x,
      sample.accel.y,
      sample.accel.z,
      sample.gyro.x,
      sample.gyro.y,
      sample.gyro.z,
    );
  }

  void processGnss(GnssSample sample) {
    if (!_isAvailable || _pipelineHandle == null) return;
    _processGnss(
      _pipelineHandle!,
      sample.timestamp,
      sample.latitude,
      sample.longitude,
      sample.altitude,
      sample.hdop,
      sample.speed,
      sample.heading,
    );
  }

  void processBaro(BaroSample sample) {
    if (!_isAvailable || _pipelineHandle == null) return;
    _processBaro(_pipelineHandle!, sample.timestamp, sample.pressureHpa);
  }

  void processMag(MagSample sample) {
    if (!_isAvailable || _pipelineHandle == null) return;
    _processMag(
      _pipelineHandle!,
      sample.timestamp,
      sample.magneticField.x,
      sample.magneticField.y,
      sample.magneticField.z,
      sample.headingDeg,
    );
  }

  void updateMapMatching({
    required Vec3 normal2D,
    required double crossTrackDistance,
    required double sigma,
    double roadElevation = -9999.0,
  }) {
    if (!_isAvailable || _pipelineHandle == null) return;
    _updateMapMatching(
      _pipelineHandle!,
      normal2D.x,
      normal2D.y,
      crossTrackDistance,
      sigma,
      roadElevation,
    );
  }

  void updateMapHeading(double roadHeadingRad, double confidence) {
    if (!_isAvailable || _pipelineHandle == null) return;
    _updateMapHeading(_pipelineHandle!, roadHeadingRad, confidence);
  }

  void updateTcnSpeed(double speedMps, double variance) {
    if (!_isAvailable || _pipelineHandle == null) return;
    _updateTcnSpeed(_pipelineHandle!, speedMps, variance);
  }

  void setPedestrianMode(bool isPedestrian) {
    if (!_isAvailable || _pipelineHandle == null) return;
    _setPedestrianMode(_pipelineHandle!, isPedestrian ? 1 : 0);
  }

  bool isPedestrian() {
    if (!_isAvailable || _pipelineHandle == null) return false;
    return _isPedestrian(_pipelineHandle!) != 0;
  }

  void setReferenceAnchor(double lat, double lon, double alt) {
    if (!_isAvailable || _pipelineHandle == null) return;
    _setReferenceAnchor(_pipelineHandle!, lat, lon, alt);
  }

  void syncGnssSpeed(double speedMps, double hdop, bool isDenied) {
    if (!_isAvailable || _pipelineHandle == null) return;
    _syncGnssSpeed(_pipelineHandle!, speedMps, hdop, isDenied ? 1 : 0);
  }

  void setOutage(bool outage) {
    if (!_isAvailable || _pipelineHandle == null) return;
    _setOutage(_pipelineHandle!, outage ? 1 : 0);
  }

  void toggleOutage() {
    if (!_isAvailable || _pipelineHandle == null) return;
    _toggleOutage(_pipelineHandle!);
  }

  bool isOutage() {
    if (!_isAvailable || _pipelineHandle == null) return false;
    return _isOutage(_pipelineHandle!) != 0;
  }

  /// Read the latest native navigation state snapshot from C++
  IdrNavSolutionC? getRawSolution() {
    if (!_isAvailable || _pipelineHandle == null || _solutionBuffer == null) {
      return null;
    }
    _getSolution(_pipelineHandle!, _solutionBuffer!);
    return _solutionBuffer!.ref;
  }

  /// Convert C++ solution into a full NavSolution Dart object
  NavSolution? getNavSolution({
    Vec3? groundTruthPos,
    double? groundTruthSpeed,
    double? gnssSpeed,
    double drDistanceTraveled = 0.0,
    double drOutageDurationSec = 0.0,
    bool isTcnModelLoaded = false,
    bool isMapMatched = false,
    String? matchedRoadName,
    double crossTrackMeters = 0.0,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
    String? gpsStatusMessage,
  }) {
    final raw = getRawSolution();
    if (raw == null) return null;

    final cov = List<double>.filled(81, 0.0);
    cov[0 * 9 + 0] = raw.covPxx;
    cov[1 * 9 + 1] = raw.covPyy;
    cov[2 * 9 + 2] = raw.covPzz;
    cov[3 * 9 + 3] = raw.covPvfwd;
    cov[4 * 9 + 4] = raw.covPvfwd;
    cov[5 * 9 + 5] = raw.covPvz;
    cov[6 * 9 + 6] = 0.001;
    cov[7 * 9 + 7] = 0.001;
    cov[8 * 9 + 8] = raw.covPyaw;

    final idrState = EkfState(
      position: Vec3(raw.px, raw.py, raw.pz),
      velocity: Vec3(raw.vx, raw.vy, raw.vz),
      attitude: Vec3(raw.rollRad, raw.pitchRad, raw.yawRad),
      covariance: cov,
    );

    // Classic DR state (dead reckoning velocity / pos)
    final classicDrState = EkfState(
      position: Vec3(raw.px - raw.idrDrift + raw.classicDrift, raw.py, raw.pz),
      velocity: Vec3(raw.vx, raw.vy, raw.vz),
      attitude: Vec3(raw.rollRad, raw.pitchRad, raw.yawRad),
      covariance: cov,
    );

    GnssStatus status = GnssStatus.available;
    if (raw.isOutage != 0) {
      status = GnssStatus.denied;
    } else if (raw.hdop > 2.5) {
      status = GnssStatus.degraded;
    }

    return NavSolution(
      timestamp: raw.timestamp,
      idrState: idrState,
      classicDrState: classicDrState,
      groundTruthPos: groundTruthPos,
      groundTruthSpeed: groundTruthSpeed,
      gnssStatus: status,
      hdop: raw.hdop,
      isGnssDenied: raw.isOutage != 0,
      idrDriftError: raw.idrDrift,
      classicDriftError: raw.classicDrift,
      shockDetected: raw.isShock != 0,
      rawJerk: raw.rawJerk,
      jerkVariance: raw.jerkVariance,
      tcnEstimatedSpeed: raw.forwardSpeed,
      baroAltitude: raw.pz,
      cabinConfidence: raw.cabinConfidence,
      isCabinLocked: raw.isCabinLocked != 0,
      mountPitchDeg: raw.pitchRad * 180.0 / math.pi,
      mountRollDeg: raw.rollRad * 180.0 / math.pi,
      isPedestrian: raw.isPedestrian != 0,
      tcnVariance: 0.05,
      roadCondition: raw.isShock != 0 ? 'ROUGH / SHOCK' : 'NORMAL',
      isMapMatched: isMapMatched,
      matchedRoadName: matchedRoadName,
      crossTrackMeters: crossTrackMeters,
      gnssSpeed: gnssSpeed,
      drDistanceTraveled: drDistanceTraveled,
      drOutageDurationSec: drOutageDurationSec,
      isTcnModelLoaded: isTcnModelLoaded,
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracyMeters,
      gpsStatusMessage: gpsStatusMessage,
    );
  }

  void dispose() {
    if (_solutionBuffer != null) {
      calloc.free(_solutionBuffer!);
      _solutionBuffer = null;
    }
    if (_isAvailable && _pipelineHandle != null) {
      _destroy(_pipelineHandle!);
      _pipelineHandle = null;
    }
    _isAvailable = false;
  }
}
