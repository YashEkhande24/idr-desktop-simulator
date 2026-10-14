#include "idr/tcn_speed_engine.hpp"
#include "idr/common.hpp"
#include <cmath>
#include <numeric>
#include <algorithm>

namespace idr {

TcnSpeedEngine::TcnSpeedEngine(int windowSize)
    : windowSize_(windowSize) {}

void TcnSpeedEngine::reset() {
    accelBuffer_.clear();
    gyroBuffer_.clear();
    estimatedSpeed_ = 0.0;
    estimatedVariance_ = 0.05;
    isStandstill_ = true;
    quietCount_ = 5;
    isPedestrian_ = false;
    isOutageMode_ = false;
    outageCruisingSpeed_ = 0.0;
    accelVariance_ = 0.0;
    speedBias_ = 0.0;
}

void TcnSpeedEngine::setOutageMode(bool outage, double entrySpeedMps) {
    isOutageMode_ = outage;
    if (outage) {
        isStandstill_ = false;
        quietCount_ = 0;
        if (entrySpeedMps > 1.0) {
            outageCruisingSpeed_ = entrySpeedMps;
            if (estimatedSpeed_ < 1.0) {
                estimatedSpeed_ = entrySpeedMps;
            }
        } else if (estimatedSpeed_ > 1.0) {
            outageCruisingSpeed_ = estimatedSpeed_;
        }
    } else {
        outageCruisingSpeed_ = 0.0;
    }
}

void TcnSpeedEngine::clearStandstill() {
    isStandstill_ = false;
    quietCount_ = 0;
}

void TcnSpeedEngine::setExternalSpeed(double speedMps, double variance) {
    estimatedVariance_ = std::clamp(variance, 0.01, 5.0);
    if (speedMps < 0.25) {
        estimatedSpeed_ = 0.0;
        isStandstill_ = true;
        quietCount_ = 5;
    } else {
        estimatedSpeed_ = std::max(0.0, speedMps + speedBias_);
        isStandstill_ = false;
        quietCount_ = 0;
    }
}

void TcnSpeedEngine::synchronizeGnssSpeed(double speedMps, double hdop, bool isDenied) {
    if (isDenied || isOutageMode_ || hdop > 5.0 || speedMps < 0.0) {
        if (isDenied || isOutageMode_) {
            isStandstill_ = false;
        }
        return;
    }

    if (speedMps < 0.35 && hdop <= 4.0) {
        // High confidence GNSS lock confirms vehicle is stationary (< 1.2 km/h)
        isStandstill_ = true;
        quietCount_ = 5;
        estimatedSpeed_ = 0.0;
    } else if (speedMps > 1.5 && !isStandstill_) {
        // Softly anchor speed when moving confidently
        estimatedSpeed_ = estimatedSpeed_ * 0.90 + speedMps * 0.10;
    }
}

void TcnSpeedEngine::applyBiasCorrection(double deltaMps) {
    speedBias_ = std::clamp(speedBias_ + deltaMps, -1.5, 1.5);
}

void TcnSpeedEngine::update(const Vec3& alignedAccel, const Vec3& alignedGyro, double dt, double gnssSpeedMps, double pitchRad) {
    accelBuffer_.push_back(alignedAccel);
    gyroBuffer_.push_back(alignedGyro);

    if (static_cast<int>(accelBuffer_.size()) > windowSize_) {
        accelBuffer_.pop_front();
        gyroBuffer_.pop_front();
    }

    checkStandstill(gnssSpeedMps);

    if (isStandstill_) {
        estimatedSpeed_ = 0.0;
        return;
    }

    double effectiveDt = std::clamp(dt, 0.001, 0.10);
    double netFwdAccel = (std::abs(pitchRad) > 0.01)
        ? (alignedAccel.x - GRAVITY_STANDARD * std::sin(pitchRad))
        : alignedAccel.x;
    double aFwd = netFwdAccel;
    double deltaV = aFwd * effectiveDt;

    // Deadband on longitudinal acceleration to reject thermal IMU bias (~0.15 m/s^2)
    if (std::abs(deltaV) < 0.15 * effectiveDt) {
        deltaV = 0.0;
    }

    estimatedSpeed_ += deltaV;

    // Aerodynamic and rolling friction damping when coasting
    if (std::abs(aFwd) < 0.20 && estimatedSpeed_ > 0.1) {
        estimatedSpeed_ *= (1.0 - 0.01 * effectiveDt);
    }

    // Outage Cruising Guard: In outage/tunnel mode, maintain cruising speed along momentum vector
    // unless real deceleration/braking is observed (aFwd < -0.5)
    if (isOutageMode_ && outageCruisingSpeed_ > 1.0 && aFwd > -0.5) {
        estimatedSpeed_ = std::max(estimatedSpeed_, outageCruisingSpeed_ * 0.98);
        outageCruisingSpeed_ = estimatedSpeed_;
    }

    // Wheeled vehicles on roads do not move in reverse during highway driving
    estimatedSpeed_ = std::max(0.0, estimatedSpeed_);

    // Soft GNSS blend when GNSS speed is available and confident
    if (gnssSpeedMps >= 0.5 && !isOutageMode_) {
        estimatedSpeed_ = estimatedSpeed_ * 0.85 + gnssSpeedMps * 0.15;
    }
}

void TcnSpeedEngine::checkStandstill(double gnssSpeedMps) {
    if (!isOutageMode_ && gnssSpeedMps >= 0.0 && gnssSpeedMps < 0.35) {
        // High confidence GNSS lock confirms stationary (< 1.2 km/h)
        isStandstill_ = true;
        quietCount_ = 5;
        estimatedSpeed_ = 0.0;
        return;
    }

    if (accelBuffer_.size() < 15) {
        return;
    }

    // Evaluate dynamic variance over the recent 20 samples
    int n = std::min(static_cast<int>(accelBuffer_.size()), 20);
    auto startIt = accelBuffer_.end() - n;
    auto startGyroIt = gyroBuffer_.end() - n;

    Vec3 mean{0, 0, 0};
    for (auto it = startIt; it != accelBuffer_.end(); ++it) {
        mean = mean + *it;
    }
    mean = mean * (1.0 / n);

    double yawSum = 0.0;
    double wNormSum = 0.0;
    for (auto it = startGyroIt; it != gyroBuffer_.end(); ++it) {
        yawSum += std::abs(it->z);
        wNormSum += std::sqrt(it->x * it->x + it->y * it->y + it->z * it->z);
    }
    double avgYaw = yawSum / n;
    double avgW = wNormSum / n;

    double varSum = 0.0;
    for (auto it = startIt; it != accelBuffer_.end(); ++it) {
        Vec3 d = *it - mean;
        varSum += (d.x * d.x + d.y * d.y + d.z * d.z);
    }
    accelVariance_ = varSum / n;

    double fwdAccel = std::abs(accelBuffer_.back().x);
    double latAccel = std::abs(accelBuffer_.back().y);

    // In a wheeled vehicle turning at speed v, centripetal acceleration is required (a_lat = v * w).
    double expectedLatA = estimatedSpeed_ * gyroBuffer_.back().z;
    double latResidual = std::abs(accelBuffer_.back().y - expectedLatA);
    double lastW = std::sqrt(gyroBuffer_.back().x * gyroBuffer_.back().x +
                             gyroBuffer_.back().y * gyroBuffer_.back().y +
                             gyroBuffer_.back().z * gyroBuffer_.back().z);
    double nonYawW = std::sqrt(gyroBuffer_.back().x * gyroBuffer_.back().x +
                               gyroBuffer_.back().y * gyroBuffer_.back().y);
    bool isPhoneRotatingInHand = (estimatedSpeed_ < 0.50 || isStandstill_) &&
        (nonYawW > 0.18 || (lastW > 0.25 && (nonYawW > 0.20 || latResidual > 1.5)));

    bool isCoupledTurn = (avgYaw > 0.25) && (latAccel > 0.60) && (latResidual < 2.0);

    if (isPhoneRotatingInHand) {
        isStandstill_ = true;
        quietCount_ = 5;
        estimatedSpeed_ = 0.0;
        return;
    }

    // Standstill condition: dynamic accel variance (< 2.5 m^2/s^4), no coupled turn,
    // low forward throttle, and accommodating physiological hand tremor (avgW < 0.35 rad/s, avgYaw < 0.18 rad/s).
    // Gated by low speed (< 1.2 m/s) to prevent smooth high-speed highway cruising in tunnels from falsely freezing.
    bool isQuiet = !isOutageMode_ && (estimatedSpeed_ < 1.2 || isStandstill_) &&
        (accelVariance_ < 2.5) && !isCoupledTurn && (avgW < 0.35 || avgYaw < 0.18) && (fwdAccel < 0.25);
    bool hasActiveMotion = isOutageMode_ || (accelVariance_ > 3.0) || isCoupledTurn || (fwdAccel > 0.40) || (!isStandstill_ && accelVariance_ > 1.2 && estimatedSpeed_ > 2.0);

    // Fast 5-sample hysteresis to avoid flapping
    if (isQuiet) {
        if (quietCount_ < 5) quietCount_++;
        if (quietCount_ >= 5) {
            isStandstill_ = true;
            estimatedSpeed_ = 0.0;
        }
    } else if (hasActiveMotion) {
        quietCount_ = 0;
        isStandstill_ = false;
    }
}

} // namespace idr
