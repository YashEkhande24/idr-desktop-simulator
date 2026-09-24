import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import '../core/constants.dart';
import '../core/math_utils.dart';

/// Module 3: TCN Speed Engine & Intelligent Inertial Odometer
///
/// Upgraded to 8-Channel Architecture:
/// [ax, ay, az, gx, gy, gz, ||a||, ||w||] with a 40-step temporal window (4.0s context).
///
/// Implements:
/// 1. Real on-device ONNX Runtime Inference executing trained Dilated Causal SE-TCN.
/// 2. 8-Channel Rotation-Invariant Feature Ingestion matching trained TCN model.
/// 3. Standstill / Zero-Velocity Update (ZUPT) detector to eliminate rest drift.
/// 4. Biomechanical Pedestrian Cadence Detector:
///    Distinguishes cyclic 1.5-2.2 Hz human footstep heel strikes from smooth vehicle creep.
/// 5. Dual-Head Uncertainty Variance:
///    Outputs instantaneous speed v_hat and heteroscedastic variance sigma^2 for Kalman tuning.
/// 6. Decimated 10 Hz inference cadence with smooth inter-step kinematic continuity.
/// 7. Robust fallback to kinematic integration when model is not yet initialized.
class TcnSpeedEngine {
  // 8 Channels: [ax, ay, az, gx, gy, gz, ||a||, ||w||]
  final List<List<double>> _buffer = [];
  double _estimatedSpeed = 0.0;
  double _estimatedVariance = 0.16; // sigma^2 in (m/s)^2
  bool _isStationary = true;
  bool _isPedestrian = false;
  int _stationaryCounter = _stationaryHysteresis; // Fast 5-sample ZUPT lock (50ms)
  static const int _stationaryHysteresis = 5; // Fast 5-sample ZUPT lock (50ms)
  bool _gnssForceStandstill = false; // GNSS-confirmed zero-speed override
  double _launchKinematicSpeed = 0.0; // Integrated forward velocity during throttle launch from standstill
  double _pvSpeed = 0.25; // Continuous-discrete 1D speed variance observer

  bool _gnssConfirmedVehicle = false;  // Suppresses pedestrian mode when GNSS confirms vehicle speed

  // ONNX Runtime state
  OrtSession? _session;
  bool _modelLoaded = false;
  int _decimationCounter = 0;
  static const int _decimationFactor = 10; // 100 Hz input -> 10 Hz inference
  double _biasCorrection = 0.0; // Slowly learned GNSS speed bias
  double _rawInferredSpeed = 0.0;

  // Online Recursive Least Squares (RLS) Speed Calibration [scale, bias]
  double _rlsScale = 1.05; // Default 1.05 compensates for Huber loss compression
  double _rlsBias = 0.0;
  // 2x2 Covariance matrix for [scale, bias]
  double _p00 = 0.05, _p01 = 0.0, _p10 = 0.0, _p11 = 0.05;
  static const double _lambdaRls = 0.9995; // Forgetting factor

  // Exact normalization statistics from normalize_stats.json (8 channels)
  static const List<double> channelMeans = [
    -0.02365945093333721,
    -0.06469030678272247,
    0.012742034159600735,
    -4.271139914635569e-05,
    -0.005188114009797573,
    -0.0005354310269467533,
    1.8305089473724365,
    0.18634985387325287,
  ];

  static const List<double> channelStds = [
    1.6824091672897339,
    1.6449514627456665,
    0.733173131942749,
    0.1312127560377121,
    0.23679392039775848,
    0.11545656621456146,
    1.651694416999817,
    0.22786571085453033,
  ];

  static const double speedScale = 25.0;

  List<double> _channelMeans = List<double>.from(channelMeans);
  List<double> _channelStds = List<double>.from(channelStds);
  double _speedScale = speedScale;

  double _lastAccelVariance = 0.0;
  double _lastAvgW = 0.0;
  double _lastAvgYawRate = 0.0;
  double _restingFwdAccel = 0.0;
  double _lastSkogStatistic = 0.0;
  double? _lastCentripetalSpeed;
  double _prevGyroZ = 0.0;

  double get estimatedSpeed => _estimatedSpeed;
  double get estimatedVariance => _estimatedVariance;
  bool get isStationary => _isStationary;
  bool get isPedestrian => _isPedestrian;
  bool get isModelLoaded => _modelLoaded;
  double get biasCorrection => _biasCorrection;
  double get rlsScale => _rlsScale;
  double get rlsBias => _rlsBias;
  double get rawInferredSpeed => _rawInferredSpeed;
  double get lastAccelVariance => _lastAccelVariance;
  double get lastAvgW => _lastAvgW;
  double get lastAvgYawRate => _lastAvgYawRate;
  double get lastSkogStatistic => _lastSkogStatistic;
  double? get centripetalSpeed => _lastCentripetalSpeed;

  /// Loads the trained ONNX model from Flutter assets.
  Future<bool> loadModel([String assetPath = 'assets/models/vehicle_speed_tcn.onnx']) async {
    try {
      OrtEnv.instance.init();
      final sessionOptions = OrtSessionOptions();
      final rawAssetFile = await rootBundle.load(assetPath);
      final bytes = rawAssetFile.buffer.asUint8List(
        rawAssetFile.offsetInBytes,
        rawAssetFile.lengthInBytes,
      );
      _session = OrtSession.fromBuffer(bytes, sessionOptions);
      _modelLoaded = true;
      debugPrint('[TcnSpeedEngine] ONNX model successfully loaded: $assetPath (${_session?.inputNames})');

      // Dynamically sync normalization statistics from companion JSON
      try {
        final statsStr = await rootBundle.loadString('assets/models/normalize_stats.json');
        final Map<String, dynamic> stats = jsonDecode(statsStr);
        if (stats.containsKey('mean') && stats['mean'] is List) {
          _channelMeans = (stats['mean'] as List).map((e) => (e as num).toDouble()).toList();
        }
        if (stats.containsKey('std') && stats['std'] is List) {
          _channelStds = (stats['std'] as List).map((e) => (e as num).toDouble()).toList();
        }
        if (stats.containsKey('speed_scale')) {
          _speedScale = (stats['speed_scale'] as num).toDouble();
        }
        debugPrint('[TcnSpeedEngine] Normalization stats dynamically synced from JSON.');
      } catch (e) {
        debugPrint('[TcnSpeedEngine] Using compile-time normalization stats: $e');
      }

      return true;
    } catch (e) {
      debugPrint('[TcnSpeedEngine] ONNX model load warning (fallback active): $e');
      _modelLoaded = false;
      return false;
    }
  }

  /// Predict forward speed given vehicle-aligned acceleration and angular rate.
  /// [vehicleAccel]: [a_fwd, a_lat, a_vert] in m/s^2
  /// [vehicleGyro]: [w_roll, w_pitch, w_yaw] in rad/s
  /// [isShockGateActive]: boolean from VibrationGate
  /// [dt]: sample period in seconds
  double predict({
    required Vec3 vehicleAccel,
    required Vec3 vehicleGyro,
    required bool isShockGateActive,
    double dt = IdrConstants.dtImu,
    double pitchRad = 0.0,
    double rollRad = 0.0,
  }) {
    final ax = vehicleAccel.x;
    final ay = vehicleAccel.y;
    final az = vehicleAccel.z;
    final gx = vehicleGyro.x;
    final gy = vehicleGyro.y;
    final gz = vehicleGyro.z;

    // Compute orientation-invariant Euclidean norms (Channels 6 and 7)
    final normA = math.sqrt(ax * ax + ay * ay + az * az);
    final normW = math.sqrt(gx * gx + gy * gy + gz * gz);

    // Maintain 200-step sliding window (2.0s @ 100 Hz) for robust frequency analysis
    _buffer.add([ax, ay, az, gx, gy, gz, normA, normW]);
    if (_buffer.length > 200) {
      _buffer.removeAt(0);
    }

    final effectiveDt = MathUtils.clamp(dt, 0.001, 0.10);
    final angularAccelZ = (gz - _prevGyroZ) / effectiveDt;
    _prevGyroZ = gz;

    // Dynamic terrain slope pitch gravity compensation on forward acceleration
    final netFwdAccel = (pitchRad.abs() > 0.01)
        ? MathUtils.slopeCompensatedForwardAccel(measuredFwdAccel: ax, pitchRad: pitchRad)
        : ax;
    final fwdThrottle = netFwdAccel - _restingFwdAccel;

    // In-Cabin Phone Rotation vs Real Vehicle Turning:
    // Only active when vehicle is stationary or at low rest speed (< 0.50 m/s) and NOT accelerating forward.
    // Real vehicle launch has forward throttle (fwdThrottle > 0.20) with modest angular rate (normW < 0.40).
    final double nonYawRate = math.sqrt(gx * gx + gy * gy);
    // Hand rotation in cabin has NO rhythmic vertical footstep impact (|az| < 1.8)
    final bool hasVerticalImpact = az.abs() > 1.8;
    final bool isForwardPropulsion = fwdThrottle > 0.20 && normW < 0.40;
    final bool isPhoneRotatingInHand = !hasVerticalImpact &&
        !isForwardPropulsion &&
        (_isStationary || _estimatedSpeed < 0.50) &&
        (normW > 0.18 || nonYawRate > 0.15);

    // Kinematic launch integration: track forward acceleration delta above resting baseline.
    // Completely suppressed during in-cabin hand rotation to eliminate false launch integration.
    if (isPhoneRotatingInHand) {
      _launchKinematicSpeed = 0.0;
    } else if (fwdThrottle > 0.20) {
      _launchKinematicSpeed = MathUtils.clamp(
        _launchKinematicSpeed + fwdThrottle * effectiveDt,
        0.0,
        6.0,
      );
    } else if (fwdThrottle < -0.25) {
      _launchKinematicSpeed = math.max(0.0, _launchKinematicSpeed + fwdThrottle * effectiveDt);
    } else {
      _launchKinematicSpeed = math.max(0.0, _launchKinematicSpeed * (1.0 - 0.5 * effectiveDt));
    }

    // 1. Check Biomechanical Pedestrian Cadence vs. Vehicle Creep
    _checkPedestrianCadence();
    if (_isPedestrian) {
      _isStationary = false;
      _stationaryCounter = 0;
      // Clamped pedestrian pace (~1.0 to 1.3 m/s)
      _estimatedSpeed = math.min(IdrConstants.pedestrianMaxSpeed, math.max(0.5, normA * 0.4));
      _estimatedVariance = 0.8;
      return _estimatedSpeed;
    }

    // 2. Check Standstill / Zero-Velocity Condition (ZUPT)
    _checkStandstill(isPhoneRotatingInHand);
    if (_isStationary) {
      _estimatedSpeed = 0.0;
      _estimatedVariance = 0.05;
      _isPedestrian = false;
      _launchKinematicSpeed = 0.0;
      return 0.0;
    }

    // 3. Shock freeze: If a violent pothole or severe bump is actively detected,
    // freeze speed integration and elevate uncertainty variance.
    // Only freeze speed if the vehicle was already in motion (> 0.25 m/s);
    // do NOT block initial launch or permanently lock zero speed!
    if (isShockGateActive && (!_isStationary || _estimatedSpeed > 0.10)) {
      _estimatedVariance = 3.5; // Elevate variance so Kalman filter de-weights measurement
      return _estimatedSpeed;
    }

    // 4. ONNX Neural Network Inference (Primary AI Path)
    if (_modelLoaded && _session != null && _buffer.length >= IdrConstants.tcnWindowSize) {
      _decimationCounter++;
      final shouldInfer = (_decimationCounter >= _decimationFactor) || (dt >= 0.05);

      if (shouldInfer) {
        _decimationCounter = 0;
        try {
          final input = Float32List(8 * IdrConstants.tcnWindowSize);
          final startIndex = _buffer.length - IdrConstants.tcnWindowSize;
          for (int ch = 0; ch < 8; ch++) {
            final chMean = _channelMeans[ch];
            final chStd = _channelStds[ch];
            final chOffset = ch * IdrConstants.tcnWindowSize;
            for (int t = 0; t < IdrConstants.tcnWindowSize; t++) {
              input[chOffset + t] = (_buffer[startIndex + t][ch] - chMean) / chStd;
            }
          }

          final inputTensor = OrtValueTensor.createTensorWithDataList(
            input,
            [1, 8, IdrConstants.tcnWindowSize],
          );
          final runOptions = OrtRunOptions();
          final outputs = _session!.run(runOptions, {'imu_input': inputTensor});
          inputTensor.release();
          runOptions.release();

          if (outputs.isNotEmpty && outputs[0] != null) {
            final rawSpeed = _extractFirstDouble(outputs[0]!.value);
            _rawInferredSpeed = rawSpeed * _speedScale;
            var inferredSpeed = math.max(0.0, (_rawInferredSpeed * _rlsScale) + _rlsBias + _biasCorrection);

            // Autonomous Deadband & Engine Idle / Pure-Rotation Noise Rejection:
            // 1. Pure rotation in place: yaw rate without centripetal lateral acceleration
            //    (latAccel < 0.50 m/s^2) and low road travel variance (< 2.5 m^2/s^4) is a rotation on table/mount,
            //    NOT vehicle driving.
            final bool isPureRotationInPlace = (gz.abs() > 0.18 || _lastAvgYawRate > 0.18) &&
                ay.abs() < 0.50 &&
                _lastAccelVariance < 2.5;

            final double dynamicFwdLaunch = ax - _restingFwdAccel;

            if (_isStationary) {
              if (!isPhoneRotatingInHand && (dynamicFwdLaunch > 0.25 || _launchKinematicSpeed > 0.20)) {
                _isStationary = false;
                _gnssForceStandstill = false;
                _stationaryCounter = 0;
              }
            }

            if (isPureRotationInPlace || isPhoneRotatingInHand || _isStationary) {
              inferredSpeed = 0.0;
              _launchKinematicSpeed = 0.0;
            } else if (inferredSpeed < 0.25 && dynamicFwdLaunch <= 0.05 && _launchKinematicSpeed < 0.10) {
              // Soft continuous deadband: smooth sigmoid transition into standstill without truncating crawl
              final scale = 1.0 / (1.0 + math.exp(-25.0 * (inferredSpeed - 0.12)));
              inferredSpeed = inferredSpeed * scale;
            }

            // Combine TCN prediction with launch kinematic coupling for instant stop-and-go throttle response
            final double targetSpeed = _isStationary
                ? 0.0
                : math.max(inferredSpeed, _launchKinematicSpeed);

            if (outputs.length > 1 && outputs[1] != null) {
              final rawVar = _extractFirstDouble(outputs[1]!.value);
              _estimatedVariance = MathUtils.clamp(
                rawVar * (speedScale * speedScale),
                0.04,
                4.0,
              );
            }

            // Distance-preserving dynamic integration / 1D Gauss-Markov Kalman speed observer:
            // At 10 Hz dataset/sensor cadence (dt >= 0.05), track targetSpeed directly without artificial lag.
            // At 100 Hz sensor cadence (dt < 0.05), fuse continuous acceleration with discrete TCN inference.
            if (_estimatedSpeed == 0.0 || dt >= 0.05) {
              _estimatedSpeed = targetSpeed;
              _pvSpeed = _estimatedVariance;
            } else {
              final rTcn = _estimatedVariance;
              final kGain = _pvSpeed / (_pvSpeed + rTcn);
              _estimatedSpeed = MathUtils.clamp(_estimatedSpeed + kGain * (targetSpeed - _estimatedSpeed), 0.0, 60.0);
              _pvSpeed = (1.0 - kGain) * _pvSpeed;
            }

            if (_isStationary) {
              _estimatedSpeed = 0.0;
              _pvSpeed = 0.01;
            }
          }

          // Centripetal Acceleration Speed Estimation (CASE):
          // a_lat = v * omega_z during steady turning with mount lever-arm and road banking compensation
          if (!_isStationary && gz.abs() >= 0.08 && ay.abs() >= 0.35) {
            final vCent = MathUtils.centripetalTurnSpeed(
              measuredLatAccel: ay.abs(),
              yawRate: gz.abs(),
              angularAccel: angularAccelZ,
              roadBankAngleRad: rollRad,
            );
            if (vCent != null && vCent >= 0.8 && vCent <= 50.0) {
              _lastCentripetalSpeed = vCent;
            } else {
              _lastCentripetalSpeed = null;
            }
          } else {
            _lastCentripetalSpeed = null;
          }

          for (final o in outputs) {
            o?.release();
          }
          return _estimatedSpeed;
        } catch (e) {
          debugPrint('[TcnSpeedEngine] Runtime inference exception: $e');
        }
      } else {
        // Continuous inter-epoch kinematic speed propagation using forward accelerometer with slope compensation:
        if (!_isStationary && !_isPedestrian && effectiveDt < 0.05) {
          final aFwd = netFwdAccel - _restingFwdAccel;
          if (aFwd.abs() > 0.04) {
            _estimatedSpeed = math.max(0.0, _estimatedSpeed + aFwd * effectiveDt);
            _pvSpeed = MathUtils.clamp(_pvSpeed + 0.15 * effectiveDt, 0.01, 2.0);
          }
        }
        return _estimatedSpeed;
      }
    }

    // 5. Kinematic Speed & Variance Estimation Fallback (Used during startup/tests)
    // Longitudinal acceleration integration with bias deadband and friction damping
    var deltaV = netFwdAccel * effectiveDt;
    if (deltaV.abs() < 0.15 * effectiveDt) {
      deltaV = 0.0;
    }

    _estimatedSpeed += deltaV;

    // Natural vehicle aerodynamic and rolling friction damping when coasting
    if (netFwdAccel.abs() < 0.20 && _estimatedSpeed > 0.1) {
      _estimatedSpeed *= (1.0 - 0.01 * effectiveDt * 100.0);
    }

    // Wheeled vehicles on roads do not move in reverse during highway driving
    _estimatedSpeed = math.max(0.0, math.max(_estimatedSpeed, _launchKinematicSpeed));

    // Dynamic variance based on normalized motion energy
    final normStdA = (normA - channelMeans[6]) / channelStds[6];
    _estimatedVariance = MathUtils.clamp(0.12 + 0.05 * normStdA.abs(), 0.08, 2.0);

    // Centripetal Acceleration Speed Estimation (CASE) fallback:
    if (!_isStationary && gz.abs() >= 0.08 && ay.abs() >= 0.35) {
      final vCent = MathUtils.centripetalTurnSpeed(
        measuredLatAccel: ay.abs(),
        yawRate: gz.abs(),
        angularAccel: angularAccelZ,
        roadBankAngleRad: rollRad,
      );
      if (vCent != null && vCent >= 0.8 && vCent <= 50.0) {
        _lastCentripetalSpeed = vCent;
      } else {
        _lastCentripetalSpeed = null;
      }
    } else {
      _lastCentripetalSpeed = null;
    }

    return _estimatedSpeed;
  }

  /// Helper to safely extract a scalar double from possibly nested lists
  static double _extractFirstDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is List && value.isNotEmpty) {
      return _extractFirstDouble(value.first);
    }
    return 0.0;
  }

  /// Detects human walking cadence (inverted pendulum 1.5-2.3 Hz vertical bounce)
  /// while preserving slow car traffic creep and rejecting motorcycle/vehicle vibration.
  void _checkPedestrianCadence() {
    if (_buffer.length < 25) { // Need at least 25 samples for frequency analysis
      _isPedestrian = false;
      return;
    }

    // Reset vehicle confirmation when speed has dropped to near-zero (stopped/parked)
    if (_gnssConfirmedVehicle && _estimatedSpeed < 0.5) {
      _gnssConfirmedVehicle = false;
    }

    // GNSS-confirmed vehicle speed (> 2 m/s ~ 7.2 km/h) suppresses pedestrian mode
    if (_gnssConfirmedVehicle) {
      _isPedestrian = false;
      return;
    }

    // Use up to 200 samples (2.0 seconds) for cadence frequency detection
    final sub = _buffer;

    var maxZ = -100.0;
    var minZ = 100.0;
    var avgGyroNorm = 0.0;

    for (final sample in sub) {
      final z = sample[2];
      if (z > maxZ) maxZ = z;
      if (z < minZ) minZ = z;
      avgGyroNorm += sample[7]; // normW
    }
    avgGyroNorm /= sub.length;

    var meanZ = 0.0;
    for (final sample in sub) {
      meanZ += sample[2];
    }
    meanZ /= sub.length;

    // Fast frequency analysis: Count major vertical peaks in the 2.0s window using
    // zero-crossings with hysteresis (Schmidt trigger) to reject high-frequency micro-noise.
    // A walking human (1.5 - 2.5 Hz) will have exactly 3 to 5 steps (6 to 10 crossings) in 2 seconds.
    // A vibrating motorcycle engine or road bumps will have dozens of crossings.
    int crossings = 0;
    bool isAbove = sub[0][2] > meanZ;
    final hysteresis = 0.5; // Requires passing meanZ + 0.5 and meanZ - 0.5 to count
    final crossingIndices = <int>[];

    for (int i = 1; i < sub.length; i++) {
      final z = sub[i][2];
      if (isAbove && z < meanZ - hysteresis) {
        isAbove = false;
        crossings++;
        crossingIndices.add(i);
      } else if (!isAbove && z > meanZ + hysteresis) {
        isAbove = true;
        crossings++;
        crossingIndices.add(i);
      }
    }
    
    // Each full step cycle has 2 crossings (up and down)
    final peakCount = crossings ~/ 2;

    final verticalPeakToPeak = maxZ - minZ;
    
    // Strict biomechanical checks:
    // 1. Must have strong heel-strike impact (peak-to-peak >= 3.5 m/s^2)
    // 2. Must have pronounced walking sway (gyro >= 0.25 rad/s)
    // 3. Cadence MUST be between 1.0 Hz and 4.0 Hz (2 to 8 peaks in 2.0s)
    // 4. Cadence Periodicity Coherence: step intervals must be regular (human walking) rather than random noise
    bool isCadenceRegular = true;
    if (crossingIndices.length >= 4) {
      final intervals = <double>[];
      for (int k = 1; k < crossingIndices.length; k++) {
        intervals.add((crossingIndices[k] - crossingIndices[k - 1]).toDouble());
      }
      var sumInt = 0.0;
      for (final intv in intervals) {
        sumInt += intv;
      }
      final meanInt = sumInt / intervals.length;
      var varInt = 0.0;
      for (final intv in intervals) {
        final d = intv - meanInt;
        varInt += d * d;
      }
      final stdInt = math.sqrt(varInt / intervals.length);
      final cv = stdInt / (meanInt > 0 ? meanInt : 1.0);
      isCadenceRegular = cv < 0.65; // Human steps are periodic (CV < 0.65); random road noise is irregular
    }

    // 5. Vehicular Momentum Lock: A car cruising (> 2.5 m/s) cannot morph into a pedestrian
    final isVehicularSpeed = _estimatedSpeed > 2.5;

    final isImpactMatch = verticalPeakToPeak >= 3.5;
    final isBodyWiggle = avgGyroNorm >= 0.25;
    final isHumanCadence = (peakCount >= 2) && (peakCount <= 8);

    _isPedestrian = !isVehicularSpeed && isImpactMatch && isBodyWiggle && isHumanCadence && isCadenceRegular;
  }

  void _checkStandstill([bool isPhoneRotatingInHand = false]) {
    if (isPhoneRotatingInHand && _isStationary) {
      _stationaryCounter = _stationaryHysteresis;
      _launchKinematicSpeed = 0.0;
      _estimatedSpeed = 0.0;
      return;
    }

    if (_buffer.length < 8) {
      return;
    }

    final sub = _buffer.sublist(math.max(0, _buffer.length - 20));

    var meanX = 0.0;
    var meanY = 0.0;
    var meanZ = 0.0;
    var avgW = 0.0;
    var avgYawRate = 0.0;

    for (final sample in sub) {
      meanX += sample[0];
      meanY += sample[1];
      meanZ += sample[2];
      avgYawRate += sample[5].abs(); // vehicleGyro.z (yaw rate)
      avgW += sample[7]; // normW (total angular rate)
    }

    meanX /= sub.length;
    meanY /= sub.length;
    meanZ /= sub.length;
    avgYawRate /= sub.length;
    avgW /= sub.length;

    var varSum = 0.0;
    for (final sample in sub) {
      final dx = sample[0] - meanX;
      final dy = sample[1] - meanY;
      final dz = sample[2] - meanZ;
      varSum += (dx * dx + dy * dy + dz * dz);
    }
    _lastAccelVariance = varSum / sub.length;
    _lastAvgW = avgW;
    _lastAvgYawRate = avgYawRate;
    final fwdAccel = meanX.abs();
    final latAccel = meanY.abs();

    // 1. Skog Generalized Likelihood Ratio Test (GLRT) for standstill hypothesis:
    // T_GLRT = (1/N) * sum( ||a_i - mean_a||^2 / sigma_a^2 + ||w_i||^2 / sigma_w^2 )
    const sigmaA2 = 0.05; // (m/s^2)^2 nominal accelerometer variance
    const sigmaW2 = 0.01; // (rad/s)^2 nominal gyro variance
    var skogSum = 0.0;
    for (final sample in sub) {
      final dx = sample[0] - meanX;
      final dy = sample[1] - meanY;
      final dz = sample[2] - meanZ;
      final aNormSq = dx * dx + dy * dy + dz * dz;
      final wNormSq = sample[3] * sample[3] + sample[4] * sample[4] + sample[5] * sample[5];
      skogSum += (aNormSq / sigmaA2) + (wNormSq / sigmaW2);
    }
    _lastSkogStatistic = skogSum / sub.length;

    // 2. TCN-Augmented Centrifugal Kinematic Consistency:
    // a_lat = v * omega_z. Disambiguates phone table rotation from real vehicular curve.
    final expectedCentrifugalA = _estimatedSpeed * meanZ; // v * omega
    final centrifugalResidual = (meanY - expectedCentrifugalA).abs();
    final bool isCoupledTurn = (avgYawRate > 0.25 || avgW > 0.30) && (latAccel > 0.60 && centrifugalResidual < 2.5);

    // Adapt resting forward acceleration bias when vehicle is resting at idle or standstill
    // (captures phone mount tilt and road slope while angular velocity is steady)
    final double dynamicLaunchDelta = (meanX - _restingFwdAccel).abs();
    final double fwdThrottle = meanX - _restingFwdAccel;

    if (_isStationary && avgYawRate < 0.20 && !isCoupledTurn && dynamicLaunchDelta < 0.30) {
      _restingFwdAccel = _restingFwdAccel == 0.0 ? meanX : (_restingFwdAccel * 0.95 + meanX * 0.05);
      _launchKinematicSpeed = 0.0;
    }

    // Pure yaw rotation in place (e.g. rotating phone on a table or in a mount) has
    // yaw rate without centripetal lateral force (latAccel < 0.50) and low road variance (< 2.5).
    final bool isPureRotationInPlace = (avgYawRate > 0.18 || avgW > 0.18) &&
        latAccel < 0.50 &&
        _lastAccelVariance < 2.5;

    // Standstill condition (ZUPT):
    // In real vehicles at idle, phone on a table, or phone held stationary in hand:
    // Dynamic acceleration variance (< 2.5 m^2/s^4), no coupled turn, and absence of forward throttle launch.
    // Hand tremor produces physiological roll/pitch angular rates (avgW up to 0.30 rad/s), but yaw rate remains low (< 0.18)
    // without centripetal lateral force.
    final bool isSyntheticNoNoise = _lastAccelVariance < 1e-6;

    final isCurrentlyStill = isSyntheticNoNoise
        ? (fwdAccel < 0.15)
        : (isPureRotationInPlace ||
            isPhoneRotatingInHand ||
            ((_isStationary || _estimatedSpeed < 0.50) &&
                (_lastSkogStatistic < 25.0 || _lastAccelVariance < 2.5) &&
                (avgW < 0.30 || avgYawRate < 0.18) &&
                !isCoupledTurn &&
                dynamicLaunchDelta < 0.30 &&
                fwdThrottle < 0.25 &&
                _launchKinematicSpeed < 0.20));

    // Active physical vehicle motion breaks out of standstill:
    // In-cabin phone hand rotations or pure in-place swivel can NEVER break standstill.
    final double recent3Fwd = sub.length >= 3
        ? (sub[sub.length - 1][0] + sub[sub.length - 2][0] + sub[sub.length - 3][0]) / 3.0
        : sub.last[0];
    final double instantLaunchThrottle = recent3Fwd - _restingFwdAccel;

    final bool hasActiveMotion = isSyntheticNoNoise
        ? (fwdAccel >= 0.18)
        : (!isPureRotationInPlace &&
            !isPhoneRotatingInHand &&
            (instantLaunchThrottle > 0.40 ||
                fwdThrottle > 0.20 ||
                _launchKinematicSpeed > 0.18 ||
                (!_isStationary && _lastAccelVariance > 1.2 && _estimatedSpeed > 2.0) ||
                (!_isStationary && _lastAccelVariance > 2.5) ||
                isCoupledTurn ||
                (_lastSkogStatistic > 35.0 && (isCoupledTurn || fwdThrottle > 0.35))));

    if (_gnssForceStandstill && instantLaunchThrottle < 0.60 && _launchKinematicSpeed < 0.25) {
      _isStationary = true;
      _stationaryCounter = _stationaryHysteresis;
    } else if (hasActiveMotion) {
      _gnssForceStandstill = false;
      _stationaryCounter = 0;
      _isStationary = false;
    } else if (isCurrentlyStill) {
      _stationaryCounter = math.min(_stationaryCounter + 1, _stationaryHysteresis + 5);
      _isStationary = _stationaryCounter >= _stationaryHysteresis;
      if (_isStationary) {
        _launchKinematicSpeed = 0.0;
        _estimatedSpeed = 0.0;
      }
    } else {
      _stationaryCounter = math.max(0, _stationaryCounter - 2);
      if (_stationaryCounter == 0) {
        _isStationary = false;
      }
    }
  }

  /// Override / calibrate speed from GNSS fix when available and high confidence.
  void synchronizeGnssSpeed(double gnssSpeed, double hdop, {bool isDenied = false}) {
    // If GNSS is denied or degraded, release any forced standstill lock so INS can run freely.
    // Keep _gnssConfirmedVehicle state — it persists through brief GNSS outages
    // to prevent false pedestrian mode in tunnels or signal shadows.
    if (isDenied || hdop > 10.0) {
      _gnssForceStandstill = false;
      return;
    }

    // Clamp negative speed values (some Android devices report -1.0 when unavailable)
    final speed = math.max(0.0, gnssSpeed);

    // Vehicle speed confirmation: GNSS speed > 2.0 m/s (7.2 km/h) confirms
    // motorized vehicle. Suppresses pedestrian mode for motorcycles/bikes
    // where engine vibration + hand-holding mimics walking cadence.
    if (speed > 2.0 && hdop <= 5.0) {
      _gnssConfirmedVehicle = true;
    } else if (speed < 0.8 && hdop <= 3.0) {
      _gnssConfirmedVehicle = false;
    }

    // Low-speed GNSS override: GPS Doppler is very reliable at distinguishing
    // stationary from moving, even with mediocre HDOP.
    if (hdop <= 8.0 && speed < 0.5) {
      if (_launchKinematicSpeed < 0.20) {
        _gnssForceStandstill = true;
        _isStationary = true;
        _estimatedSpeed = 0.0;
      }
    } else if (hdop <= 5.0 && speed >= 0.8) {
      _gnssForceStandstill = false;
      _isStationary = false;
      // Blend more aggressively from GNSS when available
      _estimatedSpeed = _estimatedSpeed * 0.7 + speed * 0.3;
    }
  }

  /// Explicitly clear any GNSS standstill constraint (e.g. upon entering tunnel)
  void clearGnssForceStandstill() {
    _gnssForceStandstill = false;
  }

  /// Slowly calibrate TCN speed bias during nominal high-quality GNSS
  void applyBiasCorrection(double deltaBias) {
    _biasCorrection = MathUtils.clamp(_biasCorrection + deltaBias, -3.0, 3.0);
  }

  /// Updates the Recursive Least Squares (RLS) velocity calibration from GNSS ground truth speed.
  void updateRlsCalibration(double gnssSpeed, double hdop) {
    if (gnssSpeed < 1.5 || hdop > 3.0 || _rawInferredSpeed < 1.0) return;

    // Measurement model: gnssSpeed = phi^T * theta where phi = [rawInferred, 1.0]^T
    final phi0 = _rawInferredSpeed;
    const phi1 = 1.0;

    // V = P * phi
    final v0 = _p00 * phi0 + _p01 * phi1;
    final v1 = _p10 * phi0 + _p11 * phi1;

    // denom = lambda + phi^T * P * phi
    final denom = _lambdaRls + (phi0 * v0 + phi1 * v1);
    if (denom < 1e-6) return;
    final invDenom = 1.0 / denom;

    // K = V / denom
    final k0 = v0 * invDenom;
    final k1 = v1 * invDenom;

    // Innovation = gnssSpeed - (scale * raw + bias)
    final pred = _rlsScale * phi0 + _rlsBias;
    final innov = gnssSpeed - pred;

    // State update: theta = theta + K * innov
    _rlsScale = MathUtils.clamp(_rlsScale + k0 * innov, 0.85, 1.25);
    _rlsBias = MathUtils.clamp(_rlsBias + k1 * innov, -1.0, 1.0);

    // Covariance update: P = (P - K * V^T) / lambda with windup clamping
    _p00 = MathUtils.clamp((_p00 - k0 * v0) / _lambdaRls, 0.0005, 1.0);
    _p01 = MathUtils.clamp((_p01 - k0 * v1) / _lambdaRls, -0.5, 0.5);
    _p10 = _p01;
    _p11 = MathUtils.clamp((_p11 - k1 * v1) / _lambdaRls, 0.0005, 1.0);
  }

  void reset() {
    _buffer.clear();
    _decimationCounter = 0;
    _estimatedSpeed = 0.0;
    _estimatedVariance = 0.16;
    _pvSpeed = 0.25;
    _isStationary = true;
    _isPedestrian = false;
    _launchKinematicSpeed = 0.0;
    _biasCorrection = 0.0;
    _rawInferredSpeed = 0.0;
    _rlsScale = 1.05;
    _rlsBias = 0.0;
    _p00 = 0.05;
    _p01 = 0.0;
    _p10 = 0.0;
    _p11 = 0.05;
    _stationaryCounter = _stationaryHysteresis;
    _gnssForceStandstill = false;
    _gnssConfirmedVehicle = false;
    _lastAccelVariance = 0.0;
    _lastAvgW = 0.0;
    _lastAvgYawRate = 0.0;
    _restingFwdAccel = 0.0;
    _lastCentripetalSpeed = null;
    _prevGyroZ = 0.0;
  }

  void dispose() {
    try {
      _session?.release();
      _session = null;
      _modelLoaded = false;
      OrtEnv.instance.release();
    } catch (_) {}
  }
}

