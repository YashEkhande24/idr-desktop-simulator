#pragma once

#include <Eigen/Dense>
#include "idr/types.hpp"

namespace idr {

class Ekf3D {
public:
    using Vector6d = Eigen::Matrix<double, 6, 1>;
    using Matrix6d = Eigen::Matrix<double, 6, 6>;

    Ekf3D(double initYawRad = 0.0);

    // Kinematic propagation step (50-100 Hz) with closed-form SE(2) arc integration
    void predict(double dt, double vForward, double omegaZ, double pitchRad, double trustWeight = 1.0);

    // Dynamic Sideslip-Relaxed Non-Holonomic Constraint (NHC)
    void applyNhc(double sigmaNhc = 0.22, double latAccel = 0.0, double forwardSpeed = 0.0);

    // Straight-Line Zero Angular Rate Update (ZARU)
    void applyZaru(double rawGyroZ, double dt);

    // Straight-Line Zero Acceleration Update (ZACU)
    void applyZacu(double rawAccelX, double dt);

    // Geodetic latitude support
    void setLatitude(double latDeg) { latitudeDeg_ = latDeg; }
    double latitude() const { return latitudeDeg_; }

    // Standstill (ZUPT): Lock velocities to zero, decay covariance, calibrate gyro & accel biases
    void applyStandstill(double rawGyroZ, double rawAccelX = 0.0);

    // GNSS 3D position update with sigmoidal HDOP inflation and fast acquisition snap
    void updateGnss(const Vec3& gnssEnu, double hdop, double sigmaBase = 2.0);

    // Barometric altitude update
    void updateBaro(double altitudeM, double sigmaBaro = 1.5);

    // Third-Order Baro-Inertial vertical velocity damping update
    void updateBaroClimbRate(double vZBaro, double sigmaVz = 0.40);

    // GNSS ground course update (when vehicle speed > 0.6 m/s)
    void updateCourse(double courseRad, double speed, double hdop);

    // Tilt-compensated compass heading update with deadband, standstill gain attenuation, and magnetic disturbance rejection
    void updateCompass(double compassYawRad, double weight = 0.05, bool isStationary = false, double magneticFieldNorm = 0.0, double expectedFieldNorm = 45.0);

    // Module 5: Smart Map-Matching Filter Kalman Update
    void updateMapMatching(const Vec3& normal2D, double crossTrackDistance, double sigma, double roadElevation = -9999.0, double sigmaAlt = 2.5);

    // Iterated Extended Kalman Filter (IEKF) Gauss-Newton map update
    void updateMapMatchingIterated(const Vec3& normal2D, double crossTrackDistance, double sigma, double roadElevation = -9999.0, double sigmaAlt = 2.5, int maxIterations = 2);

    // Map Heading Constraint during GNSS Outage
    void updateMapHeading(double roadHeadingRad, double confidence);

    // TCN Speed Update with Heteroscedastic Variance Weighting
    void updateTcnSpeed(double vTcn, double variance = -1.0);

    // Reset filter
    void reset(const Vec3& initPos = {0, 0, 0}, double initYaw = 0.0);

    // Getters
    Vec3 position() const { return {x_(0), x_(1), x_(2)}; }
    Vec3 velocity() const { return {x_(4) * std::cos(x_(3)), x_(4) * std::sin(x_(3)), x_(5)}; }
    double yaw() const { return x_(3); }
    double forwardSpeed() const { return x_(4); }
    double climbRate() const { return x_(5); }
    double roll() const { return roll_; }
    double pitch() const { return pitch_; }
    double gyroBiasZ() const { return gyroBiasZ_; }
    double accelBiasX() const { return accelBiasX_; }

    double positionStd() const {
        return std::sqrt(P_(0, 0) + P_(1, 1) + P_(2, 2));
    }

    void setMountLeverArm(const Vec3& arm) { mountLeverArm_ = arm; }
    Vec3 mountLeverArm() const { return mountLeverArm_; }

    const Vector6d& stateVector() const { return x_; }
    const Matrix6d& covariance() const { return P_; }

private:
    Vector6d x_ = Vector6d::Zero(); // [x, y, z, yaw, v_fwd, v_z]
    Matrix6d P_ = Matrix6d::Identity();

    double roll_ = 0.0;
    double pitch_ = 0.0;
    double gyroBiasZ_ = 0.0;
    double accelBiasX_ = 0.0;
    double latitudeDeg_ = 20.0;
    Vec3 mountLeverArm_ = {1.25, 0.0, 0.45};
};

} // namespace idr
