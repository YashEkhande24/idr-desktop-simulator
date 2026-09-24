#include "idr/common.hpp"
#include <algorithm>

namespace idr {

static inline double deg2rad(double deg) { return deg * (PI / 180.0); }
static inline double rad2deg(double rad) { return rad * (180.0 / PI); }

Eigen::Matrix3d rotBodyToWorld(double roll, double pitch, double yaw) {
    double cr = std::cos(roll),  sr = std::sin(roll);
    double cp = std::cos(pitch), sp = std::sin(pitch);
    double cy = std::cos(yaw),   sy = std::sin(yaw);

    Eigen::Matrix3d Rx, Ry, Rz;
    Rx << 1,  0,   0,
          0, cr, -sr,
          0, sr,  cr;

    Ry <<  cp, 0, sp,
            0, 1,  0,
          -sp, 0, cp;

    Rz << cy, -sy, 0,
          sy,  cy, 0,
           0,   0, 1;

    return Rz * Ry * Rx;
}

Eigen::Matrix3d rotWorldToBody(double roll, double pitch, double yaw) {
    return rotBodyToWorld(roll, pitch, yaw).transpose();
}

Eigen::Vector3d forwardUnitVector(double pitch, double yaw) {
    double cp = std::cos(pitch);
    return {cp * std::cos(yaw), cp * std::sin(yaw), std::sin(pitch)};
}

Eigen::Vector3d eulerRates(double roll, double pitch, const Eigen::Vector3d& gyro) {
    double p = gyro.x(), q = gyro.y(), r = gyro.z();
    double cp = std::cos(pitch);
    cp = (cp != 0.0) ? std::copysign(std::max(std::abs(cp), 1e-4), cp) : 1e-4;

    double sr = std::sin(roll), cr = std::cos(roll);
    double yaw_dot   = (q * sr + r * cr) / cp;
    double pitch_dot = -q * cr + r * sr;
    double roll_dot  = p + yaw_dot * std::sin(pitch);
    return {roll_dot, pitch_dot, yaw_dot};
}

Eigen::Matrix3d eulerRateJacobian(double roll, double pitch) {
    double cp = std::cos(pitch);
    cp = (cp != 0.0) ? std::copysign(std::max(std::abs(cp), 1e-4), cp) : 1e-4;
    double tp = std::sin(pitch) / cp;
    double sr = std::sin(roll), cr = std::cos(roll);

    Eigen::Matrix3d J;
    J << 1.0,  tp * sr,    tp * cr,
         0.0, -cr,         sr,
         0.0,  sr / cp,    cr / cp;
    return J;
}

Eigen::Vector3d bodyRates(double roll, double pitch, const Eigen::Vector3d& eulerDot) {
    double roll_dot = eulerDot.x(), pitch_dot = eulerDot.y(), yaw_dot = eulerDot.z();
    double a = yaw_dot * std::cos(pitch);
    double sr = std::sin(roll), cr = std::cos(roll);
    double q = a * sr - pitch_dot * cr;
    double r = a * cr + pitch_dot * sr;
    double p = roll_dot - yaw_dot * std::sin(pitch);
    return {p, q, r};
}

double altitudeFromPressure(double pressureHpa) {
    return 44330.0 * (1.0 - std::pow(pressureHpa / P_SEA_LEVEL_HPA, BARO_EXP));
}

double pressureFromAltitude(double altitudeM) {
    return P_SEA_LEVEL_HPA * std::pow(1.0 - altitudeM / 44330.0, 1.0 / BARO_EXP);
}

double sigmoid(double x, double gain, double centre) {
    double z = gain * (x - centre);
    if (z >= 0.0) {
        return 1.0 / (1.0 + std::exp(-std::min(z, 60.0)));
    }
    double e = std::exp(std::max(z, -60.0));
    return e / (1.0 + e);
}

Eigen::Vector3d geodeticToEcef(double latDeg, double lonDeg, double altM) {
    double phi = deg2rad(latDeg);
    double lam = deg2rad(lonDeg);
    double sphi = std::sin(phi), cphi = std::cos(phi);
    double slam = std::sin(lam), clam = std::cos(lam);

    double N = WGS84_A / std::sqrt(1.0 - WGS84_E2 * sphi * sphi);
    double x = (N + altM) * cphi * clam;
    double y = (N + altM) * cphi * slam;
    double z = (N * (1.0 - WGS84_E2) + altM) * sphi;
    return {x, y, z};
}

std::tuple<double, double, double> ecefToGeodetic(const Eigen::Vector3d& ecef) {
    double x = ecef.x(), y = ecef.y(), z = ecef.z();
    double p = std::sqrt(x * x + y * y);
    if (p < 1e-6) {
        double lat = (z >= 0) ? 90.0 : -90.0;
        return {lat, 0.0, std::abs(z) - WGS84_A * (1.0 - WGS84_F)};
    }

    double lon = rad2deg(std::atan2(y, x));
    double lat = std::atan2(z, p * (1.0 - WGS84_E2));

    for (int i = 0; i < 5; ++i) {
        double sphi = std::sin(lat);
        double N = WGS84_A / std::sqrt(1.0 - WGS84_E2 * sphi * sphi);
        lat = std::atan2(z + WGS84_E2 * N * sphi, p);
    }

    double sphi = std::sin(lat);
    double N = WGS84_A / std::sqrt(1.0 - WGS84_E2 * sphi * sphi);
    double alt = p / std::cos(lat) - N;
    return {rad2deg(lat), lon, alt};
}

Eigen::Vector3d geodeticToEnu(double latDeg, double lonDeg, double altM,
                             double refLatDeg, double refLonDeg, double refAltM) {
    Eigen::Vector3d p = geodeticToEcef(latDeg, lonDeg, altM);
    Eigen::Vector3d p0 = geodeticToEcef(refLatDeg, refLonDeg, refAltM);
    Eigen::Vector3d d = p - p0;

    double phi = deg2rad(refLatDeg);
    double lam = deg2rad(refLonDeg);
    double sphi = std::sin(phi), cphi = std::cos(phi);
    double slam = std::sin(lam), clam = std::cos(lam);

    Eigen::Matrix3d R;
    R << -slam,          clam,         0.0,
         -sphi * clam,  -sphi * slam,  cphi,
          cphi * clam,   cphi * slam,  sphi;

    return R * d;
}

std::tuple<double, double, double> enuToGeodetic(const Eigen::Vector3d& enu,
                                                 double refLatDeg, double refLonDeg, double refAltM) {
    Eigen::Vector3d p0 = geodeticToEcef(refLatDeg, refLonDeg, refAltM);
    double phi = deg2rad(refLatDeg);
    double lam = deg2rad(refLonDeg);
    double sphi = std::sin(phi), cphi = std::cos(phi);
    double slam = std::sin(lam), clam = std::cos(lam);

    Eigen::Matrix3d R;
    R << -slam,          clam,         0.0,
         -sphi * clam,  -sphi * slam,  cphi,
          cphi * clam,   cphi * slam,  sphi;

    Eigen::Vector3d ecef = p0 + R.transpose() * enu;
    return ecefToGeodetic(ecef);
}

double enuToCompassDeg(double yawEnuRad) {
    double deg = 90.0 - rad2deg(yawEnuRad);
    deg = std::fmod(deg, 360.0);
    if (deg < 0.0) deg += 360.0;
    return deg;
}

double compassToEnuRad(double compassDeg) {
    double enuDeg = 90.0 - compassDeg;
    return deg2rad(enuDeg);
}

double computeTiltCompensatedHeading(const Vec3& magUt, const Vec3& accel) {
    Eigen::Vector3d G(accel.x, accel.y, accel.z);
    double gNorm = G.norm();
    if (gNorm < 1e-4) return 0.0;
    G /= gNorm;

    Eigen::Vector3d M(magUt.x, magUt.y, magUt.z);
    double mNorm = M.norm();
    if (mNorm < 1e-4) return 0.0;
    M /= mNorm;

    Eigen::Vector3d E = M.cross(G);
    double eNorm = E.norm();
    if (eNorm < 1e-4) return 0.0;
    E /= eNorm;

    Eigen::Vector3d N = G.cross(E);
    double heading = rad2deg(std::atan2(E.y(), N.y()));
    if (heading < 0.0) heading += 360.0;
    return heading;
}

double vincentyDistanceMeters(double lat1, double lon1, double lat2, double lon2) {
    if (std::abs(lat1 - lat2) < 1e-11 && std::abs(lon1 - lon2) < 1e-11) {
        return 0.0;
    }

    constexpr double a = WGS84_A;
    constexpr double f = WGS84_F;
    constexpr double b = a * (1.0 - f);

    double phi1 = deg2rad(lat1);
    double phi2 = deg2rad(lat2);
    double u1 = std::atan((1.0 - f) * std::tan(phi1));
    double u2 = std::atan((1.0 - f) * std::tan(phi2));
    double l = deg2rad(lon2 - lon1);

    double sinU1 = std::sin(u1), cosU1 = std::cos(u1);
    double sinU2 = std::sin(u2), cosU2 = std::cos(u2);

    double lambda = l;
    double lambdaPrev = l;
    int iterLimit = 100;
    double sinSigma = 0.0, cosSigma = 0.0, sigma = 0.0;
    double sinAlpha = 0.0, cos2Alpha = 0.0, cos2SigmaM = 0.0;

    do {
        double sinLambda = std::sin(lambda);
        double cosLambda = std::cos(lambda);

        double term1 = cosU2 * sinLambda;
        double term2 = cosU1 * sinU2 - sinU1 * cosU2 * cosLambda;
        sinSigma = std::sqrt(term1 * term1 + term2 * term2);

        if (std::abs(sinSigma) < 1e-12) return 0.0;

        cosSigma = sinU1 * sinU2 + cosU1 * cosU2 * cosLambda;
        sigma = std::atan2(sinSigma, cosSigma);

        sinAlpha = (cosU1 * cosU2 * sinLambda) / sinSigma;
        cos2Alpha = 1.0 - sinAlpha * sinAlpha;

        cos2SigmaM = (std::abs(cos2Alpha) < 1e-12) ? 0.0 : (cosSigma - 2.0 * sinU1 * sinU2 / cos2Alpha);

        double c = (f / 16.0) * cos2Alpha * (4.0 + f * (4.0 - 3.0 * cos2Alpha));
        lambdaPrev = lambda;
        lambda = l + (1.0 - c) * f * sinAlpha * (sigma + c * sinSigma * (cos2SigmaM + c * cosSigma * (-1.0 + 2.0 * cos2SigmaM * cos2SigmaM)));
    } while (std::abs(lambda - lambdaPrev) > 1e-12 && --iterLimit > 0);

    double uSq = cos2Alpha * ((a * a - b * b) / (b * b));
    double bigA = 1.0 + (uSq / 16384.0) * (4096.0 + uSq * (-768.0 + uSq * (320.0 - 175.0 * uSq)));
    double bigB = (uSq / 1024.0) * (256.0 + uSq * (-128.0 + uSq * (74.0 - 47.0 * uSq)));
    double deltaSigma = bigB * sinSigma * (cos2SigmaM + 0.25 * bigB * (cosSigma * (-1.0 + 2.0 * cos2SigmaM * cos2SigmaM) -
        (bigB / 6.0) * cos2SigmaM * (-3.0 + 4.0 * sinSigma * sinSigma) * (-3.0 + 4.0 * cos2SigmaM * cos2SigmaM)));

    return b * bigA * (sigma - deltaSigma);
}

double somiglianaNormalGravity(double latDeg, double altM) {
    double phi = deg2rad(latDeg);
    double sinPhi = std::sin(phi);
    double sin2Phi = sinPhi * sinPhi;
    constexpr double gammaE = 9.7803253359;
    constexpr double k = 0.00193185265241;
    constexpr double m = 0.00344978650684;

    double gamma0 = gammaE * (1.0 + k * sin2Phi) / std::sqrt(1.0 - WGS84_E2 * sin2Phi);
    if (std::abs(altM) < 1e-3) return gamma0;

    double termH = (2.0 / WGS84_A) * (1.0 + WGS84_F + m - 2.0 * WGS84_F * sin2Phi) * altM;
    double termH2 = (3.0 / (WGS84_A * WGS84_A)) * (altM * altM);
    return gamma0 * (1.0 - termH + termH2);
}

Eigen::Vector3d apparentAcceleration(const Eigen::Vector3d& vNav, double latDeg, double altM) {
    double phi = deg2rad(latDeg);
    double cosPhi = std::cos(phi);
    double sinPhi = std::sin(phi);
    double tanPhi = std::tan(phi);

    double sinLat = std::sin(phi);
    double denom = 1.0 - WGS84_E2 * sinLat * sinLat;
    double N = WGS84_A / std::sqrt(denom);
    double M = (WGS84_A * (1.0 - WGS84_E2)) / (denom * std::sqrt(denom));

    constexpr double earthRotationRate = 7.292115e-5;

    double wEnEast = -vNav.y() / (M + altM);
    double wEnNorth = vNav.x() / (N + altM);
    double wEnUp = (vNav.x() * tanPhi) / (N + altM);

    double wEast = wEnEast;
    double wNorth = 2.0 * earthRotationRate * cosPhi + wEnNorth;
    double wUp = 2.0 * earthRotationRate * sinPhi + wEnUp;

    return {
        wUp * vNav.y() - wNorth * vNav.z(),
        wEast * vNav.z() - wUp * vNav.x(),
        wNorth * vNav.x() - wEast * vNav.y()
    };
}

} // namespace idr
