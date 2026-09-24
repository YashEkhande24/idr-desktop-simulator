import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:idr_navigator/core/constants.dart';
import 'package:idr_navigator/core/math_utils.dart';
import 'package:idr_navigator/services/vibration_gate.dart';

void main() {
  group('Module 2: VibrationGate Tests', () {
    test('Smooth road driving does not trigger shock gate', () {
      final gate = VibrationGate();

      // Constant or slowly varying vehicle acceleration
      for (int i = 0; i < 50; i++) {
        gate.process(const Vec3(1.2, 0.05, 0.02), IdrConstants.dtImu);
      }

      expect(gate.isShockDetected, isFalse);
      expect(gate.getCovarianceInflation(), equals(1.0));
      expect(gate.lastVariance, lessThan(IdrConstants.jerkVarianceThreshold));
    });

    test('Violent pothole shock triggers gate and inflates covariance', () {
      final gate = VibrationGate();

      // Normal road driving first
      for (int i = 0; i < 20; i++) {
        gate.process(const Vec3(1.0, 0.0, 0.0), IdrConstants.dtImu);
      }

      // Sudden violent vertical pothole impact spike
      gate.process(const Vec3(1.0, 0.0, 18.0), IdrConstants.dtImu);
      gate.process(const Vec3(1.0, 0.0, -12.0), IdrConstants.dtImu);
      gate.process(const Vec3(1.0, 0.0, 0.0), IdrConstants.dtImu);

      expect(gate.isShockDetected, isTrue);
      expect(gate.getCovarianceInflation(), equals(IdrConstants.jerkGateInflationFactor));
      expect(gate.lastVariance, greaterThan(IdrConstants.jerkVarianceThreshold));
    });

    test('Continuous rough road classifies as ROUGH ROAD without permanent shock trip', () {
      final gate = VibrationGate();

      // Moderate continuous road rumble / cobblestone with multi-frequency surface texture
      for (int i = 0; i < 60; i++) {
        final zNoise = math.sin(i * 0.25) * 0.5 + math.cos(i * 0.6) * 0.3;
        gate.process(Vec3(1.0, 0.1, zNoise), IdrConstants.dtImu);
      }

      // Should recognize rough road without locking into a violent shock trip
      expect(gate.isShockDetected, isFalse);
      expect(gate.isRoughRoad, isTrue);
      expect(gate.roadConditionString, equals('ROUGH ROAD'));
    });

    test('Pothole shock auto-clears after suspension rebound hold duration', () {
      final gate = VibrationGate();

      for (int i = 0; i < 20; i++) {
        gate.process(const Vec3(1.0, 0.0, 0.0), IdrConstants.dtImu);
      }

      // Violent pothole strike
      gate.process(const Vec3(1.0, 0.0, 20.0), IdrConstants.dtImu);
      gate.process(const Vec3(1.0, 0.0, -15.0), IdrConstants.dtImu);
      expect(gate.isShockDetected, isTrue);

      // Advance time past the rebound duration (350 ms hold + settling time)
      for (int i = 0; i < 60; i++) {
        gate.process(const Vec3(1.0, 0.0, 0.0), IdrConstants.dtImu);
      }

      // Gate must auto-clear and return to smooth road
      expect(gate.isShockDetected, isFalse);
      expect(gate.roadConditionString, equals('NORMAL'));
    });

    test('Pedestrian walking motion suppresses vehicle shock alarms', () {
      final gate = VibrationGate();

      // Sudden footstep impact while walking
      gate.process(
        const Vec3(0.5, 0.2, 5.0),
        IdrConstants.dtImu,
        isPedestrian: true,
      );

      expect(gate.isShockDetected, isFalse);
      expect(gate.roadConditionString, equals('PEDESTRIAN'));
    });

    test('TCN uncertainty elevation smoothly scales trust weight down', () {
      final gate = VibrationGate();

      // Normal driving with elevated TCN uncertainty
      for (int i = 0; i < 20; i++) {
        gate.process(
          const Vec3(1.0, 0.0, 0.0),
          IdrConstants.dtImu,
          tcnVariance: 2.5, // High AI uncertainty
        );
      }

      // Trust weight should be scaled down by AI confidence
      expect(gate.trustWeight, lessThan(0.90));
      expect(gate.getCovarianceInflation(), greaterThan(1.0));
    });
  });
}
