#pragma once

#include <deque>
#include <vector>
#include "idr/types.hpp"

namespace idr {

class VibrationGate {
public:
    VibrationGate(double lambda = 0.05, double shockThreshold = 450.0, int windowSize = 10);

    // Update with vehicle-aligned acceleration sample
    void update(const Vec3& alignedAccel, double dt, bool isStationary = false);

    // Continuous trust weight in [0.0, 1.0]
    double trustWeight() const { return trustWeight_; }

    // Whether a severe pothole/speedbump shock is detected
    bool shockDetected() const { return shockDetected_; }

    // Current moving jerk variance (m^2/s^6)
    double jerkVariance() const { return jerkVariance_; }

    void reset();

private:
    double lambda_;
    double shockThreshold_;
    int windowSize_;

    double trustWeight_ = 1.0;
    bool shockDetected_ = false;
    double jerkVariance_ = 0.0;

    Vec3 filteredAccel_{0, 0, 0};
    Vec3 prevFilteredAccel_{0, 0, 0};
    bool hasPrevAccel_ = false;

    std::deque<double> jerkMagnitudes_;
};

} // namespace idr
