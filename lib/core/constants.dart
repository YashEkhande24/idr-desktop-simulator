/// IDR Navigation System Constants and Algorithmic Hyperparameters.
///
/// Defines physical constants, sensor sampling frequencies, EKF noise covariances,
/// Non-Holonomic Constraint (NHC) bounds, and Sigmoid HDOP gating parameters
/// according to the SIH 2026 technical whitepaper specification.
library;

class IdrConstants {
  // --- Sampling Rates ---
  static const double imuRateHz = 100.0;
  static const double dtImu = 1.0 / imuRateHz; // 0.01 s
  static const double baroRateHz = 10.0;
  static const double dtBaro = 1.0 / baroRateHz; // 0.1 s
  static const double gnssRateHz = 1.0;
  static const double dtGnss = 1.0 / gnssRateHz; // 1.0 s

  // --- Physical Constants ---
  static const double gravity = 9.80665; // m/s^2
  static const double p0SeaLevel = 1013.25; // hPa standard atmospheric pressure

  // --- Module 1: Cabin Alignment ---
  static const int alignmentSampleCount = 100; // 1 second at 100 Hz for gravity lock
  static const double alignmentConfidenceMin = 0.85;

  // --- Module 2: Kinetic Vibration Gate ---
  static const int jerkWindowSize = 25; // 25 samples = 250 ms window
  static const double jerkVarianceThreshold = 450.0; // m^2 / s^6 true shock trigger (potholes/speed bumps, aligned with native C++)
  static const double roughRoadVarianceThreshold = 80.0; // m^2 / s^6 continuous rough road threshold
  static const double jerkGateInflationFactor = 50.0; // Q-matrix inflation during violent shock
  static const double jerkReboundDurationSec = 0.35; // Recovery hold duration after pothole hit

  // --- Module 3: TCN Speed Engine / Fallback Estimator ---
  static const int tcnWindowSize = 40; // 40 samples (4.0s @ 10 Hz / 0.4s @ 100 Hz matching trained TCN)
  static const int tcnInChannels = 8; // [ax, ay, az, gx, gy, gz, ||a||, ||w||]
  static const double tcnSpeedScale = 25.0; // Speed target scaling factor from normalize_stats.json
  static const double zuptAccelThreshold = 0.35; // m/s^2 standstill variance threshold
  static const double zuptGyroThreshold = 0.08; // rad/s standstill gyro threshold
  static const double tcnSpeedNoiseStd = 0.40; // m/s measurement noise std
  static const double pedestrianMaxSpeed = 1.4; // m/s (~5 km/h maximum human walking pace)

  // --- Module 4: 15-State Error-State Kalman Filter (ESKF) ---
  // Process Noise (Q diagonal standard deviations)
  static const double qPosStd = 0.05; // m
  static const double qVelStd = 0.35; // m/s
  static const double qAttStd = 0.015; // rad (~0.85 deg)
  static const double qGyroBiasStd = 0.001; // rad/s IMU gyro bias drift
  static const double qAccelBiasStd = 0.005; // m/s^2 IMU accel bias drift

  // Non-Holonomic Constraints (NHC)
  static const double sigmaNhcLat2 = 0.05; // (m/s)^2 virtual lateral velocity variance
  static const double sigmaNhcVert2 = 0.02; // (m/s)^2 virtual vertical velocity variance

  // Barometer
  static const double baroNoiseStd = 1.2; // meters altitude variance std

  // Sigmoid HDOP GNSS Covariance Weighting
  // R_gnss(h) = R_nominal + [1 / (1 + exp(-k * (h - h0)))] * R_max
  static const double rNominalGnss = 4.0; // nominal variance (2m std)
  static const double rMaxGnss = 2500.0; // maximum variance during outage (50m std)
  static const double hdopThreshold = 2.5; // h0 inflection point
  static const double hdopSigmoidK = 2.0; // sharpness factor k

  // --- UI & Display ---
  static const int displayFps = 30;
  static const int oscilloscopeHistoryLength = 150;
}
