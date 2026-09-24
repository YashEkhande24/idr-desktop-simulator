#include "idr/ekf_3d.hpp"
#include "idr/common.hpp"
#include <cmath>
#include <algorithm>

namespace idr {

Ekf3D::Ekf3D(double initYawRad) {
    reset({0, 0, 0}, initYawRad);
}

void Ekf3D::reset(const Vec3& initPos, double initYaw) {
    x_.setZero();
    x_(0) = initPos.x;
    x_(1) = initPos.y;
    x_(2) = initPos.z;
    x_(3) = initYaw;
    x_(4) = 0.0;
    x_(5) = 0.0;

    P_.setZero();
    P_(0, 0) = 1.0;
    P_(1, 1) = 1.0;
    P_(2, 2) = 2.0;
    P_(3, 3) = 0.01;
    P_(4, 4) = 0.25;
    P_(5, 5) = 0.20;

    roll_ = 0.0;
    pitch_ = 0.0;
    gyroBiasZ_ = 0.0;
    accelBiasX_ = 0.0;
}

void Ekf3D::predict(double dt, double vForward, double omegaZ, double pitchRad, double trustWeight) {
    pitch_ = pitchRad;
    double unbiasOmegaZ = omegaZ - gyroBiasZ_;

    double psi = x_(3);
    double psiNext = psi + unbiasOmegaZ * dt;

    bool isMoving = std::abs(vForward) >= 0.02;

    if (isMoving) {
        // Closed-form SE(2) circular arc displacement during turning
        double dx, dy;
        if (std::abs(unbiasOmegaZ) > 1e-4) {
            dx = vForward * (std::sin(psiNext) - std::sin(psi)) / unbiasOmegaZ;
            dy = vForward * (-std::cos(psiNext) + std::cos(psi)) / unbiasOmegaZ;
        } else {
            double midPsi = psi + 0.5 * unbiasOmegaZ * dt;
            double dist = vForward * dt * (1.0 - (unbiasOmegaZ * dt * unbiasOmegaZ * dt) / 24.0);
            dx = dist * std::cos(midPsi);
            dy = dist * std::sin(midPsi);
        }
        double dz = x_(5) * dt;

        x_(0) += dx;
        x_(1) += dy;
        x_(2) += dz;
        x_(3) = psiNext;
        x_(4) = vForward;

        // Analytical State Transition Jacobian F_t (6x6)
        Matrix6d F = Matrix6d::Identity();
        F(0, 3) = -vForward * std::sin(psiNext) * dt;
        F(0, 4) =  std::cos(psiNext) * dt;
        F(1, 3) =  vForward * std::cos(psiNext) * dt;
        F(1, 4) =  std::sin(psiNext) * dt;
        F(2, 5) =  dt;

        // Process Noise Covariance Q_t scaled inversely by vibration trust
        double qScale = 1.0 / std::max(trustWeight, 0.01);
        Matrix6d Q = Matrix6d::Zero();
        double sa = 0.15 * qScale;
        double dt2 = dt * dt;
        double dt3 = dt2 * dt;

        // Exact continuous-discrete Van Loan double-integration blocks
        Q(0, 0) = (1.0 / 3.0) * sa * dt3;
        Q(1, 1) = (1.0 / 3.0) * sa * dt3;
        Q(2, 2) = (1.0 / 3.0) * sa * dt3 * 2.0;

        Q(0, 4) = 0.5 * sa * dt2 * std::cos(psiNext);
        Q(4, 0) = Q(0, 4);
        Q(1, 4) = 0.5 * sa * dt2 * std::sin(psiNext);
        Q(4, 1) = Q(1, 4);
        Q(2, 5) = 0.5 * sa * dt2 * 0.5;
        Q(5, 2) = Q(2, 5);

        // Speed-dependent heading process noise scheduling:
        // Yaw uncertainty tightens at higher vehicle speed due to strong non-holonomic kinematic directionality,
        // and relaxes at low speed / crawl where turning maneuvers dominate.
        double speedFactor = std::max(0.35, 1.0 / (1.0 + 0.08 * std::max(0.0, forwardSpeed())));
        Q(3, 3) = 0.002 * dt * speedFactor;
        Q(4, 4) = sa * dt;
        Q(5, 5) = sa * dt * 0.5;

        // Covariance propagation: P = F * P * F^T + Q
        P_ = F * P_ * F.transpose() + Q;
    } else {
        // Standstill: completely freeze position propagation to prevent noise-driven creep!
        x_(3) = psiNext;
        x_(4) = 0.0;
        x_(5) = 0.0;

        // Propagate heading covariance only
        P_(3, 3) += 0.0005 * dt;
    }

    // Normalize yaw to [-PI, PI]
    while (x_(3) > PI)  x_(3) -= 2.0 * PI;
    while (x_(3) < -PI) x_(3) += 2.0 * PI;
}

void Ekf3D::applyNhc(double sigmaNhc, double latAccel, double forwardSpeed) {
    // Dynamic tire sideslip relaxation: in high-speed turns, centripetal acceleration creates tire slip
    double aRatio = std::abs(latAccel) / 9.80665;
    double vRatio = std::max(0.0, forwardSpeed) / 25.0;
    double inflation = 1.0 + 4.5 * (aRatio * aRatio) + 1.2 * (vRatio * vRatio * aRatio);
    double rNhc = (sigmaNhc * sigmaNhc) * std::clamp(inflation, 1.0, 10.0);

    P_(4, 4) = (P_(4, 4) * rNhc) / (P_(4, 4) + rNhc);
    // Vertical NHC: ground vehicles don't launch vertically
    x_(5) *= 0.95;
    P_(5, 5) = std::max(1e-6, P_(5, 5) * 0.95);
}

void Ekf3D::applyZaru(double rawGyroZ, double dt) {
    // Straight-Line Zero Angular Rate Update (ZARU)
    gyroBiasZ_ = std::clamp(gyroBiasZ_ * 0.98 + rawGyroZ * 0.02, -0.08, 0.08);
    P_(3, 3) = std::max(1e-6, P_(3, 3) * 0.98);
}

void Ekf3D::applyZacu(double rawAccelX, double dt) {
    // Straight-Line Zero Acceleration Update (ZACU)
    accelBiasX_ = std::clamp(accelBiasX_ * 0.98 + rawAccelX * 0.02, -0.25, 0.25);
}

void Ekf3D::applyStandstill(double rawGyroZ, double rawAccelX) {
    // Zero-velocity update: clamp forward velocity and climb rate
    x_(4) = 0.0;
    x_(5) = 0.0;
    P_(4, 4) = 0.0001;
    P_(5, 5) = 0.0001;

    // Shrink position covariance to suppress noise-driven wander, with tight physical floor (0.01 m^2)
    P_(0, 0) = std::max(0.01, P_(0, 0) * 0.992);
    P_(1, 1) = std::max(0.01, P_(1, 1) * 0.992);
    P_(2, 2) = std::max(0.01, P_(2, 2) * 0.992);
    P_(0, 1) *= 0.992;
    P_(1, 0) *= 0.992;

    // Continuously trim gyro z-bias and forward accel bias while stopped
    gyroBiasZ_ = std::clamp(gyroBiasZ_ * 0.95 + rawGyroZ * 0.05, -0.08, 0.08);
    accelBiasX_ = std::clamp(accelBiasX_ * 0.95 + rawAccelX * 0.05, -0.20, 0.20);
}

void Ekf3D::updateGnss(const Vec3& gnssEnu, double hdop, double sigmaBase) {
    // Sigmoidal HDOP Inflation
    double s = sigmoid(hdop, 2.0, 3.5);
    double rFactor = 1.0 + 100.0 * s;
    double varPos = (sigmaBase * sigmaBase) * rFactor;

    // 3D GNSS Mount Lever-Arm Antenna Translation: p_axle = p_gnss - R * r_mount
    Eigen::Matrix3d Rmount = rotBodyToWorld(roll_, pitch_, x_(3));
    Eigen::Vector3d armNav = Rmount * mountLeverArm_.toEigen();
    double effX = gnssEnu.x - armNav.x();
    double effY = gnssEnu.y - armNav.y();
    double effZ = gnssEnu.z - armNav.z();

    double dx = effX - x_(0);
    double dy = effY - x_(1);
    double dist2 = dx * dx + dy * dy;

    // Fast Acquisition / Snap on GPS teleport or large initial offset with confident fix
    if (hdop <= 4.0 && (dist2 > 225.0 || (x_(0) == 0.0 && x_(1) == 0.0 && (effX != 0.0 || effY != 0.0)))) {
        x_(0) = effX;
        x_(1) = effY;
        x_(2) = effZ;
        P_(0, 0) = varPos;
        P_(1, 1) = varPos;
        P_(2, 2) = varPos * 3.0;
        return;
    }

    // 3D Chi-Square Mahalanobis Innovation Gating (3 DOF, critical = 14.16 for 3-sigma)
    double innCovX = P_(0, 0) + varPos;
    double innCovY = P_(1, 1) + varPos;
    double innCovZ = P_(2, 2) + varPos * 3.0;
    double dz = effZ - x_(2);
    double mahalanobis = (dx * dx) / innCovX + (dy * dy) / innCovY + (dz * dz) / innCovZ;
    if (mahalanobis > 14.16 && rFactor > 5.0) {
        return; // Reject GNSS outlier during degraded multi-path or outage
    }

    // Measurement matrix H: 3x6 observing [x, y, z]
    Eigen::Matrix<double, 3, 6> H = Eigen::Matrix<double, 3, 6>::Zero();
    H(0, 0) = 1.0;
    H(1, 1) = 1.0;
    H(2, 2) = 1.0;

    Eigen::Matrix3d R = Eigen::Matrix3d::Identity() * varPos;
    R(2, 2) *= 3.0; // Altitude is ~3x noisier

    // Innovation
    Eigen::Vector3d z(effX, effY, effZ);
    Eigen::Vector3d y = z - H * x_;

    // Innovation covariance S = H * P * H^T + R
    Eigen::Matrix3d S = H * P_ * H.transpose() + R;

    // Kalman Gain K = P * H^T * S^-1
    Eigen::Matrix<double, 6, 3> K = P_ * H.transpose() * S.inverse();

    // State update
    x_ += K * y;

    // Joseph-form covariance update: P = (I - K*H)*P*(I - K*H)^T + K*R*K^T
    Matrix6d I = Matrix6d::Identity();
    Matrix6d I_KH = I - K * H;
    P_ = I_KH * P_ * I_KH.transpose() + K * R * K.transpose();

    // Enforce physical minimum floor (0.05 m^2 horizontal, 0.1 m^2 vertical)
    P_(0, 0) = std::max(0.05, P_(0, 0));
    P_(1, 1) = std::max(0.05, P_(1, 1));
    P_(2, 2) = std::max(0.10, P_(2, 2));
}

void Ekf3D::updateBaro(double altitudeM, double sigmaBaro) {
    double r = sigmaBaro * sigmaBaro;
    double y = altitudeM - x_(2);
    double s = P_(2, 2) + r;
    if (s > 1e-9) {
        double k = P_(2, 2) / s;
        x_(2) += k * y;
        P_(2, 2) = std::max(1e-6, (1.0 - k) * P_(2, 2));
    }
}

void Ekf3D::updateBaroClimbRate(double vZBaro, double sigmaVz) {
    double r = sigmaVz * sigmaVz;
    double y = vZBaro - x_(5);
    double s = P_(5, 5) + r;
    if (s > 1e-9) {
        double k = P_(5, 5) / s;
        x_(5) += k * y;
        P_(5, 5) = std::max(1e-6, (1.0 - k) * P_(5, 5));
    }
}

void Ekf3D::updateCourse(double courseRad, double speed, double hdop) {
    if (speed < 0.6 || hdop > 5.0) return; // Only update when moving with reliable GNSS

    double diff = courseRad - x_(3);
    while (diff > PI)  diff -= 2.0 * PI;
    while (diff < -PI) diff += 2.0 * PI;

    double rCourse = 0.04 * std::max(1.0, hdop);
    double s = P_(3, 3) + rCourse;
    if (s > 1e-6) {
        double k = P_(3, 3) / s;
        x_(3) += k * diff;
        P_(3, 3) = std::max(1e-6, (1.0 - k) * P_(3, 3));
        while (x_(3) > PI)  x_(3) -= 2.0 * PI;
        while (x_(3) < -PI) x_(3) += 2.0 * PI;

        // Calibrate gyro bias from heading residual integral term
        gyroBiasZ_ = std::clamp(gyroBiasZ_ - 0.02 * diff, -0.08, 0.08);
    }
}

void Ekf3D::updateCompass(double compassYawRad, double weight, bool isStationary, double magneticFieldNorm, double expectedFieldNorm) {
    double diff = compassYawRad - x_(3);
    while (diff > PI)  diff -= 2.0 * PI;
    while (diff < -PI) diff += 2.0 * PI;

    // Angular deadband: skip update if angular noise is tiny (< 0.02 rad ~ 1.1 deg)
    if (std::abs(diff) < 0.02) return;

    // Gentle gain at rest (0.01) to prevent heading micro-oscillations driving position creep
    double effWeight = isStationary ? 0.01 : weight;

    // Adaptive magnetic disturbance rejection: downweight if field magnitude deviates from expected
    if (magneticFieldNorm > 0.0 && expectedFieldNorm > 0.0) {
        double devPct = std::abs(magneticFieldNorm - expectedFieldNorm) / expectedFieldNorm;
        if (devPct > 0.15) {
            effWeight /= (1.0 + 10.0 * (devPct - 0.15));
        }
    }

    x_(3) += diff * effWeight;

    while (x_(3) > PI)  x_(3) -= 2.0 * PI;
    while (x_(3) < -PI) x_(3) += 2.0 * PI;
}

void Ekf3D::updateMapMatching(const Vec3& normal2D, double crossTrackDistance, double sigma, double roadElevation, double sigmaAlt) {
    double rMap = sigma * sigma;

    // Observation matrix H = [nx, ny, 0, 0, 0, 0]
    Eigen::Matrix<double, 1, 6> H = Eigen::Matrix<double, 1, 6>::Zero();
    H(0, 0) = normal2D.x;
    H(0, 1) = normal2D.y;

    double absDist = std::abs(crossTrackDistance);
    const double laneDeadband = 1.75;
    double effectiveDist = 0.0;
    if (absDist > laneDeadband) {
        double excess = absDist - laneDeadband;
        double huberW = (excess <= 2.5) ? 1.0 : (2.5 / excess);
        effectiveDist = ((crossTrackDistance > 0) ? excess : -excess) * huberW;
    }

    double S = (H * P_ * H.transpose())(0, 0) + rMap;
    if (S > 1e-9 && std::abs(effectiveDist) > 1e-4) {
        Eigen::Matrix<double, 6, 1> K = P_ * H.transpose() / S;
        double inn = -effectiveDist;
        x_ += K * inn;

        Matrix6d I = Matrix6d::Identity();
        Matrix6d I_KH = I - K * H;
        P_ = I_KH * P_ * I_KH.transpose() + K * rMap * K.transpose();
        P_(0, 0) = std::max(1e-6, P_(0, 0));
        P_(1, 1) = std::max(1e-6, P_(1, 1));
    }

    // Vertical road deck constraint
    if (roadElevation > -9000.0) {
        double rAlt = sigmaAlt * sigmaAlt;
        double sZ = P_(2, 2) + rAlt;
        if (sZ > 1e-9) {
            double kZ = P_(2, 2) / sZ;
            x_(2) += kZ * (roadElevation - x_(2));
            P_(2, 2) = std::max(1e-6, P_(2, 2) * (1.0 - kZ));
        }
    }
}

void Ekf3D::updateMapMatchingIterated(const Vec3& normal2D, double crossTrackDistance, double sigma, double roadElevation, double sigmaAlt, int maxIterations) {
    updateMapMatching(normal2D, crossTrackDistance, sigma, roadElevation, sigmaAlt);
    if (maxIterations > 1 && std::abs(crossTrackDistance) > 3.0) {
        updateMapMatching(normal2D, crossTrackDistance * 0.35, sigma * 1.5, roadElevation, sigmaAlt);
    }
}

void Ekf3D::updateMapHeading(double roadHeadingRad, double confidence) {
    if (confidence < 0.45) return;
    double resid = roadHeadingRad - x_(3);
    while (resid > PI)  resid -= 2.0 * PI;
    while (resid < -PI) resid += 2.0 * PI;

    if (std::abs(resid) > 0.52) return; // ~30 degrees max alignment threshold

    double rHead = 0.08 / std::max(0.1, confidence);
    double s = P_(3, 3) + rHead;
    if (s > 1e-9) {
        double k = P_(3, 3) / s;
        x_(3) += k * resid;
        P_(3, 3) = std::max(1e-6, P_(3, 3) * (1.0 - k));
        while (x_(3) > PI)  x_(3) -= 2.0 * PI;
        while (x_(3) < -PI) x_(3) += 2.0 * PI;
    }
}

void Ekf3D::updateTcnSpeed(double vTcn, double variance) {
    double rTcn = (variance > 0.0) ? std::clamp(variance, 0.04, 4.0) : (0.25 * 0.25);
    double s = P_(4, 4) + rTcn;
    if (s > 1e-9) {
        double k = P_(4, 4) / s;
        x_(4) += k * (vTcn - x_(4));
        P_(4, 4) = std::max(1e-6, P_(4, 4) * (1.0 - k));
    }
}

} // namespace idr
