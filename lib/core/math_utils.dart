import 'dart:math' as math;

/// 3-element vector class with vector arithmetic.
class Vec3 {
  final double x;
  final double y;
  final double z;

  const Vec3(this.x, this.y, this.z);

  static const Vec3 zero = Vec3(0.0, 0.0, 0.0);
  static const Vec3 gravity = Vec3(0.0, 0.0, -9.80665);

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator *(double s) => Vec3(x * s, y * s, z * s);
  Vec3 operator /(double s) => Vec3(x / s, y / s, z / s);
  Vec3 operator -() => Vec3(-x, -y, -z);

  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;

  Vec3 cross(Vec3 o) => Vec3(
        y * o.z - z * o.y,
        z * o.x - x * o.z,
        x * o.y - y * o.x,
      );

  double get normSquared => x * x + y * y + z * z;
  double get norm => math.sqrt(normSquared);

  Vec3 get normalized {
    final n = norm;
    if (n < 1e-12) return Vec3.zero;
    return this / n;
  }

  List<double> toList() => [x, y, z];

  @override
  String toString() => 'Vec3(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)}, ${z.toStringAsFixed(3)})';
}

/// 3x3 Matrix for 3D rotations, transformations, and coordinate frame alignment.
class Mat3 {
  // Row-major entries:
  // [m00, m01, m02]
  // [m10, m11, m12]
  // [m20, m21, m22]
  final List<double> e;

  const Mat3(this.e);

  static const Mat3 identity = Mat3([
    1.0, 0.0, 0.0,
    0.0, 1.0, 0.0,
    0.0, 0.0, 1.0,
  ]);

  static const Mat3 zero = Mat3([
    0.0, 0.0, 0.0,
    0.0, 0.0, 0.0,
    0.0, 0.0, 0.0,
  ]);

  double get m00 => e[0];
  double get m01 => e[1];
  double get m02 => e[2];
  double get m10 => e[3];
  double get m11 => e[4];
  double get m12 => e[5];
  double get m20 => e[6];
  double get m21 => e[7];
  double get m22 => e[8];

  /// Construct rotation matrix from Euler angles (roll = phi, pitch = theta, yaw = psi).
  /// Standard aerospace sequence: Z (yaw) -> Y (pitch) -> X (roll).
  factory Mat3.fromEuler(double roll, double pitch, double yaw) {
    final cr = math.cos(roll);
    final sr = math.sin(roll);
    final cp = math.cos(pitch);
    final sp = math.sin(pitch);
    final cy = math.cos(yaw);
    final sy = math.sin(yaw);

    return Mat3([
      cy * cp, cy * sp * sr - sy * cr, cy * sp * cr + sy * sr,
      sy * cp, sy * sp * sr + cy * cr, sy * sp * cr - cy * sr,
      -sp,     cp * sr,                cp * cr,
    ]);
  }

  Mat3 operator *(Mat3 o) {
    return Mat3([
      m00 * o.m00 + m01 * o.m10 + m02 * o.m20,
      m00 * o.m01 + m01 * o.m11 + m02 * o.m21,
      m00 * o.m02 + m01 * o.m12 + m02 * o.m22,

      m10 * o.m00 + m11 * o.m10 + m12 * o.m20,
      m10 * o.m01 + m11 * o.m11 + m12 * o.m21,
      m10 * o.m02 + m11 * o.m12 + m12 * o.m22,

      m20 * o.m00 + m21 * o.m10 + m22 * o.m20,
      m20 * o.m01 + m21 * o.m11 + m22 * o.m21,
      m20 * o.m02 + m21 * o.m12 + m22 * o.m22,
    ]);
  }

  Vec3 transform(Vec3 v) {
    return Vec3(
      m00 * v.x + m01 * v.y + m02 * v.z,
      m10 * v.x + m11 * v.y + m12 * v.z,
      m20 * v.x + m21 * v.y + m22 * v.z,
    );
  }

  Mat3 get transpose {
    return Mat3([
      m00, m10, m20,
      m01, m11, m21,
      m02, m12, m22,
    ]);
  }

  double get determinant {
    return m00 * (m11 * m22 - m12 * m21) -
           m01 * (m10 * m22 - m12 * m20) +
           m02 * (m10 * m21 - m11 * m20);
  }

  Mat3? get inverse {
    final det = determinant;
    if (det.abs() < 1e-12) return null;
    final invDet = 1.0 / det;

    return Mat3([
      (m11 * m22 - m12 * m21) * invDet,
      (m02 * m21 - m01 * m22) * invDet,
      (m01 * m12 - m02 * m11) * invDet,

      (m12 * m20 - m10 * m22) * invDet,
      (m00 * m22 - m02 * m20) * invDet,
      (m02 * m10 - m00 * m12) * invDet,

      (m10 * m21 - m11 * m20) * invDet,
      (m01 * m20 - m00 * m21) * invDet,
      (m00 * m11 - m01 * m10) * invDet,
    ]);
  }

  /// Construct skew-symmetric cross-product matrix [v]x such that [v]x * u = v x u.
  factory Mat3.skewSymmetric(Vec3 v) {
    return Mat3([
      0.0, -v.z,  v.y,
      v.z,  0.0, -v.x,
     -v.y,  v.x,  0.0,
    ]);
  }
}

/// Helper math routines.
class MathUtils {
  static double clamp(double value, double min, double max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  static double normalizeAngle(double angle) {
    while (angle > math.pi) {
      angle -= 2.0 * math.pi;
    }
    while (angle < -math.pi) {
      angle += 2.0 * math.pi;
    }
    return angle;
  }

  static double radToDeg(double radians) => radians * (180.0 / math.pi);
  static double degToRad(double degrees) => degrees * (math.pi / 180.0);

  /// Convert Cartesian ENU angle in radians (0 = East, pi/2 = North, CCW)
  /// to Navigational Compass heading in degrees [0, 360) (0 = North, 90 = East, CW).
  static double enuToCompassDeg(double enuRad) {
    final enuDeg = radToDeg(enuRad);
    final compassDeg = 90.0 - enuDeg;
    return (compassDeg % 360.0 + 360.0) % 360.0;
  }

  /// Convert Navigational Compass heading in degrees (0 = North, 90 = East, CW)
  /// to Cartesian ENU angle in radians (0 = East, pi/2 = North, CCW).
  static double compassToEnuRad(double compassDeg) {
    final enuDeg = 90.0 - compassDeg;
    return normalizeAngle(degToRad(enuDeg));
  }

  /// Compute tilt-compensated electronic compass azimuth (radians, 0 = North, pi/2 = East)
  /// using 3D gravity vector and 3D magnetic field vector in smartphone body frame.
  static double computeTiltCompensatedHeading({
    required Vec3 gravity,
    required Vec3 magneticField,
  }) {
    final g = gravity.normalized;
    final m = magneticField.normalized;
    if (g.norm < 1e-6 || m.norm < 1e-6) return 0.0;

    // East vector H = M x G
    final east = m.cross(g).normalized;
    if (east.norm < 1e-6) return 0.0;

    // North vector N = G x H
    final north = g.cross(east).normalized;

    // Device top (+Y) azimuth:
    // angle from North toward East = atan2(east.y, north.y)
    final heading = math.atan2(east.y, north.y);
    return normalizeAngle(heading);
  }

  /// Barometric pressure to altitude formula from standard atmosphere (ISA):
  /// z = 44330 * (1 - (P / 1013.25)^0.1903)
  static double pressureToAltitude(double pressureHpa) {
    if (pressureHpa <= 0.0) return 0.0;
    return 44330.0 * (1.0 - math.pow(pressureHpa / 1013.25, 0.190284).toDouble());
  }

  /// WGS84 Earth Equatorial Radius in meters (semi-major axis a).
  static const double earthRadiusWgs84 = 6378137.0;
  static const double wgs84A = 6378137.0;
  static const double wgs84F = 1.0 / 298.257223563;
  static const double wgs84E2 = 0.0066943799901413165;
  static const double earthRotationRate = 7.292115e-5; // rad/s

  /// Radius of curvature in the prime vertical (transverse radius):
  /// N(phi) = a / sqrt(1 - e^2 * sin^2(phi))
  static double primeVerticalRadius(double latRad) {
    final sinLat = math.sin(latRad);
    return wgs84A / math.sqrt(1.0 - wgs84E2 * sinLat * sinLat);
  }

  /// Radius of curvature in the meridian:
  /// M(phi) = a * (1 - e^2) / (1 - e^2 * sin^2(phi))^(3/2)
  static double meridianRadius(double latRad) {
    final sinLat = math.sin(latRad);
    final denom = 1.0 - wgs84E2 * sinLat * sinLat;
    return (wgs84A * (1.0 - wgs84E2)) / (denom * math.sqrt(denom));
  }

  /// Convert geodetic WGS84 (Latitude, Longitude, Altitude) to local Cartesian ENU (East-North-Up)
  /// relative to a reference coordinate anchor (refLat, refLon, refAlt) using ellipsoidal geodesy.
  static Vec3 wgs84ToEnu({
    required double lat,
    required double lon,
    double alt = 0.0,
    required double refLat,
    required double refLon,
    double refAlt = 0.0,
  }) {
    final latRad = degToRad(lat);
    final refLatRad = degToRad(refLat);
    final dLatRad = latRad - refLatRad;
    final dLonRad = degToRad(lon - refLon);

    // Mean latitude for ellipsoidal curvature evaluation
    final meanLat = (latRad + refLatRad) / 2.0;
    final M = meridianRadius(meanLat);
    final N = primeVerticalRadius(meanLat);

    // Local tangent plane projection using exact ellipsoidal curvature
    final east = dLonRad * (N + alt) * math.cos(meanLat);
    final north = dLatRad * (M + alt);
    final up = alt - refAlt;

    return Vec3(east, north, up);
  }

  /// Convert local Cartesian ENU (East-North-Up in meters) back to WGS84 (Latitude, Longitude, Altitude)
  /// using ellipsoidal geodesy.
  static ({double latitude, double longitude, double altitude}) enuToWgs84({
    required Vec3 enu,
    required double refLat,
    required double refLon,
    double refAlt = 0.0,
  }) {
    final refLatRad = degToRad(refLat);
    final m0 = meridianRadius(refLatRad);
    final dLatRad = enu.y / (m0 + refAlt);
    final latRad = refLatRad + dLatRad;
    final meanLat = (refLatRad + latRad) / 2.0;

    final N = primeVerticalRadius(meanLat);
    final dLonRad = enu.x / ((N + refAlt) * math.cos(meanLat));
    final lonRad = degToRad(refLon) + dLonRad;

    return (
      latitude: radToDeg(latRad),
      longitude: radToDeg(lonRad),
      altitude: refAlt + enu.z,
    );
  }

  /// Great-circle surface distance between two WGS-84 coordinates (Latitude, Longitude) in meters.
  static double haversineDistanceMeters(double lat1, double lon1, double lat2, double lon2) {
    final dLat = degToRad(lat2 - lat1);
    final dLon = degToRad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(degToRad(lat1)) * math.cos(degToRad(lat2)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusWgs84 * c;
  }

  /// Exact geodesic distance between two geodetic WGS-84 coordinates on the oblate ellipsoid
  /// using Vincenty's inverse formula. Accurate to sub-millimeter precision.
  static double vincentyDistanceMeters(double lat1, double lon1, double lat2, double lon2) {
    if ((lat1 - lat2).abs() < 1e-11 && (lon1 - lon2).abs() < 1e-11) {
      return 0.0;
    }

    const a = wgs84A;
    const f = wgs84F;
    const b = a * (1.0 - f);

    final phi1 = degToRad(lat1);
    final phi2 = degToRad(lat2);
    final u1 = math.atan((1.0 - f) * math.tan(phi1));
    final u2 = math.atan((1.0 - f) * math.tan(phi2));
    final l = degToRad(lon2 - lon1);

    final sinU1 = math.sin(u1), cosU1 = math.cos(u1);
    final sinU2 = math.sin(u2), cosU2 = math.cos(u2);

    double lambda = l;
    double lambdaPrev = l;
    int iterLimit = 100;
    double sinSigma = 0.0, cosSigma = 0.0, sigma = 0.0;
    double sinAlpha = 0.0, cos2Alpha = 0.0, cos2SigmaM = 0.0;

    do {
      final sinLambda = math.sin(lambda);
      final cosLambda = math.cos(lambda);

      final term1 = cosU2 * sinLambda;
      final term2 = cosU1 * sinU2 - sinU1 * cosU2 * cosLambda;
      sinSigma = math.sqrt(term1 * term1 + term2 * term2);

      if (sinSigma.abs() < 1e-12) {
        return 0.0; // Co-incident points
      }

      cosSigma = sinU1 * sinU2 + cosU1 * cosU2 * cosLambda;
      sigma = math.atan2(sinSigma, cosSigma);

      sinAlpha = (cosU1 * cosU2 * sinLambda) / sinSigma;
      cos2Alpha = 1.0 - sinAlpha * sinAlpha;

      cos2SigmaM = cos2Alpha.abs() < 1e-12 ? 0.0 : (cosSigma - 2.0 * sinU1 * sinU2 / cos2Alpha);

      final c = (f / 16.0) * cos2Alpha * (4.0 + f * (4.0 - 3.0 * cos2Alpha));
      lambdaPrev = lambda;
      lambda = l + (1.0 - c) * f * sinAlpha * (sigma + c * sinSigma * (cos2SigmaM + c * cosSigma * (-1.0 + 2.0 * cos2SigmaM * cos2SigmaM)));
    } while ((lambda - lambdaPrev).abs() > 1e-12 && --iterLimit > 0);

    if (iterLimit == 0) {
      // Non-convergent (near antipodal) fallback
      return haversineDistanceMeters(lat1, lon1, lat2, lon2);
    }

    final uSq = cos2Alpha * ((a * a - b * b) / (b * b));
    final bigA = 1.0 + (uSq / 16384.0) * (4096.0 + uSq * (-768.0 + uSq * (320.0 - 175.0 * uSq)));
    final bigB = (uSq / 1024.0) * (256.0 + uSq * (-128.0 + uSq * (74.0 - 47.0 * uSq)));
    final deltaSigma = bigB * sinSigma * (cos2SigmaM + 0.25 * bigB * (cosSigma * (-1.0 + 2.0 * cos2SigmaM * cos2SigmaM) -
        (bigB / 6.0) * cos2SigmaM * (-3.0 + 4.0 * sinSigma * sinSigma) * (-3.0 + 4.0 * cos2SigmaM * cos2SigmaM)));

    return b * bigA * (sigma - deltaSigma);
  }

  /// Robust Huber M-estimator loss weighting:
  /// w(u) = 1.0 for |u| <= k, and k / |u| for |u| > k.
  /// Typically k = 1.345 provides 95% asymptotic efficiency on Gaussian noise.
  static double huberWeight(double normalizedResidual, {double k = 1.345}) {
    final absU = normalizedResidual.abs();
    if (absU <= k) return 1.0;
    return k / absU;
  }

  /// Tukey biweight (bisquare) robust weighting:
  /// w(u) = (1 - (u/c)^2)^2 for |u| <= c, and 0 for |u| > c.
  /// Tuning constant c = 4.685 gives 95% efficiency.
  static double tukeyWeight(double normalizedResidual, {double c = 4.685}) {
    final absU = normalizedResidual.abs();
    if (absU >= c) return 0.0;
    final r = 1.0 - (absU / c) * (absU / c);
    return r * r;
  }

  /// Chi-Square critical value lookup for hypothesis testing and innovation Mahalanobis gating.
  /// [dof]: degrees of freedom (e.g., 1 for altitude/heading, 2 for horizontal position, 3 for 3D position).
  /// [pValue]: significance level (default 0.01 for 99% confidence gate, or 0.0027 for 3-sigma gate).
  static double chiSquareThreshold(int dof, {double pValue = 0.01}) {
    if (pValue <= 0.003) {
      // ~3-sigma gate (99.73% confidence)
      switch (dof) {
        case 1:
          return 9.00;
        case 2:
          return 11.83;
        case 3:
          return 14.16;
        case 6:
          return 20.25;
        default:
          return dof + 3.0 * math.sqrt(2.0 * dof);
      }
    } else if (pValue <= 0.01) {
      // 99% confidence gate
      switch (dof) {
        case 1:
          return 6.635;
        case 2:
          return 9.210;
        case 3:
          return 11.345;
        case 6:
          return 16.812;
        default:
          return dof + 2.33 * math.sqrt(2.0 * dof);
      }
    } else {
      // 95% confidence gate (p=0.05)
      switch (dof) {
        case 1:
          return 3.841;
        case 2:
          return 5.991;
        case 3:
          return 7.815;
        case 6:
          return 12.592;
        default:
          return dof + 1.645 * math.sqrt(2.0 * dof);
      }
    }
  }

  /// Evaluates whether a Mahalanobis distance squared (NIS) passes the Chi-Square gate.
  static bool passChiSquareGate(double mahalanobisDistSq, int dof, {double pValue = 0.01}) {
    return mahalanobisDistSq <= chiSquareThreshold(dof, pValue: pValue);
  }

  /// Savitzky-Golay 5-point causal quadratic derivative filter.
  /// Computes derivative at the most recent sample (endpoint t=0) over 5 consecutive points
  /// [y0, y1, y2, y3, y4] where y4 is current, separated by dt.
  /// Coefficients: (1 / (10 * dt)) * [-2 * y0 - 1 * y1 + 0 * y2 + 1 * y3 + 2 * y4] (central smoothed derivative)
  static Vec3 savitzkyGolayDerivative5(List<Vec3> window, double dt) {
    if (window.length < 5 || dt <= 0.0) {
      if (window.length >= 2 && dt > 0.0) {
        return (window.last - window[window.length - 2]) / dt;
      }
      return Vec3.zero;
    }
    final n = window.length;
    // Use the latest 5 samples: n-5, n-4, n-3, n-2, n-1
    final y0 = window[n - 5];
    final y1 = window[n - 4];
    final y3 = window[n - 2];
    final y4 = window[n - 1];

    // Central quadratic polynomial derivative evaluated at middle with smooth projection:
    // ( -2*y0 - 1*y1 + 1*y3 + 2*y4 ) / (10 * dt)
    final num = (y4 * 2.0) + y3 - y1 - (y0 * 2.0);
    return num / (10.0 * dt);
  }

  /// Second-order discrete 2-sample Bortz coning correction vector:
  /// Delta_beta = (1 / 12) * (prevTheta x currTheta)
  /// Eliminates non-commutative attitude drift under MEMS vibration.
  static Vec3 bortzConingVector(Vec3 prevTheta, Vec3 currTheta) {
    return prevTheta.cross(currTheta) * (1.0 / 12.0);
  }

  /// Second-order discrete sculling velocity correction vector:
  /// Delta_v_scull = 0.5 * (currTheta x currDv) + (1 / 12) * (prevTheta x currDv + prevDv x currTheta)
  static Vec3 scullingCorrection(Vec3 prevTheta, Vec3 currTheta, Vec3 prevDv, Vec3 currDv) {
    final term1 = currTheta.cross(currDv) * 0.5;
    final term2 = (prevTheta.cross(currDv) + prevDv.cross(currTheta)) * (1.0 / 12.0);
    return term1 + term2;
  }

  /// Magnetic inclination (dip angle) in radians between 3D magnetic field vector
  /// and horizontal plane defined by local gravity unit vector.
  /// [gravity]: 3D gravity acceleration vector in the same coordinate frame.
  static double magneticDipAngle(Vec3 magneticField, Vec3 gravity) {
    final mNorm = magneticField.norm;
    final gNorm = gravity.norm;
    if (mNorm < 1e-6 || gNorm < 1e-6) return 0.0;
    // In body frame, rest gravity vector points up towards +g when resting on table
    final gUnit = gravity / gNorm;
    final dot = magneticField.dot(gUnit) / mNorm;
    return math.asin(clamp(dot, -1.0, 1.0));
  }

  /// Closed-form circular arc position displacement on Lie group SE(2) over sample period [dt].
  /// Given forward speed [speed], heading [yaw] (ENU radians), and yaw rate [omegaZ] (rad/s):
  /// Integrates arc length exactly rather than assuming piecewise linear chord.
  static ({double dx, double dy}) arcStepSE2({
    required double speed,
    required double yaw,
    required double omegaZ,
    required double dt,
  }) {
    final absW = omegaZ.abs();
    if (absW > 1e-4) {
      final psiNext = yaw + omegaZ * dt;
      final dx = speed * (math.sin(psiNext) - math.sin(yaw)) / omegaZ;
      final dy = speed * (-math.cos(psiNext) + math.cos(yaw)) / omegaZ;
      return (dx: dx, dy: dy);
    } else {
      // Second-order Taylor series around omegaZ = 0
      final midYaw = yaw + 0.5 * omegaZ * dt;
      final dist = speed * dt * (1.0 - (omegaZ * dt * omegaZ * dt) / 24.0);
      return (dx: dist * math.cos(midYaw), dy: dist * math.sin(midYaw));
    }
  }

  /// Dynamically computes local base sea-level barometric pressure P0 (hPa)
  /// from current atmospheric pressure [pBaro] (hPa) and true GNSS altitude [hGnss] (meters).
  static double calibratedSeaLevelPressure(double pBaro, double hGnss) {
    if (pBaro <= 0.0) return 1013.25;
    final base = 1.0 - (hGnss / 44330.0);
    if (base <= 0.1) return 1013.25;
    return pBaro * math.pow(base, -1.0 / 0.190284).toDouble();
  }

  /// Evaluates altitude (meters) using dynamically calibrated sea-level pressure [p0] (hPa).
  static double altitudeFromCalibratedPressure(double pBaro, double p0) {
    if (pBaro <= 0.0 || p0 <= 0.0) return 0.0;
    return 44330.0 * (1.0 - math.pow(pBaro / p0, 0.190284).toDouble());
  }

  /// Somigliana WGS84 closed-form theoretical normal gravity formula (m/s^2)
  /// with free-air vertical gradient correction for altitude [altM] above ellipsoid:
  /// gamma(phi) = gamma_e * (1 + k * sin^2(phi)) / sqrt(1 - e^2 * sin^2(phi))
  /// g(phi, h) = gamma(phi) * [1 - (2/a)*(1 + f + m - 2*f*sin^2(phi))*h + (3/a^2)*h^2]
  static double wgs84NormalGravity(double latDeg, [double altM = 0.0]) {
    final phi = degToRad(latDeg);
    final sinPhi = math.sin(phi);
    final sin2Phi = sinPhi * sinPhi;
    const gammaE = 9.7803253359; // Equatorial theoretical gravity
    const k = 0.00193185265241;  // Somigliana formula constant
    const m = 0.00344978650684;  // Geodetic constant omega^2 * a^2 * b / GM

    final gamma0 = gammaE * (1.0 + k * sin2Phi) / math.sqrt(1.0 - wgs84E2 * sin2Phi);
    if (altM.abs() < 1e-3) return gamma0;

    final termH = (2.0 / wgs84A) * (1.0 + wgs84F + m - 2.0 * wgs84F * sin2Phi) * altM;
    final termH2 = (3.0 / (wgs84A * wgs84A)) * (altM * altM);
    return gamma0 * (1.0 - termH + termH2);
  }

  /// Coriolis acceleration vector a_coriolis in local ENU frame (m/s^2)
  /// for vehicle velocity [vNav] = [v_East, v_North, v_Up] at geodetic latitude [latDeg].
  /// omega_ie^n = [0, omega_E * cos(phi), omega_E * sin(phi)]^T.
  static Vec3 coriolisAcceleration(Vec3 vNav, double latDeg) {
    final phi = degToRad(latDeg);
    final cosPhi = math.cos(phi);
    final sinPhi = math.sin(phi);
    final wCos = earthRotationRate * cosPhi;
    final wSin = earthRotationRate * sinPhi;

    return Vec3(
      2.0 * (wSin * vNav.y - wCos * vNav.z),
      -2.0 * (wSin * vNav.x),
      2.0 * (wCos * vNav.x),
    );
  }

  /// Transport rate vector omega_en^n in local ENU frame (rad/s)
  /// representing the angular rate of the local navigation frame relative to the Earth
  /// as the vehicle moves over the WGS-84 curved ellipsoid:
  /// omega_en^n = [-v_N / (M + h), v_E / (N + h), (v_E * tan(phi)) / (N + h)]^T.
  static Vec3 transportRate({
    required Vec3 vNav,
    required double latDeg,
    double altM = 0.0,
  }) {
    final phi = degToRad(latDeg);
    final M = meridianRadius(phi);
    final N = primeVerticalRadius(phi);
    final tanPhi = math.tan(phi);

    final wEast = -vNav.y / (M + altM);
    final wNorth = vNav.x / (N + altM);
    final wUp = (vNav.x * tanPhi) / (N + altM);

    return Vec3(wEast, wNorth, wUp);
  }

  /// Total apparent acceleration (Coriolis + Transport Rate / Eötvös effect)
  /// in local ENU frame (m/s^2) to be subtracted from navigation-frame specific force:
  /// a_apparent = (2 * omega_ie^n + omega_en^n) x vNav.
  static Vec3 apparentAcceleration({
    required Vec3 vNav,
    required double latDeg,
    double altM = 0.0,
  }) {
    final phi = degToRad(latDeg);
    final cosPhi = math.cos(phi);
    final sinPhi = math.sin(phi);
    final tanPhi = math.tan(phi);

    final M = meridianRadius(phi);
    final N = primeVerticalRadius(phi);

    // omega_en^n components
    final wEnEast = -vNav.y / (M + altM);
    final wEnNorth = vNav.x / (N + altM);
    final wEnUp = (vNav.x * tanPhi) / (N + altM);

    // Total rotating frame vector W = 2 * omega_ie^n + omega_en^n
    final wEast = wEnEast;
    final wNorth = 2.0 * earthRotationRate * cosPhi + wEnNorth;
    final wUp = 2.0 * earthRotationRate * sinPhi + wEnUp;

    // Subtracted apparent acceleration (matching coriolisAcceleration sign convention)
    return Vec3(
      wUp * vNav.y - wNorth * vNav.z,
      wEast * vNav.z - wUp * vNav.x,
      wNorth * vNav.x - wEast * vNav.y,
    );
  }

  /// Road corridor deadband Huber loss weighting:
  /// Evaluates effective cross-track residual allowing a tolerance deadband [deadbandHalfWidthM]
  /// (e.g. half-lane width 1.75m) where natural lane changes within the carriageway incur 0 penalty.
  /// Beyond the deadband, a smooth Huber M-estimator loss is applied.
  static ({double effectiveResidual, double weight}) deadbandHuberLoss({
    required double rawResidual,
    double deadbandHalfWidthM = 1.75,
    double k = 1.345,
  }) {
    final absR = rawResidual.abs();
    if (absR <= deadbandHalfWidthM) {
      return (effectiveResidual: 0.0, weight: 1.0);
    }
    final excess = absR - deadbandHalfWidthM;
    final signedExcess = rawResidual > 0 ? excess : -excess;
    final w = huberWeight(excess, k: k);
    return (effectiveResidual: signedExcess * w, weight: w);
  }

  /// Dynamic tire sideslip angle relaxation on Non-Holonomic Constraint (NHC) covariance.
  /// Ground vehicle tires develop lateral slip angles alpha ~ (m * v^2) / (C_alpha * R) during turns.
  /// Inflates nominal lateral variance sigma_0^2 as a function of centripetal acceleration [latAccel]
  /// and forward velocity [forwardSpeed] to avoid clipping high-speed expressway curve trajectories.
  static double adaptiveNhcLatVariance(
    double nominalVar,
    double latAccel,
    double forwardSpeed,
  ) {
    final absA = latAccel.abs();
    final v = math.max(0.0, forwardSpeed);
    final aRatio = absA / 9.80665;
    final vRatio = v / 25.0; // 25 m/s ~ 90 km/h reference highway speed
    final inflation = 1.0 + 4.5 * (aRatio * aRatio) + 1.2 * (vRatio * vRatio * aRatio);
    return MathUtils.clamp(nominalVar * inflation, nominalVar, 0.45);
  }

  /// Robust 3D Hard-Iron magnetic field center offset estimator via minimum bounding sphere centroid.
  /// Eliminates permanent magnetic distortion from steel car body or mount.
  static Vec3 hardIronOffsetEstimate(List<Vec3> magWindow) {
    if (magWindow.length < 10) return Vec3.zero;
    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    double minZ = double.infinity, maxZ = -double.infinity;

    for (final m in magWindow) {
      if (m.x < minX) minX = m.x;
      if (m.x > maxX) maxX = m.x;
      if (m.y < minY) minY = m.y;
      if (m.y > maxY) maxY = m.y;
      if (m.z < minZ) minZ = m.z;
      if (m.z > maxZ) maxZ = m.z;
    }

    return Vec3(
      (minX + maxX) * 0.5,
      (minY + maxY) * 0.5,
      (minZ + maxZ) * 0.5,
    );
  }

  /// Exact 3-point Menger curvature kappa (1/m) of the circumscribed circle passing through nodes A, B, C.
  /// kappa = 4 * Area(ABC) / ( ||A - B|| * ||B - C|| * ||C - A|| )
  /// In 2D plane: Area(ABC) = 0.5 * |(Bx - Ax)*(Cy - Ay) - (By - Ay)*(Cx - Ax)|.
  static double mengerCurvature(Vec3 a, Vec3 b, Vec3 c) {
    final dAB = math.sqrt((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y));
    final dBC = math.sqrt((c.x - b.x) * (c.x - b.x) + (c.y - b.y) * (c.y - b.y));
    final dCA = math.sqrt((a.x - c.x) * (a.x - c.x) + (a.y - c.y) * (a.y - c.y));

    if (dAB < 1e-4 || dBC < 1e-4 || dCA < 1e-4) return 0.0;

    final area2D = 0.5 * ((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)).abs();
    final denom = dAB * dBC * dCA;
    if (denom < 1e-9) return 0.0;

    return (4.0 * area2D) / denom;
  }

  /// Analytical 2D Principal Component Analysis (PCA) dominant orientation angle (radians)
  /// given sample covariance terms [covXX], [covXY], [covYY].
  /// Evaluates psi = 0.5 * atan2(2 * covXY, covXX - covYY) without null-vector degeneracies.
  static double pcaOrientationAngle(double covXX, double covXY, double covYY) {
    return 0.5 * math.atan2(2.0 * covXY, covXX - covYY);
  }

  /// Dynamic centripetal turn speed (m/s) from lateral specific force [measuredLatAccel] and yaw rate [yawRate],
  /// rigorously compensating for mount lever-arm angular acceleration [angularAccel] * [mountOffsetForward]
  /// and highway superelevation (road banking angle) [roadBankAngleRad].
  /// v = |a_lat - alpha_z * r_x - g * sin(phi_bank)| / |omega_z|
  static double? centripetalTurnSpeed({
    required double measuredLatAccel,
    required double yawRate,
    double mountOffsetForward = 1.25,
    double angularAccel = 0.0,
    double roadBankAngleRad = 0.0,
    double gravity = 9.80665,
  }) {
    final absW = yawRate.abs();
    if (absW < 0.06) return null;

    final tangentialMountA = angularAccel * mountOffsetForward;
    final bankGravityA = gravity * math.sin(roadBankAngleRad);
    final netAxleCentripetalA = (measuredLatAccel - tangentialMountA - bankGravityA).abs();

    final v = netAxleCentripetalA / absW;
    if (v >= 0.8 && v <= 55.0) {
      return v;
    }
    return null;
  }

  /// Dynamic forward acceleration (m/s^2) on hill slopes, subtracting the gravity projection
  /// along vehicle pitch angle [pitchRad]:
  /// a_fwd_dynamic = a_fwd - g * sin(theta_pitch).
  static double slopeCompensatedForwardAccel({
    required double measuredFwdAccel,
    required double pitchRad,
    double gravity = 9.80665,
  }) {
    return measuredFwdAccel - gravity * math.sin(pitchRad);
  }

  /// Savitzky-Golay 5-point causal quadratic derivative filter for scalar sequences (e.g. barometric altitude).
  /// Computes derivative at the most recent sample over 5 consecutive points [y0, y1, y2, y3, y4] separated by dt.
  /// Formula: (2*y4 + y3 - y1 - 2*y0) / (10 * dt).
  static double savitzkyGolayDerivative5Scalar(List<double> window, double dt) {
    if (window.length < 5 || dt <= 0.0) {
      if (window.length >= 2 && dt > 0.0) {
        return (window.last - window[window.length - 2]) / dt;
      }
      return 0.0;
    }
    final n = window.length;
    final y0 = window[n - 5];
    final y1 = window[n - 4];
    final y3 = window[n - 2];
    final y4 = window[n - 1];
    return (y4 * 2.0 + y3 - y1 - y0 * 2.0) / (10.0 * dt);
  }

  /// Exact continuous-discrete Van Loan double-integration process noise covariance blocks
  /// over sample period [dt] given continuous velocity random walk spectral density [Sa].
  /// Returns exact position variance q_pp, position-velocity cross-covariance q_pv, and velocity variance q_vv.
  static ({double qpp, double qpv, double qvv}) vanLoanProcessNoise({
    required double sa,
    required double dt,
    double scale = 1.0,
  }) {
    final effectiveDt = clamp(dt, 0.001, 0.20);
    final dt2 = effectiveDt * effectiveDt;
    final dt3 = dt2 * effectiveDt;
    final sScaled = sa * scale;

    return (
      qpp: (1.0 / 3.0) * sScaled * dt3,
      qpv: (1.0 / 2.0) * sScaled * dt2,
      qvv: sScaled * effectiveDt,
    );
  }

  /// Algebraic 3D magnetic ellipsoid fitting via least squares.
  /// Given a window of raw 3D magnetometer samples, fits the quadratic form:
  /// (m - b)^T * M^T * M * (m - b) = R^2
  /// Returns the estimated hard-iron center offset vector [center] and soft-iron scaling [scale].
  static ({Vec3 center, Vec3 scaleMatrixDiagonal}) fitMagneticEllipsoid(List<Vec3> points) {
    if (points.length < 15) {
      final bb = hardIronOffsetEstimate(points);
      return (center: bb, scaleMatrixDiagonal: const Vec3(1.0, 1.0, 1.0));
    }

    // Centroid shift for numerical stability
    double cx = 0, cy = 0, cz = 0;
    for (final p in points) {
      cx += p.x;
      cy += p.y;
      cz += p.z;
    }
    cx /= points.length;
    cy /= points.length;
    cz /= points.length;

    // Direct least squares fit for ellipsoid axes centered around centroid
    // v1 * (x - cx)^2 + v2 * (y - cy)^2 + v3 * (z - cz)^2 + 2*v4*(x-cx) + 2*v5*(y-cy) + 2*v6*(z-cz) = 1
    // Formulate 6x6 normal equations: (A^T A) * v = A^T * 1
    final ata = List<double>.filled(36, 0.0);
    final atb = List<double>.filled(6, 0.0);

    for (final p in points) {
      final dx = p.x - cx;
      final dy = p.y - cy;
      final dz = p.z - cz;

      final row = [
        dx * dx,
        dy * dy,
        dz * dz,
        2.0 * dx,
        2.0 * dy,
        2.0 * dz,
      ];

      for (int i = 0; i < 6; i++) {
        atb[i] += row[i];
        final i6 = i * 6;
        for (int j = 0; j < 6; j++) {
          ata[i6 + j] += row[i] * row[j];
        }
      }
    }

    // Solve 6x6 system using Gaussian elimination with partial pivoting
    final v = _solveLinearSystem6(ata, atb);
    if (v == null || v[0] <= 0 || v[1] <= 0 || v[2] <= 0) {
      final fallbackCenter = hardIronOffsetEstimate(points);
      return (center: fallbackCenter, scaleMatrixDiagonal: const Vec3(1.0, 1.0, 1.0));
    }

    // Center offsets
    final ox = -v[3] / v[0];
    final oy = -v[4] / v[1];
    final oz = -v[5] / v[2];

    final finalCenter = Vec3(cx + ox, cy + oy, cz + oz);

    // Semi-axis lengths
    final d0 = 1.0 + (v[3] * v[3]) / v[0] + (v[4] * v[4]) / v[1] + (v[5] * v[5]) / v[2];
    if (d0 <= 0) {
      return (center: finalCenter, scaleMatrixDiagonal: const Vec3(1.0, 1.0, 1.0));
    }

    final a = math.sqrt(d0 / v[0]);
    final b = math.sqrt(d0 / v[1]);
    final c = math.sqrt(d0 / v[2]);
    final avgRadius = (a + b + c) / 3.0;

    final scaleDiag = Vec3(
      clamp(avgRadius / a, 0.5, 2.0),
      clamp(avgRadius / b, 0.5, 2.0),
      clamp(avgRadius / c, 0.5, 2.0),
    );

    return (center: finalCenter, scaleMatrixDiagonal: scaleDiag);
  }

  static List<double>? _solveLinearSystem6(List<double> a, List<double> b) {
    const n = 6;
    final m = List<double>.from(a);
    final x = List<double>.from(b);

    for (int i = 0; i < n; i++) {
      int maxRow = i;
      double maxVal = m[i * n + i].abs();
      for (int k = i + 1; k < n; k++) {
        final val = m[k * n + i].abs();
        if (val > maxVal) {
          maxVal = val;
          maxRow = k;
        }
      }

      if (maxVal < 1e-12) return null; // Singular matrix

      if (maxRow != i) {
        for (int k = i; k < n; k++) {
          final tmp = m[i * n + k];
          m[i * n + k] = m[maxRow * n + k];
          m[maxRow * n + k] = tmp;
        }
        final tmpB = x[i];
        x[i] = x[maxRow];
        x[maxRow] = tmpB;
      }

      final pivot = m[i * n + i];
      for (int k = i + 1; k < n; k++) {
        final factor = m[k * n + i] / pivot;
        for (int j = i; j < n; j++) {
          m[k * n + j] -= factor * m[i * n + j];
        }
        x[k] -= factor * x[i];
      }
    }

    // Back-substitution
    final res = List<double>.filled(n, 0.0);
    for (int i = n - 1; i >= 0; i--) {
      double sum = x[i];
      for (int j = i + 1; j < n; j++) {
        sum -= m[i * n + j] * res[j];
      }
      res[i] = sum / m[i * n + i];
    }
    return res;
  }

  /// C¹ Hermite backward bridge smoother for dead-reckoning trajectory segments.
  /// When GNSS returns after an outage, smoothly distributes terminal position error
  /// backwards across the outage trajectory without creating velocity kinks at entry/exit.
  static List<Vec3> smoothOutageTrajectory({
    required List<Vec3> trajectory,
    required int outageStartIndex,
    required Vec3 terminalCorrection,
  }) {
    if (outageStartIndex < 0 || outageStartIndex >= trajectory.length - 1) {
      return trajectory;
    }
    final int count = trajectory.length - outageStartIndex;
    if (count <= 1) return trajectory;

    // Compute cumulative arc-length distances along the outage segment
    final List<double> arcLengths = List<double>.filled(count, 0.0);
    double totalDistance = 0.0;
    for (int i = 1; i < count; i++) {
      final pPrev = trajectory[outageStartIndex + i - 1];
      final pCurr = trajectory[outageStartIndex + i];
      totalDistance += (pCurr - pPrev).norm;
      arcLengths[i] = totalDistance;
    }

    final List<Vec3> smoothed = List<Vec3>.from(trajectory);
    for (int i = 1; i < count; i++) {
      // Normalized progress tau in [0, 1]
      final double tau = totalDistance > 1e-4 ? (arcLengths[i] / totalDistance) : (i / (count - 1));
      // Hermite smoothstep S-curve: w(tau) = 3*tau^2 - 2*tau^3 (w'(0)=0, w'(1)=0)
      final double weight = (3.0 - 2.0 * tau) * tau * tau;
      smoothed[outageStartIndex + i] = trajectory[outageStartIndex + i] + (terminalCorrection * weight);
    }
    return smoothed;
  }
}

/// 3D C2-Continuous Spline for smooth highway centerline geometry, continuous normal vectors,
/// and exact analytical curvature.
class CubicSpline3D {
  final List<Vec3> points;
  final List<double> _arcLengths;
  final double totalLength;

  CubicSpline3D._(this.points, this._arcLengths, this.totalLength);

  /// Construct a C2-continuous cubic spline passing through polyline nodes.
  factory CubicSpline3D.fromPoints(List<Vec3> pts) {
    if (pts.length < 2) {
      throw ArgumentError('CubicSpline3D requires at least 2 points');
    }

    final arcLengths = <double>[0.0];
    double total = 0.0;
    for (int i = 0; i < pts.length - 1; i++) {
      final d = (pts[i + 1] - pts[i]).norm;
      total += d;
      arcLengths.add(total);
    }

    return CubicSpline3D._(List<Vec3>.unmodifiable(pts), arcLengths, total);
  }

  /// Evaluates 3D position p(s) along spline arc length s in [0, totalLength].
  Vec3 evaluatePosition(double s) {
    final clampedS = MathUtils.clamp(s, 0.0, totalLength);
    final i = _findSegment(clampedS);
    if (i >= points.length - 1) return points.last;

    final s0 = _arcLengths[i];
    final s1 = _arcLengths[i + 1];
    final ds = s1 - s0;
    if (ds < 1e-6) return points[i];

    final u = (clampedS - s0) / ds;

    // Catmull-Rom Hermite interpolation with zero acceleration at boundaries
    final p0 = i > 0 ? points[i - 1] : points[i];
    final p1 = points[i];
    final p2 = points[i + 1];
    final p3 = i < points.length - 2 ? points[i + 2] : points[i + 1];

    final m1 = (p2 - p0) * 0.5;
    final m2 = (p3 - p1) * 0.5;

    final u2 = u * u;
    final u3 = u2 * u;

    final h00 = 2.0 * u3 - 3.0 * u2 + 1.0;
    final h10 = u3 - 2.0 * u2 + u;
    final h01 = -2.0 * u3 + 3.0 * u2;
    final h11 = u3 - u2;

    return p1 * h00 + m1 * h10 + p2 * h01 + m2 * h11;
  }

  /// Evaluates 3D unit tangent t(s) along spline arc length s.
  Vec3 evaluateTangent(double s) {
    final clampedS = MathUtils.clamp(s, 0.0, totalLength);
    const eps = 0.05;
    final sFwd = math.min(totalLength, clampedS + eps);
    final sBwd = math.max(0.0, clampedS - eps);
    final dt = sFwd - sBwd;
    if (dt < 1e-6) return const Vec3(1.0, 0.0, 0.0);

    final pFwd = evaluatePosition(sFwd);
    final pBwd = evaluatePosition(sBwd);
    final deriv = (pFwd - pBwd) / dt;
    return deriv.normalized;
  }

  /// Evaluates 2D horizontal unit normal n(s) pointing to the right of travel direction.
  Vec3 evaluateNormal2D(double s) {
    final t = evaluateTangent(s);
    return Vec3(-t.y, t.x, 0.0);
  }

  /// Evaluates analytical curvature kappa(s) = ||p' x p''|| / ||p'||^3 along spline.
  double evaluateCurvature(double s) {
    const eps = 0.10;
    final sM = MathUtils.clamp(s, eps, totalLength - eps);
    final pPrev = evaluatePosition(sM - eps);
    final pCurr = evaluatePosition(sM);
    final pNext = evaluatePosition(sM + eps);

    final d1 = (pNext - pPrev) / (2.0 * eps);
    final d2 = (pNext - pCurr * 2.0 + pPrev) / (eps * eps);

    final cross = d1.cross(d2);
    final d1Norm = d1.norm;
    if (d1Norm < 1e-4) return 0.0;

    return cross.norm / (d1Norm * d1Norm * d1Norm);
  }

  /// Orthogonal projection of 3D query point [P] onto the spline curve using coarse sampling
  /// followed by Newton-Raphson refinement: (p(s) - P) . p'(s) = 0.
  ({double s, Vec3 point, double distance}) projectPoint(Vec3 p) {
    if (points.length < 2 || totalLength <= 0.0) {
      final pt = points.isNotEmpty ? points.first : Vec3.zero;
      return (s: 0.0, point: pt, distance: (pt - p).norm);
    }

    // 1. Coarse search over segment chord bounds
    double bestS = 0.0;
    double bestDistSq = double.infinity;

    const numSamples = 20;
    final step = totalLength / numSamples;
    for (int k = 0; k <= numSamples; k++) {
      final sK = math.min(totalLength, k * step);
      final ptK = evaluatePosition(sK);
      final distSq = (ptK - p).normSquared;
      if (distSq < bestDistSq) {
        bestDistSq = distSq;
        bestS = sK;
      }
    }

    // 2. Newton-Raphson refinement: f(s) = (p(s) - P) . t(s) = 0
    double sOpt = bestS;
    for (int iter = 0; iter < 4; iter++) {
      final pos = evaluatePosition(sOpt);
      final tang = evaluateTangent(sOpt);
      final diff = pos - p;
      final f = diff.dot(tang);

      // f'(s) ~ ||tang||^2 + diff . curvature ~ 1.0
      final fPrime = tang.normSquared;
      if (fPrime.abs() < 1e-6) break;

      final deltaS = f / fPrime;
      sOpt = MathUtils.clamp(sOpt - deltaS, 0.0, totalLength);
      if (deltaS.abs() < 1e-4) break;
    }

    final finalPos = evaluatePosition(sOpt);
    final finalDist = (finalPos - p).norm;
    return (s: sOpt, point: finalPos, distance: finalDist);
  }

  int _findSegment(double s) {
    for (int i = 0; i < _arcLengths.length - 1; i++) {
      if (s <= _arcLengths[i + 1]) {
        return i;
      }
    }
    return math.max(0, points.length - 2);
  }
}

/// Unit Quaternion on SO(3) for 3D orientation, attitude kinematics, and Mahony filtering.
class Quaternion {
  final double w;
  final double x;
  final double y;
  final double z;

  const Quaternion(this.w, this.x, this.y, this.z);

  static const Quaternion identity = Quaternion(1.0, 0.0, 0.0, 0.0);

  Quaternion operator +(Quaternion o) => Quaternion(w + o.w, x + o.x, y + o.y, z + o.z);
  Quaternion operator -(Quaternion o) => Quaternion(w - o.w, x - o.x, y - o.y, z - o.z);
  Quaternion scale(double s) => Quaternion(w * s, x * s, y * s, z * s);
  Quaternion operator /(double s) => Quaternion(w / s, x / s, y / s, z / s);

  /// Hamilton quaternion multiplication: q * o
  Quaternion multiply(Quaternion o) => Quaternion(
        w * o.w - x * o.x - y * o.y - z * o.z,
        w * o.x + x * o.w + y * o.z - z * o.y,
        w * o.y - x * o.z + y * o.w + z * o.x,
        w * o.z + x * o.y - y * o.x + z * o.w,
      );

  Quaternion operator *(dynamic o) {
    if (o is Quaternion) return multiply(o);
    if (o is num) return scale(o.toDouble());
    throw ArgumentError('Unsupported operand type for Quaternion.*: ${o.runtimeType}');
  }

  Quaternion get conjugate => Quaternion(w, -x, -y, -z);

  double get normSquared => w * w + x * x + y * y + z * z;
  double get norm => math.sqrt(normSquared);

  Quaternion get normalized {
    final n = norm;
    if (n < 1e-12) return Quaternion.identity;
    return this / n;
  }

  /// Rotate a 3D vector v by this unit quaternion: v' = q * [0, v] * q^*
  Vec3 rotate(Vec3 v) {
    // Optimized Rodrigues-like formulation without full triple quaternion multiplication:
    // v' = v + 2 * q_v x (q_v x v + w * v)
    final qv = Vec3(x, y, z);
    final t = qv.cross(v) * 2.0;
    return v + (t * w) + qv.cross(t);
  }

  /// Inverse rotate a 3D vector (rotate by conjugate)
  Vec3 inverseRotate(Vec3 v) => conjugate.rotate(v);

  /// Convert to 3x3 direction cosine rotation matrix.
  Mat3 toRotationMatrix() {
    final xx = x * x;
    final yy = y * y;
    final zz = z * z;
    final xy = x * y;
    final xz = x * z;
    final yz = y * z;
    final wx = w * x;
    final wy = w * y;
    final wz = w * z;

    return Mat3([
      1.0 - 2.0 * (yy + zz), 2.0 * (xy - wz),        2.0 * (xz + wy),
      2.0 * (xy + wz),        1.0 - 2.0 * (xx + zz), 2.0 * (yz - wx),
      2.0 * (xz - wy),        2.0 * (yz + wx),        1.0 - 2.0 * (xx + yy),
    ]);
  }

  /// Construct quaternion from Euler angles (roll = phi, pitch = theta, yaw = psi).
  /// Standard aerospace rotation sequence: Z (yaw) -> Y (pitch) -> X (roll).
  factory Quaternion.fromEuler(double roll, double pitch, double yaw) {
    final cr = math.cos(roll * 0.5);
    final sr = math.sin(roll * 0.5);
    final cp = math.cos(pitch * 0.5);
    final sp = math.sin(pitch * 0.5);
    final cy = math.cos(yaw * 0.5);
    final sy = math.sin(yaw * 0.5);

    return Quaternion(
      cr * cp * cy + sr * sp * sy,
      sr * cp * cy - cr * sp * sy,
      cr * sp * cy + sr * cp * sy,
      cr * cp * sy - sr * sp * cy,
    ).normalized;
  }

  /// Extract Euler angles (roll, pitch, yaw) in radians.
  ({double roll, double pitch, double yaw}) toEuler() {
    // Roll (x-axis rotation)
    final sinrCosp = 2.0 * (w * x + y * z);
    final cosrCosp = 1.0 - 2.0 * (x * x + y * y);
    final roll = math.atan2(sinrCosp, cosrCosp);

    // Pitch (y-axis rotation)
    final sinp = 2.0 * (w * y - z * x);
    double pitch;
    if (sinp.abs() >= 1.0) {
      pitch = (sinp >= 0 ? 1.0 : -1.0) * (math.pi / 2.0); // gimbal lock
    } else {
      pitch = math.asin(sinp);
    }

    // Yaw (z-axis rotation)
    final sinyCosp = 2.0 * (w * z + x * y);
    final cosyCosp = 1.0 - 2.0 * (y * y + z * z);
    final yaw = math.atan2(sinyCosp, cosyCosp);

    return (roll: roll, pitch: pitch, yaw: yaw);
  }

  /// Construct quaternion from rotation vector (angle * axis, where ||axis|| = 1).
  factory Quaternion.fromRotationVector(Vec3 rotVec) {
    final theta = rotVec.norm;
    if (theta < 1e-12) return Quaternion.identity;
    final halfTheta = theta * 0.5;
    final sinHalf = math.sin(halfTheta) / theta;
    return Quaternion(
      math.cos(halfTheta),
      rotVec.x * sinHalf,
      rotVec.y * sinHalf,
      rotVec.z * sinHalf,
    );
  }

  @override
  String toString() =>
      'Quaternion(${w.toStringAsFixed(4)}, ${x.toStringAsFixed(4)}, ${y.toStringAsFixed(4)}, ${z.toStringAsFixed(4)})';
}
