#include <iostream>
#include <cassert>
#include <cmath>
#include "idr/common.hpp"
#include "idr/cabin_aligner.hpp"
#include "idr/vibration_gate.hpp"
#include "idr/tcn_speed_engine.hpp"
#include "idr/ekf_3d.hpp"
#include "idr/baseline_dr.hpp"
#include "idr/pipeline.hpp"

using namespace idr;

void testCommon() {
    std::cout << "[Test] Running testCommon..." << std::endl;
    // Rotation matrix identity check
    auto R = rotBodyToWorld(0.0, 0.0, 0.0);
    assert((R - Eigen::Matrix3d::Identity()).norm() < 1e-9);

    // Barometric formula
    double alt0 = altitudeFromPressure(1013.25);
    assert(std::abs(alt0) < 1e-4);

    // Sigmoid
    double s0 = sigmoid(0.0, 1.0, 0.0);
    assert(std::abs(s0 - 0.5) < 1e-6);

    // Navigational heading conversions
    // East = 0 rad ENU -> 90 deg Nav
    assert(std::abs(enuToCompassDeg(0.0) - 90.0) < 1e-4);
    // North = PI/2 rad ENU -> 0 deg Nav
    assert(std::abs(enuToCompassDeg(PI / 2.0) - 0.0) < 1e-4);

    std::cout << "  -> testCommon PASSED!" << std::endl;
}

void testStandstillAndZupt() {
    std::cout << "[Test] Running testStandstillAndZupt..." << std::endl;
    TcnSpeedEngine tcn;

    // Feed stationary data (gravity only on z, zero gyro)
    for (int i = 0; i < 30; ++i) {
        tcn.update({0.0, 0.0, 9.81}, {0.0, 0.0, 0.0}, 0.02);
    }
    assert(tcn.isStandstill());
    assert(tcn.speedMps() == 0.0);

    // Stationary vibration gate bypass
    VibrationGate gate;
    for (int i = 0; i < 20; ++i) {
        gate.update({0.05, -0.02, 9.81}, 0.02, true);
    }
    assert(!gate.shockDetected());
    assert(gate.trustWeight() == 1.0);

    std::cout << "  -> testStandstillAndZupt PASSED!" << std::endl;
}

void testClassicDrSync() {
    std::cout << "[Test] Running testClassicDrSync..." << std::endl;
    IdrPipeline pipeline;

    // Nominal GNSS fix
    GnssSample gnss;
    gnss.lat = 18.5204;
    gnss.lon = 73.8567;
    gnss.alt = 560.0;
    gnss.hdop = 1.0;
    gnss.course = 90.0; // Heading East
    pipeline.processGnss(gnss);

    // IMU steps while nominal
    for (int i = 0; i < 50; ++i) {
        ImuSample imu;
        imu.timestamp = 0.02 * (i + 1);
        imu.accel = {0.0, 0.0, 9.81};
        imu.gyro = {0.0, 0.0, 0.0};
        pipeline.processImu(imu);
    }

    auto sol = pipeline.solution();
    // Classic DR drift should remain 0.0 m during nominal reception
    assert(sol.classicDrift < 0.1);
    std::cout << "  Classic drift during nominal GNSS: " << sol.classicDrift << " m" << std::endl;

    // Now toggle tunnel outage
    pipeline.setTunnelOutage(true);
    for (int i = 0; i < 100; ++i) {
        ImuSample imu;
        imu.timestamp = 1.0 + 0.02 * (i + 1);
        // Simulate small accelerometer bias (0.3 m/s^2) and gyro drift
        imu.accel = {0.3, 0.0, 9.81};
        imu.gyro = {0.0, 0.0, 0.02};
        pipeline.processImu(imu);
    }

    auto solOutage = pipeline.solution();
    std::cout << "  Classic drift during outage: " << solOutage.classicDrift << " m" << std::endl;
    std::cout << "  IDR drift during outage:     " << solOutage.idrDrift << " m" << std::endl;
    assert(solOutage.classicDrift > 0.1);

    std::cout << "  -> testClassicDrSync PASSED!" << std::endl;
}

void testIdleDriftSuppression() {
    std::cout << "[Test] Running testIdleDriftSuppression..." << std::endl;
    Ekf3D ekf;
    ekf.reset({0, 0, 0}, 0.0);

    // Initial position covariance is 1.0 m^2
    assert(ekf.covariance()(0, 0) == 1.0);

    // Simulate 200 standstill cycles (4 seconds at 50 Hz) with small accelerometer and gyro bias
    for (int i = 0; i < 200; ++i) {
        ekf.predict(0.02, 0.0, 0.015, 0.0);
        ekf.applyStandstill(0.015, 0.04);
    }

    // Position must not have crept AT ALL (dx = 0, dy = 0, dz = 0)
    auto pos = ekf.position();
    assert(std::abs(pos.x) < 1e-9);
    assert(std::abs(pos.y) < 1e-9);
    assert(std::abs(pos.z) < 1e-9);

    // Covariance must have contracted well below 1.0 m^2 towards 0.01 m^2
    double covX = ekf.covariance()(0, 0);
    double covY = ekf.covariance()(1, 1);
    std::cout << "  Standstill position variance after 200 cycles: " << covX << " m^2 (floor: 0.01)" << std::endl;
    assert(covX < 0.25);
    assert(covX >= 0.01);
    assert(covY < 0.25);
    assert(covY >= 0.01);

    // Forward accel bias should have been calibrated towards 0.04 m/s^2
    assert(std::abs(ekf.accelBiasX() - 0.04) < 0.01);
    std::cout << "  Estimated accel bias X: " << ekf.accelBiasX() << " m/s^2" << std::endl;

    // Gyro bias should have been calibrated towards 0.015 rad/s
    assert(std::abs(ekf.gyroBiasZ() - 0.015) < 0.005);
    std::cout << "  Estimated gyro bias Z:  " << ekf.gyroBiasZ() << " rad/s" << std::endl;

    std::cout << "  -> testIdleDriftSuppression PASSED!" << std::endl;
}

void testMapMatching() {
    std::cout << "[Test] Running testMapMatching..." << std::endl;
    Ekf3D ekf;
    ekf.reset({5.0, 2.0, 0.0}, 0.0);

    // Road segment along East (normal pointing North = [0, 1])
    // Cross track distance is 2.0m (vehicle is 2m North of road centerline)
    ekf.updateMapMatching({0.0, 1.0, 0.0}, 2.0, 1.0, 0.0);

    // Position Y should be pulled towards 0.0
    auto pos = ekf.position();
    assert(pos.y < 2.0);
    std::cout << "  Position Y after map match correction: " << pos.y << " m (started at 2.0 m)" << std::endl;

    // Map heading constraint
    ekf.updateMapHeading(0.0, 0.9);

    std::cout << "  -> testMapMatching PASSED!" << std::endl;
}

void testCompassDeadband() {
    std::cout << "[Test] Running testCompassDeadband..." << std::endl;
    Ekf3D ekf;
    ekf.reset({0, 0, 0}, 0.0);

    // Small compass discrepancy (< 0.02 rad ~ 1.1 deg) must be ignored by deadband
    ekf.updateCompass(0.01, 0.05, true);
    assert(ekf.yaw() == 0.0); // Exact 0.0 preserved!

    // Discrepancy > 0.02 rad is gently updated with stationary attenuation
    ekf.updateCompass(0.10, 0.05, true);
    assert(ekf.yaw() > 0.0 && ekf.yaw() < 0.05);

    std::cout << "  -> testCompassDeadband PASSED!" << std::endl;
}

int main() {
    std::cout << "=========================================" << std::endl;
    std::cout << "  Testing IDR Pure C++ Core Engine       " << std::endl;
    std::cout << "=========================================" << std::endl;

    testCommon();
    testStandstillAndZupt();
    testClassicDrSync();
    testIdleDriftSuppression();
    testMapMatching();
    testCompassDeadband();

    std::cout << "=========================================" << std::endl;
    std::cout << "  ALL C++ CORE TESTS PASSED SUCCESSFULLY!" << std::endl;
    std::cout << "=========================================" << std::endl;
    return 0;
}
