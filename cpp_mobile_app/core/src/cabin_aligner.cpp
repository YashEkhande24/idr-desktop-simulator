#include "idr/cabin_aligner.hpp"
#include "idr/common.hpp"
#include <cmath>

namespace idr {

CabinAligner::CabinAligner(int calibrationWindow)
    : calibrationWindow_(calibrationWindow) {
    gravitySamples_.reserve(calibrationWindow);
}

void CabinAligner::reset() {
    calibrated_ = false;
    pitch_ = 0.0;
    roll_ = 0.0;
    yaw_ = 0.0;
    R_mount_ = Eigen::Matrix3d::Identity();
    gravitySamples_.clear();
    horizontalAccels_.clear();
}

void CabinAligner::addSample(const Vec3& accel) {
    if (!calibrated_) {
        gravitySamples_.push_back(accel);
        if (static_cast<int>(gravitySamples_.size()) >= calibrationWindow_) {
            computeGravityAlignment();
        }
        return;
    }

    // After gravity leveling, accumulate horizontal acceleration for 2D PCA heading.
    Eigen::Vector3d a_body = R_mount_ * accel.toEigen();
    // In vehicle frame: x=forward, y=lateral, z=vertical
    horizontalAccels_.push_back({a_body.x(), a_body.y()});
    if (horizontalAccels_.size() > 200) {
        horizontalAccels_.pop_front();
    }

    // Only run PCA when there is significant directional motion energy.
    // When stationary, horizontal accel is isotropic sensor noise (~0.01-0.1 m²/s⁴ variance)
    // which produces random PCA directions. Real vehicle braking/acceleration
    // creates anisotropic variance > 0.5 m²/s⁴ along the forward axis.
    if (horizontalAccels_.size() >= 60) {
        // Quick variance check on horizontal acceleration magnitude
        Eigen::Vector2d hmean = Eigen::Vector2d::Zero();
        for (const auto& v : horizontalAccels_) {
            hmean += v;
        }
        hmean /= static_cast<double>(horizontalAccels_.size());
        double hvar = 0.0;
        for (const auto& v : horizontalAccels_) {
            Eigen::Vector2d d = v - hmean;
            hvar += d.squaredNorm();
        }
        hvar /= static_cast<double>(horizontalAccels_.size());

        // Only update PCA heading when there's real directional motion (variance > 0.5)
        if (hvar > 0.5) {
            computePcaHeading();
        }
    }
}

void CabinAligner::computeGravityAlignment() {
    if (gravitySamples_.empty()) return;

    Eigen::Vector3d g_mean = Eigen::Vector3d::Zero();
    for (const auto& s : gravitySamples_) {
        g_mean += s.toEigen();
    }
    g_mean /= static_cast<double>(gravitySamples_.size());

    double gx = g_mean.x(), gy = g_mean.y(), gz = g_mean.z();

    // Pitch: angle about y-axis to align z with gravity
    pitch_ = std::atan2(-gx, std::sqrt(gy * gy + gz * gz));
    // Roll: angle about x-axis
    roll_  = std::atan2(gy, gz);

    // Initial mount rotation matrix (leveling phone body into horizontal vehicle frame)
    R_mount_ = rotBodyToWorld(roll_, pitch_, yaw_);
    calibrated_ = true;
}

void CabinAligner::computePcaHeading() {
    if (horizontalAccels_.size() < 50) return;

    Eigen::Vector2d mean = Eigen::Vector2d::Zero();
    for (const auto& v : horizontalAccels_) {
        mean += v;
    }
    mean /= static_cast<double>(horizontalAccels_.size());

    double cxx = 0.0, cxy = 0.0, cyy = 0.0;
    for (const auto& v : horizontalAccels_) {
        Eigen::Vector2d d = v - mean;
        cxx += d.x() * d.x();
        cxy += d.x() * d.y();
        cyy += d.y() * d.y();
    }

    // Principal component direction theta = 0.5 * atan2(2 * cxy, cxx - cyy)
    double delta_yaw = 0.5 * std::atan2(2.0 * cxy, cxx - cyy);
    yaw_ += delta_yaw * 0.15; // Faster convergence (was 0.05)

    R_mount_ = rotBodyToWorld(roll_, pitch_, yaw_);
}

Vec3 CabinAligner::alignAccel(const Vec3& rawAccel) const {
    if (!calibrated_) return rawAccel;
    Eigen::Vector3d aligned = R_mount_ * rawAccel.toEigen();
    return Vec3(aligned.x(), aligned.y(), aligned.z() - GRAVITY_STANDARD);
}

Vec3 CabinAligner::alignGyro(const Vec3& rawGyro) const {
    if (!calibrated_) return rawGyro;
    Eigen::Vector3d aligned = R_mount_ * rawGyro.toEigen();
    return Vec3::fromEigen(aligned);
}

} // namespace idr
