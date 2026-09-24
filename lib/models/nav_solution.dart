import 'ekf_state.dart';
import '../core/math_utils.dart';

enum GnssStatus {
  available,
  degraded,
  denied,
}

/// Consolidated navigation and telemetry solution frame for UI presentation.
class NavSolution {
  final double timestamp;
  final EkfState idrState;
  final EkfState classicDrState;
  final Vec3? groundTruthPos;
  final double? groundTruthSpeed;

  final GnssStatus gnssStatus;
  final double hdop;
  final bool isGnssDenied;

  final double idrDriftError; // meters relative to ground truth
  final double classicDriftError; // meters relative to ground truth

  final bool shockDetected; // Vibration gate active
  final double rawJerk; // m/s^3
  final double jerkVariance; // m^2/s^6
  final double tcnEstimatedSpeed; // m/s
  final double baroAltitude; // meters

  final double cabinConfidence; // 0..1
  final bool isCabinLocked;
  final double mountPitchDeg;
  final double mountRollDeg;

  final bool isPedestrian;
  final double tcnVariance;
  final String roadCondition;

  final bool isMapMatched;
  final String? matchedRoadName;
  final double crossTrackMeters;

  final double? gnssSpeed; // m/s from GNSS receiver
  final double drDistanceTraveled; // meters accumulated during active GNSS outage
  final double drOutageDurationSec; // elapsed seconds during active GNSS outage
  final bool isTcnModelLoaded; // whether ONNX model is actively running

  final double? latitude; // WGS-84 Latitude in degrees
  final double? longitude; // WGS-84 Longitude in degrees
  final double? accuracyMeters; // GPS fix accuracy radius in meters
  final String? gpsStatusMessage; // Diagnostic message (e.g. "Locked ±2.5m", "GPS Disabled")

  const NavSolution({
    required this.timestamp,
    required this.idrState,
    required this.classicDrState,
    this.groundTruthPos,
    this.groundTruthSpeed,
    required this.gnssStatus,
    required this.hdop,
    required this.isGnssDenied,
    required this.idrDriftError,
    required this.classicDriftError,
    required this.shockDetected,
    required this.rawJerk,
    required this.jerkVariance,
    required this.tcnEstimatedSpeed,
    required this.baroAltitude,
    required this.cabinConfidence,
    required this.isCabinLocked,
    required this.mountPitchDeg,
    required this.mountRollDeg,
    this.isPedestrian = false,
    this.tcnVariance = 0.16,
    this.roadCondition = 'NORMAL',
    this.isMapMatched = false,
    this.matchedRoadName,
    this.crossTrackMeters = 0.0,
    this.gnssSpeed,
    this.drDistanceTraveled = 0.0,
    this.drOutageDurationSec = 0.0,
    this.isTcnModelLoaded = false,
    this.latitude,
    this.longitude,
    this.accuracyMeters,
    this.gpsStatusMessage,
  });

  /// Master navigation speed in km/h.
  /// 1. Standstill / Zero Confirmed: returns 0.0.
  /// 2. Nominal GNSS: anchors to high-precision GNSS Doppler ground speed (0.05 m/s accuracy).
  /// 3. GNSS Denied / Dead Reckoning (tunnels): returns calibrated EKF forward velocity.
  double get speedKmh {
    // 1. Standstill confirmation: if EKF velocity is 0.0 or GNSS confirms stopped (< 0.5 m/s)
    if (idrState.speed == 0.0 || (gnssSpeed != null && gnssSpeed! < 0.5 && hdop <= 4.0)) {
      return 0.0;
    }

    // 2. High-precision GNSS Doppler speed during nominal reception
    if (!isGnssDenied && gnssSpeed != null && hdop <= 5.0) {
      final s = gnssSpeed! * 3.6;
      return s < 0.8 ? 0.0 : s;
    }

    // 3. Inertial Dead Reckoning during GNSS outage
    final s = idrState.speedKmh;
    return s < 0.8 ? 0.0 : s;
  }
  double get tcnSpeedKmh => tcnEstimatedSpeed * 3.6;
  double? get gnssSpeedKmh => gnssSpeed != null ? gnssSpeed! * 3.6 : null;

  /// Real-time drift percentage during GNSS outage: (idrDriftError / drDistanceTraveled) * 100
  double get drDriftPercent {
    if (drDistanceTraveled < 5.0) return 0.0;
    return (idrDriftError / drDistanceTraveled) * 100.0;
  }

  /// Navigational compass heading in degrees [0, 360): 0 = North, 90 = East, 180 = South, 270 = West.
  double get headingDeg => MathUtils.enuToCompassDeg(idrState.yaw);
}


