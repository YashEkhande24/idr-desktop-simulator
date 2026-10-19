import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:idr_navigator/core/math_utils.dart';
import 'package:idr_navigator/models/ekf_state.dart';
import 'package:idr_navigator/models/nav_solution.dart';
import 'package:idr_navigator/models/navigation_models.dart';
import 'package:idr_navigator/services/idr_pipeline.dart';
import 'package:idr_navigator/services/tcn_speed_engine.dart';
import 'package:idr_navigator/services/ekf_3d.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('dev.fluttercommunity.plus/sensors/method'), (call) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter.baseflow.com/geolocator'), (call) async {
          if (call.method == 'isLocationServiceEnabled') return true;
          if (call.method == 'checkPermission') return 3;
          return null;
        });
  });

  group('Travelling Navigation & Math Verification Suite', () {
    test('1. NavSolution.speedKmh returns GNSS Doppler speed during nominal driving', () {
      final sol = NavSolution(
        timestamp: 100.0,
        idrState: const EkfState(
          position: Vec3.zero,
          velocity: Vec3.zero, // EKF temporarily 0 at startup
          attitude: Vec3.zero,
          covariance: [],
        ),
        classicDrState: const EkfState(
          position: Vec3.zero,
          velocity: Vec3.zero,
          attitude: Vec3.zero,
          covariance: [],
        ),
        gnssStatus: GnssStatus.available,
        hdop: 1.2,
        isGnssDenied: false,
        idrDriftError: 0.0,
        classicDriftError: 0.0,
        shockDetected: false,
        rawJerk: 0.0,
        jerkVariance: 0.0,
        tcnEstimatedSpeed: 0.0,
        baroAltitude: 0.0,
        cabinConfidence: 1.0,
        isCabinLocked: true,
        mountPitchDeg: 0.0,
        mountRollDeg: 0.0,
        gnssSpeed: 15.0, // 15 m/s = 54.0 km/h
      );

      // Must report live GNSS Doppler ground truth (54.0 km/h), NOT 0.0!
      expect(sol.speedKmh, closeTo(54.0, 0.1));
    });

    test('2. TcnSpeedEngine breaks out of standstill when GNSS confirms motion', () {
      final tcn = TcnSpeedEngine();

      // Start stationary
      expect(tcn.isStationary, isTrue);

      // Feed high-confidence GNSS speed of 12.0 m/s (43.2 km/h)
      tcn.synchronizeGnssSpeed(12.0, 1.5);

      expect(tcn.isStationary, isFalse);
      expect(tcn.estimatedSpeed, greaterThan(5.0));
    });

    test('3. TcnSpeedEngine does NOT falsely classify smooth highway cruising as desk rest', () {
      final tcn = TcnSpeedEngine();

      // Vehicle accelerates and cruises at 16.0 m/s (~58 km/h)
      tcn.synchronizeGnssSpeed(16.0, 1.2);

      // Simulate 100 samples (1.0 sec @ 100 Hz) of smooth straight-line cruising on highway asphalt
      // Smooth cruising has low variance (~0.18 m^2/s^4) and low gyro rates (w ~ 0.02 rad/s)
      for (int i = 0; i < 100; i++) {
        tcn.predict(
          vehicleAccel: const Vec3(0.02, 0.01, 0.0),
          vehicleGyro: const Vec3(0.01, 0.01, 0.02),
          isShockGateActive: false,
          dt: 0.01,
        );
      }

      // Standstill must NOT be triggered during highway cruising!
      expect(tcn.isStationary, isFalse);
      expect(tcn.estimatedSpeed, greaterThan(10.0));
    });

    test('4. Ekf3D snap threshold and nominal GNSS position updates prevent position freeze', () {
      final ekf = Ekf3D();

      // Initial state is stationary at (0, 0, 0)
      for (int i = 0; i < 50; i++) {
        ekf.applyStandstill(0.01, 0.01);
      }
      expect(ekf.state.position.x, equals(0.0));
      expect(ekf.state.position.y, equals(0.0));

      // Vehicle moves forward to (0, 8.0, 0) - GNSS reports 8m advance
      ekf.updateGnss(
        gnssX: 0.0,
        gnssY: 8.0,
        gnssZ: 0.0,
        hdop: 1.2,
        isDenied: false,
      );

      // Position MUST have advanced significantly towards GNSS position (not frozen at 0!)
      expect(ekf.state.position.y, greaterThan(4.0));
    });

    test('5. Real-time navigation tracks moving vehicle and decrements remaining distance', () async {
      final pipeline = IdrPipeline();
      final navService = pipeline.navigationService;

      const dest = NavDestination(
        name: 'Tech Park Plaza',
        targetEnu: Vec3(0, 1000, 0), // 1 km North
      );

      await navService.startNavigation(dest, pipeline);
      expect(navService.isNavigating, isTrue);
      final initialRemaining = navService.remainingDistanceMeters;
      expect(initialRemaining, closeTo(1000.0, 50.0));

      // Simulate vehicle travelling North from (0, 0) to (0, 200) to (0, 400)
      navService.updateVehicleProgress(const Vec3(0, 200, 0), 0.0, pipeline);
      expect(navService.remainingDistanceMeters, lessThan(initialRemaining));
      final remAt200 = navService.remainingDistanceMeters;

      navService.updateVehicleProgress(const Vec3(0, 400, 0), 0.0, pipeline);
      expect(navService.remainingDistanceMeters, lessThan(remAt200));

      // Simulate approaching junction / finish at (0, 990)
      navService.updateVehicleProgress(const Vec3(0, 990, 0), 0.0, pipeline);
      expect(navService.hasArrived, isTrue);
      expect(navService.remainingDistanceMeters, equals(0.0));

      pipeline.dispose();
    });
  });
}
