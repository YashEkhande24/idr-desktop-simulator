#include "idr/vibration_gate.hpp"
#include <cmath>
#include <numeric>
#include <algorithm>

namespace idr {

VibrationGate::VibrationGate(double lambda, double shockThreshold, int windowSize)
    : lambda_(lambda), shockThreshold_(shockThreshold), windowSize_(windowSize) {}

void VibrationGate::reset() {
    trustWeight_ = 1.0;
    shockDetected_ = false;
    jerkVariance_ = 0.0;
    hasPrevAccel_ = false;
    jerkMagnitudes_.clear();
}

void VibrationGate::update(const Vec3& alignedAccel, double dt, bool isStationary) {
    if (dt <= 1e-4) return;

    // Stationary bypass: if stationary, do not trip shock gate on handling tremors
    if (isStationary) {
        trustWeight_ = 1.0;
        shockDetected_ = false;
        jerkVariance_ = 0.0;
        filteredAccel_ = alignedAccel;
        prevFilteredAccel_ = alignedAccel;
        hasPrevAccel_ = true;
        jerkMagnitudes_.clear();
        return;
    }

    // 1st-order low pass filter on acceleration (alpha = 0.25)
    constexpr double alpha = 0.25;
    if (!hasPrevAccel_) {
        filteredAccel_ = alignedAccel;
        prevFilteredAccel_ = alignedAccel;
        hasPrevAccel_ = true;
        return;
    }

    filteredAccel_ = filteredAccel_ * (1.0 - alpha) + alignedAccel * alpha;

    // Compute vehicle jerk vector
    Vec3 dAccel = filteredAccel_ - prevFilteredAccel_;
    prevFilteredAccel_ = filteredAccel_;

    Vec3 jerk = dAccel * (1.0 / dt);
    double jMag = jerk.norm();

    jerkMagnitudes_.push_back(jMag);
    if (static_cast<int>(jerkMagnitudes_.size()) > windowSize_) {
        jerkMagnitudes_.pop_front();
    }

    if (jerkMagnitudes_.size() < 3) {
        trustWeight_ = 1.0;
        shockDetected_ = false;
        jerkVariance_ = 0.0;
        return;
    }

    // Compute moving variance
    double sum = std::accumulate(jerkMagnitudes_.begin(), jerkMagnitudes_.end(), 0.0);
    double mean = sum / jerkMagnitudes_.size();

    double sqDiff = 0.0;
    for (double val : jerkMagnitudes_) {
        double d = val - mean;
        sqDiff += d * d;
    }
    jerkVariance_ = sqDiff / jerkMagnitudes_.size();

    // Clamp variance display to 500 to prevent astronomical spikes
    if (jerkVariance_ > 500.0) jerkVariance_ = 500.0;

    shockDetected_ = (jerkVariance_ >= shockThreshold_);

    // Continuous trust weight w_v = exp(-lambda * sigma_jerk^2)
    trustWeight_ = std::exp(-lambda_ * jerkVariance_);
    trustWeight_ = std::clamp(trustWeight_, 0.001, 1.0);
}

} // namespace idr
