#pragma once

#include <Eigen/Dense>
#include <cmath>
#include <tuple>
#include "idr/types.hpp"

namespace idr {

constexpr double WGS84_A = 6378137.0;
constexpr double WGS84_F = 1.0 / 298.257223563;
constexpr double WGS84_E2 = 2.0 * WGS84_F - WGS84_F * WGS84_F;
constexpr double P_SEA_LEVEL_HPA = 1013.25;
constexpr double BARO_EXP = 0.190263; // R * L / (g * M)
constexpr double GRAVITY_STANDARD = 9.80665;
constexpr double PI = 3.14159265358979323846;

// Rotation matrices
Eigen::Matrix3d rotBodyToWorld(double roll, double pitch, double yaw);
Eigen::Matrix3d rotWorldToBody(double roll, double pitch, double yaw);
Eigen::Vector3d forwardUnitVector(double pitch, double yaw);

// Angular rate kinematic conversions
Eigen::Vector3d eulerRates(double roll, double pitch, const Eigen::Vector3d& gyro);
Eigen::Matrix3d eulerRateJacobian(double roll, double pitch);
Eigen::Vector3d bodyRates(double roll, double pitch, const Eigen::Vector3d& eulerDot);

// Atmospheric and barometric calculations
double altitudeFromPressure(double pressureHpa);
double pressureFromAltitude(double altitudeM);

// Sigmoidal HDOP scaling schedule
double sigmoid(double x, double gain = 1.0, double centre = 0.0);

// Coordinate geodetic conversions
Eigen::Vector3d geodeticToEcef(double latDeg, double lonDeg, double altM);
std::tuple<double, double, double> ecefToGeodetic(const Eigen::Vector3d& ecef);
Eigen::Vector3d geodeticToEnu(double latDeg, double lonDeg, double altM,
                             double refLatDeg, double refLonDeg, double refAltM);
std::tuple<double, double, double> enuToGeodetic(const Eigen::Vector3d& enu,
                                                 double refLatDeg, double refLonDeg, double refAltM);

// Navigational heading conversions
double enuToCompassDeg(double yawEnuRad);
double compassToEnuRad(double compassDeg);
double computeTiltCompensatedHeading(const Vec3& magUt, const Vec3& accel);

// Advanced geodesy & kinematics
double vincentyDistanceMeters(double lat1, double lon1, double lat2, double lon2);
double somiglianaNormalGravity(double latDeg, double altM = 0.0);
Eigen::Vector3d apparentAcceleration(const Eigen::Vector3d& vNav, double latDeg, double altM = 0.0);

} // namespace idr
