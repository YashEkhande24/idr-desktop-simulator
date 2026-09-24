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

  // Dynamic acceleration centering (gravity compensation)
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

  group('Mobile App Engine Stop-and-Go Traffic Suite', () {
    late TcnSpeedEngine engine;

    setUp(() async {
      engine = TcnSpeedEngine();
      final loaded = await engine.loadModel('assets/models/vehicle_speed_tcn.onnx');
      expect(loaded, isTrue, reason: 'ONNX model must load successfully in Flutter engine');
      expect(engine.isModelLoaded, isTrue);
    });

    test('1. Stop-and-Go Standstill Breakout Responsiveness (Latency Test)', () {
      // Step A: Feed 45 resting standstill samples so buffer is initialized and ZUPT engages
      for (int i = 0; i < 45; i++) {
        engine.predict(
          vehicleAccel: const Vec3(0.01, 0.00, 0.01),
          vehicleGyro: const Vec3(0.001, 0.001, 0.001),
          isShockGateActive: false,
          dt: 0.1,
        );
      }
      expect(engine.isStationary, isTrue, reason: 'Engine must be locked in stationary ZUPT');
      expect(engine.estimatedSpeed, equals(0.0));

      // Step B: Apply standard city throttle launch (1.0 m/s^2 forward pull-away)
      int breakoutSteps = 0;
      bool brokeOut = false;

      for (int i = 0; i < 10; i++) {
        engine.predict(
          vehicleAccel: const Vec3(1.00, 0.02, 0.01), // Standard city intersection pull-away
          vehicleGyro: const Vec3(0.005, 0.002, 0.001),
          isShockGateActive: false,
          dt: 0.1,
        );
        breakoutSteps++;
        if (!engine.isStationary) {
          brokeOut = true;
          break;
        }
      }

      print('[Stop-and-Go Test] Breakout detected in $breakoutSteps step(s) (${breakoutSteps * 100} ms).');

      expect(brokeOut, isTrue, reason: 'Vehicle must break out of standstill on throttle');
      expect(breakoutSteps, lessThanOrEqualTo(5), reason: 'Breakout latency must be <= 500 ms');
    });

    test('2. Multi-Stop Congestion Queue: S-Vta1a.csv (4 Stop-Start Cycles)', () {
      final records = parseIovnbdCsv(r'model\IO-VNBD\Synchronised V abd S datasets\Categorised IOVNB Dataset\Vta (Driver E)\Vta01a\S-Vta1a.csv');
      expect(records.isNotEmpty, isTrue);

      double trueDist = 0.0;
      double estDist = 0.0;
      const double dt = 0.1;
      final int steps = math.min(1200, records.length); // 120s

      int breakoutCount = 0;
      bool wasStationary = false;

      for (int i = 0; i < steps; i++) {
        final r = records[i];
        final acc = r['acc'] as Vec3;
        final gyr = r['gyr'] as Vec3;
        final truth = r['speed'] as double;

        final est = engine.predict(
          vehicleAccel: acc,
          vehicleGyro: gyr,
          isShockGateActive: false,
          dt: dt,
        );

        trueDist += truth * dt;
        estDist += est * dt;

        if (engine.isStationary) {
          wasStationary = true;
        } else if (wasStationary) {
          breakoutCount++;
          wasStationary = false;
        }
      }

      final driftPct = (estDist - trueDist).abs() / trueDist * 100.0;
      print('[Stop-and-Go Test] S-Vta1a: True Dist = ${trueDist.toStringAsFixed(1)}m | '
          'Est Dist = ${estDist.toStringAsFixed(1)}m | '
          'Drift = ${driftPct.toStringAsFixed(2)}% | '
          'Breakouts = $breakoutCount');

      expect(driftPct, lessThan(10.0), reason: 'Drift must satisfy SIH <10% rule');
      expect(breakoutCount, greaterThan(0), reason: 'Must detect active breakouts in stop-and-go traffic');
    });

    test('3. Repeated Signal Stops: S-Vta1b.csv (Arterial Corridor)', () {
      final records = parseIovnbdCsv(r'model\IO-VNBD\Synchronised V abd S datasets\Categorised IOVNB Dataset\Vta (Driver E)\Vta01b\S-Vta1b.csv');
      expect(records.isNotEmpty, isTrue);

      double trueDist = 0.0;
      double estDist = 0.0;
      const double dt = 0.1;
      final int steps = math.min(1200, records.length);

      int statCount = 0;
      for (int i = 0; i < steps; i++) {
        final r = records[i];
        final acc = r['acc'] as Vec3;
        final gyr = r['gyr'] as Vec3;
        final truth = r['speed'] as double;

        final est = engine.predict(
          vehicleAccel: acc,
          vehicleGyro: gyr,
          isShockGateActive: false,
          dt: dt,
        );

        if (engine.isStationary) statCount++;

        trueDist += truth * dt;
        estDist += est * dt;
      }

      final driftPct = (estDist - trueDist).abs() / trueDist * 100.0;
      print('[Stop-and-Go Test] S-Vta1b: True Dist = ${trueDist.toStringAsFixed(1)}m | '
          'Est Dist = ${estDist.toStringAsFixed(1)}m | '
          'Drift = ${driftPct.toStringAsFixed(2)}% | StatCount = $statCount / $steps');

      expect(driftPct, lessThan(12.0));
    });

    test('4. Heavy Traffic Signals: S-Vta4.csv', () {
      final records = parseIovnbdCsv(r'model\IO-VNBD\Synchronised V abd S datasets\Categorised IOVNB Dataset\Vta (Driver E)\Vta04\S-Vta4.csv');
      expect(records.isNotEmpty, isTrue);

      double trueDist = 0.0;
      double estDist = 0.0;
      const double dt = 0.1;
      final int steps = math.min(1200, records.length);

      for (int i = 0; i < steps; i++) {
        final r = records[i];
        final acc = r['acc'] as Vec3;
        final gyr = r['gyr'] as Vec3;
        final truth = r['speed'] as double;

        final est = engine.predict(
          vehicleAccel: acc,
          vehicleGyro: gyr,
          isShockGateActive: false,
          dt: dt,
        );

        trueDist += truth * dt;
        estDist += est * dt;
      }

      final driftPct = (estDist - trueDist).abs() / trueDist * 100.0;
      print('[Stop-and-Go Test] S-Vta4: True Dist = ${trueDist.toStringAsFixed(1)}m | '
          'Est Dist = ${estDist.toStringAsFixed(1)}m | '
          'Drift = ${driftPct.toStringAsFixed(2)}%');

      expect(driftPct, lessThan(10.0));
    });

    test('5. Urban Traffic Flow: S-Vta6.csv', () {
      final records = parseIovnbdCsv(r'model\IO-VNBD\Synchronised V abd S datasets\Categorised IOVNB Dataset\Vta (Driver E)\Vta06\S-Vta6.csv');
      expect(records.isNotEmpty, isTrue);

      double trueDist = 0.0;
      double estDist = 0.0;
      const double dt = 0.1;
      final int steps = math.min(1200, records.length);

      for (int i = 0; i < steps; i++) {
        final r = records[i];
        final acc = r['acc'] as Vec3;
        final gyr = r['gyr'] as Vec3;
        final truth = r['speed'] as double;

        final est = engine.predict(
          vehicleAccel: acc,
          vehicleGyro: gyr,
          isShockGateActive: false,
          dt: dt,
        );

        trueDist += truth * dt;
        estDist += est * dt;
      }

      final driftPct = (estDist - trueDist).abs() / trueDist * 100.0;
      print('[Stop-and-Go Test] S-Vta6: True Dist = ${trueDist.toStringAsFixed(1)}m | '
          'Est Dist = ${estDist.toStringAsFixed(1)}m | '
          'Drift = ${driftPct.toStringAsFixed(2)}%');

      expect(driftPct, lessThan(10.0));
    });

    test('6. Suburban Intersection Stop-and-Go: S-Vtb5.csv', () {
      final records = parseIovnbdCsv(r'model\IO-VNBD\Synchronised V abd S datasets\Categorised IOVNB Dataset\Vtb (Driver E)\Vtb05\S-Vtb5.csv');
      expect(records.isNotEmpty, isTrue);

      double trueDist = 0.0;
      double estDist = 0.0;
      const double dt = 0.1;
      final int steps = math.min(1200, records.length);

      for (int i = 0; i < steps; i++) {
        final r = records[i];
        final acc = r['acc'] as Vec3;
        final gyr = r['gyr'] as Vec3;
        final truth = r['speed'] as double;

        final est = engine.predict(
          vehicleAccel: acc,
          vehicleGyro: gyr,
          isShockGateActive: false,
          dt: dt,
        );

        trueDist += truth * dt;
        estDist += est * dt;
      }

      final driftPct = (estDist - trueDist).abs() / trueDist * 100.0;
      print('[Stop-and-Go Test] S-Vtb5: True Dist = ${trueDist.toStringAsFixed(1)}m | '
          'Est Dist = ${estDist.toStringAsFixed(1)}m | '
          'Drift = ${driftPct.toStringAsFixed(2)}%');

      expect(driftPct, lessThan(10.0));
    });

    test('7. Mixed City Congestion: S-Vw14a.csv', () {
      final records = parseIovnbdCsv(r'model\IO-VNBD\Synchronised V abd S datasets\Categorised IOVNB Dataset\Vw (Driver E)\Vw14a\S-Vw14a.csv');
      expect(records.isNotEmpty, isTrue);

      double trueDist = 0.0;
      double estDist = 0.0;
      const double dt = 0.1;
      final int steps = math.min(1200, records.length);

      for (int i = 0; i < steps; i++) {
        final r = records[i];
        final acc = r['acc'] as Vec3;
        final gyr = r['gyr'] as Vec3;
        final truth = r['speed'] as double;

        final est = engine.predict(
          vehicleAccel: acc,
          vehicleGyro: gyr,
          isShockGateActive: false,
          dt: dt,
        );

        trueDist += truth * dt;
        estDist += est * dt;
      }

      final driftPct = (estDist - trueDist).abs() / trueDist * 100.0;
      print('[Stop-and-Go Test] S-Vw14a: True Dist = ${trueDist.toStringAsFixed(1)}m | '
          'Est Dist = ${estDist.toStringAsFixed(1)}m | '
          'Drift = ${driftPct.toStringAsFixed(2)}%');

      expect(driftPct, lessThan(10.0));
    });
  });
}
