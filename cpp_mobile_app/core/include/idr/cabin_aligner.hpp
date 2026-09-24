#pragma once

#include <Eigen/Dense>
#include <vector>
#include <deque>
#include "idr/types.hpp"

namespace idr {

class CabinAligner {
public:
    CabinAligner(int calibrationWindow = 100);

    // Feed raw phone accelerometer sample (m/s^2)
    void addSample(const Vec3& accel);

    // Check if gravity-level calibration is ready
    bool isCalibrated() const { return calibrated_; }
    bool isLocked() const { return calibrated_; }
    double confidence() const {
        if (!calibrated_) {
            return (calibrationWindow_ > 0) ? (static_cast<double>(gravitySamples_.size()) / calibrationWindow_ * 0.5) : 0.0;
        }
        return (horizontalAccels_.size() >= 100) ? 0.95 : 0.70;
    }

    // Transform raw phone acceleration into vehicle cabin frame
    Vec3 alignAccel(const Vec3& rawAccel) const;

    // Transform raw phone angular velocity into vehicle cabin frame
    Vec3 alignGyro(const Vec3& rawGyro) const;

    // Direct access to estimated mount attitude
    double mountPitch() const { return pitch_; }
    double mountRoll()  const { return roll_; }
    double mountYaw()   const { return yaw_; }
    double mountPitchDeg() const { return pitch_ * 180.0 / 3.14159265358979323846; }
    double mountRollDeg()  const { return roll_ * 180.0 / 3.14159265358979323846; }
    double mountYawDeg()   const { return yaw_ * 180.0 / 3.14159265358979323846; }

    const Eigen::Matrix3d& rotationMatrix() const { return R_mount_; }

    void reset();

private:
    void computeGravityAlignment();
    void computePcaHeading();

    int calibrationWindow_;
    bool calibrated_ = false;
    double pitch_ = 0.0; // mount pitch (radians)
    double roll_  = 0.0; // mount roll (radians)
    double yaw_   = 0.0; // mount yaw (radians)

    Eigen::Matrix3d R_mount_ = Eigen::Matrix3d::Identity();
    std::vector<Vec3> gravitySamples_;
    std::deque<Eigen::Vector2d> horizontalAccels_;
};

} // namespace idr
