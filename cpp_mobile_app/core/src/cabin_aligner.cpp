#include "idr/cabin_aligner.hpp"
#include "idr/common.hpp"
#include <cmath>
#include <algorithm>

namespace idr {

CabinAligner::CabinAligner(int calibrationWindow)
    : calibrationWindow_(calibrationWindow) {
    gravitySamples_.reserve(calibrationWindow);
}

void CabinAligner::reset() {
    calibrated_ = headingLocked_ = false;
    pitch_ = roll_ = yaw_ = 0.0;
    R_level_ = R_mount_ = Eigen::Matrix3d::Identity();
    gravitySamples_.clear();
    horizontalAccels_.clear();
    pcaUpdates_ = decim_ = signCount_ = 0;
    signCorr_ = 0.0;
}

void CabinAligner::addSample(const Vec3& accel, const Vec3& gyro) {
    if (!calibrated_) {
        gravitySamples_.push_back(accel);
        if (static_cast<int>(gravitySamples_.size()) >= calibrationWindow_) {
            computeGravityAlignment();
        }
        return;
    }

    // Leveled, yaw-free frame: buffer stays consistent regardless of yaw evolution
    const Eigen::Vector3d a_lvl = R_level_ * accel.toEigen();
    const double wz_lvl = (R_level_ * gyro.toEigen()).z();

    // Turn rejection: centripetal acceleration lies along the lateral axis and corrupts longitudinal PCA
    if (std::abs(wz_lvl) > 0.08) return; // ~4.6 deg/s

    horizontalAccels_.push_back({a_lvl.x(), a_lvl.y()});
    if (horizontalAccels_.size() > 200) {
        horizontalAccels_.pop_front();
    }

    // Decimate: run PCA every 10 samples once window is populated
    if (horizontalAccels_.size() >= 60 && (++decim_ % 10) == 0) {
        computePcaHeading();
    }
}

void CabinAligner::computeGravityAlignment() {
    if (gravitySamples_.empty()) return;

    const double n = static_cast<double>(gravitySamples_.size());
    Eigen::Vector3d mean = Eigen::Vector3d::Zero();
    for (const auto& s : gravitySamples_) {
        mean += s.toEigen();
    }
    mean /= n;

    Eigen::Vector3d var = Eigen::Vector3d::Zero();
    for (const auto& s : gravitySamples_) {
        var += (s.toEigen() - mean).cwiseAbs2();
    }
    var /= n;

    // Stationarity check: |g| must be within 0.4 m/s^2 of 9.80665 and max variance < 0.05
    if (std::abs(mean.norm() - GRAVITY_STANDARD) > 0.4 || var.maxCoeff() > 0.05) {
        // Discard older half of noisy samples and continue gathering
        gravitySamples_.erase(gravitySamples_.begin(), gravitySamples_.begin() + gravitySamples_.size() / 2);
        return;
    }

    double gx = mean.x(), gy = mean.y(), gz = mean.z();
    pitch_ = std::atan2(-gx, std::sqrt(gy * gy + gz * gz));
    roll_  = std::atan2(gy, gz);

    // ZYX leveling composition: R_level = Ry(pitch) * Rx(roll)
    R_level_ = (Eigen::AngleAxisd(pitch_, Eigen::Vector3d::UnitY()) *
                Eigen::AngleAxisd(roll_,  Eigen::Vector3d::UnitX())).toRotationMatrix();
    yaw_ = 0.0;
    R_mount_ = R_level_;
    calibrated_ = true;
}

void CabinAligner::computePcaHeading() {
    const double n = static_cast<double>(horizontalAccels_.size());
    if (n < 50) return;

    Eigen::Vector2d mean = Eigen::Vector2d::Zero();
    for (const auto& v : horizontalAccels_) {
        mean += v;
    }
    mean /= n;

    double cxx = 0.0, cxy = 0.0, cyy = 0.0;
    for (const auto& v : horizontalAccels_) {
        const Eigen::Vector2d d = v - mean;
        cxx += d.x() * d.x();
        cxy += d.x() * d.y();
        cyy += d.y() * d.y();
    }
    cxx /= n;
    cxy /= n;
    cyy /= n;

    // Eigenvalues: require longitudinal energy AND anisotropy
    const double tr = cxx + cyy;
    const double disc = std::sqrt((cxx - cyy) * (cxx - cyy) + 4.0 * cxy * cxy);
    const double l1 = 0.5 * (tr + disc);
    const double l2 = 0.5 * (tr - disc);
    if (l1 < 0.5 || l1 < 4.0 * std::max(l2, 1e-6)) return;

    // Principal axis angle in leveled phone frame in (-pi/2, pi/2]
    const double theta = 0.5 * std::atan2(2.0 * cxy, cxx - cyy);
    double err = wrapPi(-theta - yaw_);
    if (err >  3.14159265358979323846 / 2.0) err -= 3.14159265358979323846;
    if (err < -3.14159265358979323846 / 2.0) err += 3.14159265358979323846;

    const double gain = (pcaUpdates_ < 20) ? 0.3 : 0.05;
    yaw_ = wrapPi(yaw_ + gain * err);
    ++pcaUpdates_;

    R_mount_ = Eigen::AngleAxisd(yaw_, Eigen::Vector3d::UnitZ()).toRotationMatrix() * R_level_;
}

void CabinAligner::resolveForwardSign(double gnssLongAccel, double alignedAx) {
    if (!calibrated_ || pcaUpdates_ < 5 || std::abs(gnssLongAccel) < 0.4) return;
    signCorr_ += alignedAx * gnssLongAccel;
    if (++signCount_ < 15) return;
    if (signCorr_ < 0.0) {
        yaw_ = wrapPi(yaw_ + 3.14159265358979323846);
        R_mount_ = Eigen::AngleAxisd(yaw_, Eigen::Vector3d::UnitZ()).toRotationMatrix() * R_level_;
    }
    headingLocked_ = true;
    signCorr_ = 0.0;
    signCount_ = 0;
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
