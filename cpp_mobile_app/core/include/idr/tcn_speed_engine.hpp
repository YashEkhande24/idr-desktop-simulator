#pragma once

#include <deque>
#include <vector>
#include "idr/types.hpp"

namespace idr {

class TcnSpeedEngine {
public:
    TcnSpeedEngine(int windowSize = 50);

    // Update with vehicle-frame IMU sample
    // gnssSpeedMps: optional GNSS speed aiding (-1.0 if not available)
    // pitchRad: vehicle cabin tilt pitch in radians for slope gravity compensation
    void update(const Vec3& alignedAccel, const Vec3& alignedGyro, double dt, double gnssSpeedMps = -1.0, double pitchRad = 0.0);

    // Feed external AI prediction (e.g., from Dart ONNX runtime)
    void setExternalSpeed(double speedMps, double variance = 0.05);

    // GNSS Speed synchronization & zero-speed anchoring
    void synchronizeGnssSpeed(double speedMps, double hdop, bool isDenied = false);
    void applyBiasCorrection(double deltaMps);

    // Pedestrian mode toggle & detection
    void setPedestrianMode(bool pedestrian) { isPedestrian_ = pedestrian; }
    bool isPedestrian() const { return isPedestrian_; }

    // Estimated forward speed in m/s
    double speedMps() const { return estimatedSpeed_; }

    // Speed in km/h
    double speedKmh() const { return estimatedSpeed_ * 3.6; }

    // Standstill detector (ZUPT) status
    bool isStandstill() const { return isStandstill_; }

    // Acceleration variance (m^2/s^4)
    double accelVariance() const { return accelVariance_; }
    double estimatedVariance() const { return estimatedVariance_; }

    // Outage cruising mode
    void setOutageMode(bool outage, double entrySpeedMps = 0.0);
    bool isOutageMode() const { return isOutageMode_; }
    void clearStandstill();

    void reset();

private:
    void checkStandstill(double gnssSpeedMps);
    double evaluateTcnModel();

    int windowSize_;
    double estimatedSpeed_ = 0.0;
    double estimatedVariance_ = 0.05;
    bool isStandstill_ = true;
    int quietCount_ = 5;
    bool isPedestrian_ = false;
    bool isOutageMode_ = false;
    double outageCruisingSpeed_ = 0.0;
    double accelVariance_ = 0.0;
    double speedBias_ = 0.0;

    std::deque<Vec3> accelBuffer_;
    std::deque<Vec3> gyroBuffer_;
};

} // namespace idr
