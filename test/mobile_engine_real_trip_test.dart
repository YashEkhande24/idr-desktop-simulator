// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:idr_navigator/core/math_utils.dart';
import 'package:idr_navigator/services/tcn_speed_engine.dart';

int _findCol(List<String> header, List<String> patterns) {
  for (int i = 0; i < header.length; i++) {
    final h = header[i].toLowerCase();
    for (final p in patterns) {
      if (h.contains(p)) return i;
    }
  }
  return -1;
}

/// Helper to parse an IO-VNBD synchronized S-*.csv file into IMU and ground truth speed.
List<Map<String, dynamic>> parseIovnbdCsv(String filePath) {
  final file = File(filePath);
  if (!file.existsSync()) {
    throw Exception('File not found: $filePath');
  }
  final lines = file.readAsLinesSync(encoding: latin1);
  if (lines.length < 2) return [];

  final header = lines[0].split(',').map((e) => e.trim().toLowerCase()).toList();
  final axIdx = _findCol(header, ['accelerometer x', 'accel x', 'ax']);
  final ayIdx = _findCol(header, ['accelerometer y', 'accel y', 'ay']);
  final azIdx = _findCol(header, ['accelerometer z', 'accel z', 'az']);
  final wxIdx = _findCol(header, ['gyroscope roll', 'gyr x', 'wx']);
  final wyIdx = _findCol(header, ['gyroscope pitch', 'gyr y', 'wy']);
  final wzIdx = _findCol(header, ['gyroscope yaw', 'gyr z', 'wz']);
  final vIdx = _findCol(header, ['gps speed', 'speed', 'velocity']);

  if (axIdx == -1 || ayIdx == -1 || azIdx == -1 || vIdx == -1) {
    return [];
  }

  final data = <Map<String, dynamic>>[];
  for (int i = 1; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty) continue;
    final parts = line.split(',');
    if (parts.length < header.length) continue;

    try {
      final ax = double.parse(parts[axIdx]);
      final ay = double.parse(parts[ayIdx]);
      final az = double.parse(parts[azIdx]);
      final wx = wxIdx != -1 ? double.parse(parts[wxIdx]) : 0.0;
      final wy = wyIdx != -1 ? double.parse(parts[wyIdx]) : 0.0;
      final wz = wzIdx != -1 ? double.parse(parts[wzIdx]) : 0.0;
      double speed = double.parse(parts[vIdx]);
      // Only convert if explicitly recorded in raw km/h with mean > 35.0 matching train.py
      if (speed > 40.0) {
        speed = speed / 3.6;
      }

      data.add({
        'acc': Vec3(ax, ay, az),
        'gyr': Vec3(wx, wy, wz),
        'speed': speed,
      });
    } catch (_) {
      continue;
    }
  }

  // Gravity compensation matching CabinAligner and train.py:
  // Subtract the static gravity vector (norm ~ 9.81 m/s^2) so dynamic acceleration is centered at 0
  if (data.isNotEmpty) {
    double sumX = 0, sumY = 0, sumZ = 0;
    for (final d in data) {
      final a = d['acc'] as Vec3;
      sumX += a.x;
      sumY += a.y;
      sumZ += a.z;
    }
    final meanX = sumX / data.length;
    final meanY = sumY / data.length;
    final meanZ = sumZ / data.length;
    final normMean = math.sqrt(meanX * meanX + meanY * meanY + meanZ * meanZ);
    if (normMean > 5.0) {
      final gx = (meanX / normMean) * 9.80665;
      final gy = (meanY / normMean) * 9.80665;
      final gz = (meanZ / normMean) * 9.80665;
      for (int i = 0; i < data.length; i++) {
        final a = data[i]['acc'] as Vec3;
        data[i]['acc'] = Vec3(a.x - gx, a.y - gy, a.z - gz);
      }
    }
  }

  return data;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Mobile App Engine Real-Trip Benchmark Tests', () {
    late TcnSpeedEngine engine;

    setUp(() async {
      engine = TcnSpeedEngine();
      final loaded = await engine.loadModel('assets/models/vehicle_speed_tcn.onnx');
      expect(loaded, isTrue, reason: 'ONNX model must load successfully in Flutter engine');
      expect(engine.isModelLoaded, isTrue);
    });

    test('Test Case A: Real Stop-and-Go Urban Traffic (S-Vta1a.csv)', () {
      final records = parseIovnbdCsv(r'model\IO-VNBD\Synchronised V abd S datasets\Categorised IOVNB Dataset\Vta (Driver E)\Vta01a\S-Vta1a.csv');
      expect(records.isNotEmpty, isTrue);

      double trueDist = 0.0;
      double estimatedDist = 0.0;
      const double dt = 0.1; // 10 Hz dataset
      final int stepsToRun = records.length > 1200 ? 1200 : records.length; // 120 seconds stop-and-go window

      for (int i = 0; i < stepsToRun; i++) {
        final r = records[i];
        final acc = r['acc'] as Vec3;
        final gyr = r['gyr'] as Vec3;
        final truthSpeed = r['speed'] as double;

        final estSpeed = engine.predict(
          vehicleAccel: acc,
          vehicleGyro: gyr,
          isShockGateActive: false,
          dt: dt,
        );

        trueDist += truthSpeed * dt;
        estimatedDist += estSpeed * dt;
      }

      final driftError = (estimatedDist - trueDist).abs();
      final driftPct = (driftError / trueDist) * 100.0;

      print('[Flutter Test] S-Vta1a: True Dist = ${trueDist.toStringAsFixed(1)}m | '
          'Est Dist = ${estimatedDist.toStringAsFixed(1)}m | '
          'Drift = ${driftPct.toStringAsFixed(2)}%');

      // Must satisfy SIH <10% drift rule
      expect(driftPct, lessThan(10.0),
          reason: 'Mobile app engine must achieve <10% drift on real stop-and-go trip');
    });

    test('Test Case B: Real Stationary Curb Idle (S-Vta20.csv) - ZUPT Lock', () {
      final records = parseIovnbdCsv(r'model\IO-VNBD\Synchronised V abd S datasets\Categorised IOVNB Dataset\Vta (Driver E)\Vta20\S-Vta20.csv');
      expect(records.isNotEmpty, isTrue);

      double estimatedDist = 0.0;
      const double dt = 0.1;
      const int stepsToRun = 600; // 60 seconds of engine idle at curb

      for (int i = 0; i < stepsToRun; i++) {
        final r = records[i];
        final acc = r['acc'] as Vec3;
        final gyr = r['gyr'] as Vec3;

        final estSpeed = engine.predict(
          vehicleAccel: acc,
          vehicleGyro: gyr,
          isShockGateActive: false,
          dt: dt,
        );

        estimatedDist += estSpeed * dt;
      }

      print('[Flutter Test] S-Vta20 (Stationary): Accumulated Dist = ${estimatedDist.toStringAsFixed(2)}m');

      // The mobile app Skog GLRT ZUPT must clamp speed and prevent vibration drift
      expect(engine.isStationary, isTrue);
      expect(estimatedDist, lessThan(3.0),
          reason: 'Mobile app engine ZUPT must hold stationary drift under 3.0 meters over 60s');
    });

    test('Test Case C: Real Suburban Free-Flow Drive (S-Vtb8.csv)', () {
      final records = parseIovnbdCsv(r'model\IO-VNBD\Synchronised V abd S datasets\Categorised IOVNB Dataset\Vtb (Driver E)\Vtb08\S-Vtb8.csv');
      expect(records.isNotEmpty, isTrue);

      double trueDist = 0.0;
      double estimatedDist = 0.0;
      const double dt = 0.1;
      final int stepsToRun = records.length > 600 ? 600 : records.length;

      for (int i = 0; i < stepsToRun; i++) {
        final r = records[i];
        final acc = r['acc'] as Vec3;
        final gyr = r['gyr'] as Vec3;
        final truthSpeed = r['speed'] as double;

        final estSpeed = engine.predict(
          vehicleAccel: acc,
          vehicleGyro: gyr,
          isShockGateActive: false,
          dt: dt,
        );

        trueDist += truthSpeed * dt;
        estimatedDist += estSpeed * dt;
      }

      final driftError = (estimatedDist - trueDist).abs();
      final driftPct = (driftError / trueDist) * 100.0;

      print('[Flutter Test] S-Vtb8: True Dist = ${trueDist.toStringAsFixed(1)}m | '
          'Est Dist = ${estimatedDist.toStringAsFixed(1)}m | '
          'Drift = ${driftPct.toStringAsFixed(2)}%');

      // Satisfies SIH <10% drift rule
      expect(driftPct, lessThan(10.0),
          reason: 'Mobile app engine must achieve <10% drift on free-flow suburban trip');
    });
  });
}
