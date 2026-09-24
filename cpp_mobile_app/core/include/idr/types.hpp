#pragma once

#include <Eigen/Dense>
#include <vector>
#include <string>
#include <cmath>
#include <cstdint>

namespace idr {

struct Vec3 {
    double x = 0.0;
    double y = 0.0;
    double z = 0.0;

    Vec3() = default;
    Vec3(double _x, double _y, double _z) : x(_x), y(_y), z(_z) {}

    Eigen::Vector3d toEigen() const { return {x, y, z}; }
    static Vec3 fromEigen(const Eigen::Vector3d& v) { return {v.x(), v.y(), v.z()}; }

    double norm() const { return std::sqrt(x * x + y * y + z * z); }
    Vec3 operator+(const Vec3& o) const { return {x + o.x, y + o.y, z + o.z}; }
    Vec3 operator-(const Vec3& o) const { return {x - o.x, y - o.y, z - o.z}; }
    Vec3 operator*(double s) const { return {x * s, y * s, z * s}; }
};

struct ImuSample {
    double timestamp = 0.0; // seconds
    Vec3 accel;             // m/s^2 (specific force)
    Vec3 gyro;              // rad/s (angular rates p, q, r)
};

struct GnssSample {
    double timestamp = 0.0;
    double lat = 0.0;       // degrees
    double lon = 0.0;       // degrees
    double alt = 0.0;       // meters WGS84
    double hdop = 1.0;
    double speed = 0.0;     // m/s ground speed
    double course = 0.0;    // degrees true North [0, 360)
};

struct BaroSample {
    double timestamp = 0.0;
    double pressureHpa = 1013.25;
    double altitude = 0.0;
};

struct MagSample {
    double timestamp = 0.0;
    Vec3 magField;          // microteslas (uT)
    double headingDeg = 0.0;// tilt-compensated compass [0, 360)
};

struct NavSolution {
    double timestamp = 0.0;
    Vec3 positionEnu;       // meters [East, North, Up]
    Vec3 velocity;          // [v_forward, v_lateral, v_climb]
    double yawRad = 0.0;    // ENU yaw: 0 = East, counter-clockwise
    double headingDeg = 0.0;// Navigational Azimuth: 0 = North, [0, 360) clockwise
    double rollRad = 0.0;
    double pitchRad = 0.0;

    // Diagnostics & Covariance
    double positionStd = 0.0; // sqrt(trace(P_pos))
    double hdop = 1.0;
    double trustWeight = 1.0;
    bool isShock = false;
    bool isStandstill = false;
    bool isOutage = false;

    // Error comparisons
    double idrDrift = 0.0;     // meters from ground truth/nominal
    double classicDrift = 0.0; // meters from ground truth/nominal

    // Extended diagnostics
    double gyroBiasZ = 0.0;
    double accelBiasX = 0.0;
    double forwardSpeed = 0.0;
    double climbRate = 0.0;
    double cabinConfidence = 0.0;
    bool isCabinLocked = false;
    bool isPedestrian = false;
    double rawJerk = 0.0;
    double jerkVariance = 0.0;
    double covDiagonal[6] = {0.0, 0.0, 0.0, 0.0, 0.0, 0.0};
};

} // namespace idr
