# Cabin Aligner + Pipeline Review

## Prioritized findings

| # | Sev | Location | Bug |
|---|-----|----------|-----|
| 1 | 🔴 Critical | `processImu` → `ekf_.predict(..., mountPitch, mountRoll)` | **Frame error.** Mount pitch/roll is the phone's tilt in the cradle (often 30–70°), not the vehicle's attitude. `aAligned` is already leveled, so passing these angles applies the tilt a second time. A 60° mount pitch makes the EKF project about 87% of forward speed into climb rate. `tcnEngine_.update` and `NavSolution::pitchRad/rollRad` have the same problem. |
| 2 | 🔴 Critical | `computePcaHeading` | **Mixed-frame feedback loop.** `horizontalAccels_` stores samples rotated by whatever `yaw_` was current at insertion. PCA over that buffer measures the error against a blend of old yaws. Because it runs on every sample (50 Hz) over a 200-sample window, the same stale data is applied up to about 140 times, causing overshoot and limit-cycling. The yaw is also never wrapped. |
| 3 | 🔴 Critical | `computePcaHeading` | **Axis ambiguities not handled.** PCA gives an axis, not a direction. The result is wrong by π about half the time (forward vs. reverse). There is also no anisotropy test, and lateral acceleration in turns contaminates the result because there is no yaw-rate gate. |
| 4 | 🔴 Critical | `processMag` | **Phone heading used as vehicle heading.** The OS azimuth refers to the phone's axis, so the mount yaw offset must be removed. On Android the azimuth refers to the phone's +Y axis, which adds another 90°. Magnetic declination is also missing. |
| 5 | 🟠 High | `computeGravityAlignment` | No stationarity or |g| check. Calibrating while driving or while the phone is being handled locks in a permanently wrong level. The code also never re-levels if the phone shifts in the cradle. |
| 6 | 🟠 High | `processImu` (pre-calibration) | `alignAccel` returns the raw value, with gravity still included, before calibration. The TCN, EKF and baseline DR then integrate about 9.81 m/s² of garbage. The same applies before heading lock: `aAligned.x` is not the vehicle's forward axis, which corrupts `applyStandstill(…, aAligned.x)` bias estimation. |
| 7 | 🟠 High | `processGnss` first fix | The EKF yaw is seeded from `sample.course` even at near-zero speed, where course is invalid (0, -1 or noise). |
| 8 | 🟡 Med | `stepSimulation` | Reads `lastImuTimestamp_` without holding the lock (data race). |
| 9 | 🟡 Med | `cabinAligner()`, `ekf()` and other accessors | They return references to mutex-guarded state with no lock, which is a race if called from the UI thread. |
| 10 | 🟡 Med | HDOP thresholds | Three different thresholds: EKF uses ≤ 4.0, baseline DR uses > 3.0, drift uses > 5.0. Between 3 and 4 the baseline free-runs while the EKF is still GNSS-aided. Between 4 and 5 neither is aided, but drift is reported as 0. |
| 11 | 🟡 Med | `isLocked()` | Returns `calibrated_`, so it reports "locked" before the heading has been estimated. |
| 12 | 🟢 Low | `processImu` | `isStandstill()` is read before `tcnEngine_.update()`, so the vibration gate uses the previous tick's state. |

---

## Fix 1: CabinAligner (rewrite of the core logic)

The design change: store **leveled, yaw-free** horizontal acceleration (`R_level_ * a`). From that buffer, compute the **absolute** mount yaw, then low-pass that absolute value. This removes the feedback loop.

### `cabin_aligner.hpp` (changed and added members)

```cpp
public:
    void addSample(const Vec3& accel, const Vec3& gyro);          // gyro needed for turn rejection
    void resolveForwardSign(double gnssLongAccel, double alignedAx); // π-ambiguity resolution
    bool isLocked() const { return calibrated_ && headingLocked_; }
    double confidence() const;

private:
    static double wrapPi(double a) { return std::remainder(a, 2.0 * M_PI); }

    Eigen::Matrix3d R_level_ = Eigen::Matrix3d::Identity(); // phone -> leveled (yaw = 0)
    bool headingLocked_ = false;
    int  pcaUpdates_ = 0;
    int  decim_ = 0;
    double signCorr_ = 0.0;   // Σ(ax_aligned · a_gnss)
    int    signCount_ = 0;
```

### `cabin_aligner.cpp`

```cpp
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
        if (static_cast<int>(gravitySamples_.size()) >= calibrationWindow_) computeGravityAlignment();
        return;
    }
    // Leveled, yaw-free frame: the buffer stays consistent no matter how yaw_ evolves.
    const Eigen::Vector3d a_lvl = R_level_ * accel.toEigen();
    const double wz_lvl = (R_level_ * gyro.toEigen()).z();

    // Reject turns: centripetal acceleration lies along the lateral axis and corrupts PCA.
    if (std::abs(wz_lvl) > 0.08) return;   // ~4.6 deg/s

    horizontalAccels_.push_back({a_lvl.x(), a_lvl.y()});
    if (horizontalAccels_.size() > 200) horizontalAccels_.pop_front();

    // Decimate: one PCA every 10 samples, not every sample on the same window.
    if (horizontalAccels_.size() >= 60 && (++decim_ % 10) == 0) computePcaHeading();
}

void CabinAligner::computeGravityAlignment() {
    const double n = static_cast<double>(gravitySamples_.size());
    Eigen::Vector3d mean = Eigen::Vector3d::Zero();
    for (const auto& s : gravitySamples_) mean += s.toEigen();
    mean /= n;
    Eigen::Vector3d var = Eigen::Vector3d::Zero();
    for (const auto& s : gravitySamples_) var += (s.toEigen() - mean).cwiseAbs2();
    var /= n;

    // Stationarity + sign/unit sanity check (expects specific force, +g up, m/s^2).
    // On failure, keep the newest half of the buffer and retry.
    if (std::abs(mean.norm() - GRAVITY_STANDARD) > 0.4 || var.maxCoeff() > 0.05) {
        gravitySamples_.erase(gravitySamples_.begin(),
                              gravitySamples_.begin() + gravitySamples_.size() / 2);
        return;
    }

    const double gx = mean.x(), gy = mean.y(), gz = mean.z();
    pitch_ = std::atan2(-gx, std::sqrt(gy * gy + gz * gz));
    roll_  = std::atan2(gy, gz);

    // Explicit ZYX composition: R_level = Ry(pitch) * Rx(roll). Do not depend on rotBodyToWorld's convention.
    R_level_ = (Eigen::AngleAxisd(pitch_, Eigen::Vector3d::UnitY()) *
                Eigen::AngleAxisd(roll_,  Eigen::Vector3d::UnitX())).toRotationMatrix();
    yaw_ = 0.0;
    R_mount_ = R_level_;
    calibrated_ = true;
}

void CabinAligner::computePcaHeading() {
    const double n = static_cast<double>(horizontalAccels_.size());
    Eigen::Vector2d mean = Eigen::Vector2d::Zero();
    for (const auto& v : horizontalAccels_) mean += v;
    mean /= n;

    double cxx = 0, cxy = 0, cyy = 0;
    for (const auto& v : horizontalAccels_) {
        const Eigen::Vector2d d = v - mean;
        cxx += d.x() * d.x(); cxy += d.x() * d.y(); cyy += d.y() * d.y();
    }
    cxx /= n; cxy /= n; cyy /= n;

    // Eigenvalues: require real longitudinal energy AND anisotropy.
    const double tr = cxx + cyy;
    const double disc = std::sqrt((cxx - cyy) * (cxx - cyy) + 4.0 * cxy * cxy);
    const double l1 = 0.5 * (tr + disc), l2 = 0.5 * (tr - disc);
    if (l1 < 0.5 || l1 < 4.0 * std::max(l2, 1e-6)) return;

    // Principal axis angle in the leveled phone frame, in (-π/2, π/2].
    const double theta = 0.5 * std::atan2(2.0 * cxy, cxx - cyy);
    // Rz(yaw) must map [cosθ, sinθ] onto vehicle +X, so yaw = -θ (mod π).
    double err = wrapPi(-theta - yaw_);
    if (err >  M_PI / 2) err -= M_PI;     // axis ambiguity: take the nearest of ±π
    if (err < -M_PI / 2) err += M_PI;

    const double gain = (pcaUpdates_ < 20) ? 0.3 : 0.05;
    yaw_ = wrapPi(yaw_ + gain * err);
    ++pcaUpdates_;

    R_mount_ = Eigen::AngleAxisd(yaw_, Eigen::Vector3d::UnitZ()).toRotationMatrix() * R_level_;
}

// Resolve the forward/backward (π) ambiguity: aligned ax must correlate positively
// with GNSS longitudinal acceleration (dv/dt).
void CabinAligner::resolveForwardSign(double gnssLongAccel, double alignedAx) {
    if (!calibrated_ || pcaUpdates_ < 5 || std::abs(gnssLongAccel) < 0.4) return;
    signCorr_ += alignedAx * gnssLongAccel;
    if (++signCount_ < 15) return;
    if (signCorr_ < 0.0) {
        yaw_ = wrapPi(yaw_ + M_PI);
        R_mount_ = Eigen::AngleAxisd(yaw_, Eigen::Vector3d::UnitZ()).toRotationMatrix() * R_level_;
    }
    headingLocked_ = true;
    signCorr_ = 0.0;
    signCount_ = 0;
}

double CabinAligner::confidence() const {
    if (!calibrated_)
        return calibrationWindow_ > 0 ? 0.4 * gravitySamples_.size() / double(calibrationWindow_) : 0.0;
    if (!headingLocked_) return 0.5 + 0.02 * std::min(pcaUpdates_, 10);
    return 0.95;
}
```

`alignAccel` and `alignGyro` stay as they are. Subtracting gravity on z is correct for a leveled frame with specific force +g up.

---

## Fix 2: Pipeline

### `processImu`

```cpp
void IdrPipeline::processImu(const ImuSample& sample) {
    std::lock_guard<std::mutex> lock(mutex_);
    double dt = (lastImuTimestamp_ > 0.0) ? (sample.timestamp - lastImuTimestamp_) : 0.02;
    if (dt <= 0.0 || dt > 0.5) dt = 0.02;
    lastImuTimestamp_ = sample.timestamp;

    cabinAligner_.addSample(sample.accel, sample.gyro);
    if (!cabinAligner_.isCalibrated()) {           // (#6) never feed gravity-polluted data downstream
        updateSolution();
        return;
    }
    const Vec3 aAligned = cabinAligner_.alignAccel(sample.accel);
    const Vec3 wAligned = cabinAligner_.alignGyro(sample.gyro);
    lastAlignedAx_ = aAligned.x;                   // used for forward-sign resolution

    // (#12) Update TCN first so the gate and ZUPT see the current standstill state.
    // (#1) Vehicle pitch in the leveled frame is about 0, NOT the mount pitch.
    const double vehPitch = 0.0;                   // or an EKF/baro road-grade estimate if available
    tcnEngine_.update(aAligned, wAligned, dt, -1.0, vehPitch);
    const bool standstill = tcnEngine_.isStandstill();

    vibrationGate_.update(aAligned, dt, standstill);
    const double trust = vibrationGate_.trustWeight();

    if (standstill) {
        // Accel-x bias is only meaningful once the mount yaw is locked.
        if (cabinAligner_.isLocked()) ekf_.applyStandstill(wAligned.z, aAligned.x);
    } else {
        ekf_.predict(dt, tcnEngine_.speedMps(), wAligned.z, vehPitch, /*roll*/0.0, trust);
    }
    if (!tcnEngine_.isPedestrian()) ekf_.applyNhc();

    // (#10) Single shared threshold
    const bool gnssUsable = hasGnssRef_ && !isTunnelOutage_ && currentHdop_ <= kMaxUsableHdop;
    if (!gnssUsable) {
        if (standstill) baselineDr_.syncWithGnss(baselineDr_.position(), {0, 0, 0}, baselineDr_.yaw());
        else            baselineDr_.step(dt, aAligned, wAligned);
    } else {
        baselineDr_.syncWithGnss(ekf_.position(), ekf_.velocity(), ekf_.yaw());
    }
    updateSolution();
}
```

Header additions: `static constexpr double kMaxUsableHdop = 4.0;`, `double lastAlignedAx_ = 0.0;`, `double lastGnssSpeed_ = -1.0, lastGnssTime_ = 0.0;`. Also add `double timestamp` to `GnssSample` if it is not already present.

### `processGnss` (first-fix course, forward-sign resolution, thresholds)

```cpp
void IdrPipeline::processGnss(const GnssSample& sample) {
    std::lock_guard<std::mutex> lock(mutex_);
    const bool courseValid = sample.speed >= 2.0 && sample.course >= 0.0;   // (#7)

    if (!hasGnssRef_) {
        refLat_ = sample.lat; refLon_ = sample.lon; refAlt_ = sample.alt;
        hasGnssRef_ = true;
        const double yaw0 = courseValid ? compassToEnuRad(sample.course) : ekf_.yaw();
        ekf_.reset({0, 0, 0}, yaw0);
        baselineDr_.reset({0, 0, 0}, yaw0);
    }

    latestGnssEnu_ = Vec3::fromEigen(
        geodeticToEnu(sample.lat, sample.lon, sample.alt, refLat_, refLon_, refAlt_));
    currentHdop_ = sample.hdop;

    // (#3) GNSS dv/dt resolves the mount-yaw π ambiguity
    if (lastGnssSpeed_ >= 0.0 && sample.timestamp > lastGnssTime_) {
        const double aLong = (sample.speed - lastGnssSpeed_) / (sample.timestamp - lastGnssTime_);
        cabinAligner_.resolveForwardSign(aLong, lastAlignedAx_);  // ideally a low-passed ax
    }
    lastGnssSpeed_ = sample.speed;
    lastGnssTime_ = sample.timestamp;

    tcnEngine_.synchronizeGnssSpeed(sample.speed, sample.hdop, isTunnelOutage_);
    if (!isTunnelOutage_ && sample.hdop <= kMaxUsableHdop) {
        ekf_.updateGnss(latestGnssEnu_, sample.hdop);
        if (sample.speed >= 0.6 && sample.course >= 0.0)
            ekf_.updateCourse(compassToEnuRad(sample.course), sample.speed, sample.hdop);
    }
    updateSolution();
}
```

### `processMag` (#4)

```cpp
void IdrPipeline::processMag(const MagSample& sample) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!cabinAligner_.isLocked()) return;   // phone->vehicle yaw unknown: the heading is meaningless
    // The phone's x-axis sits at mountYaw relative to vehicle +X, so:
    //   psi_vehicle = psi_phone - mountYaw.
    // kAzimuthAxisOffset = +π/2 on Android (azimuth refers to the phone's +Y axis); verify on iOS.
    const double psiPhone = compassToEnuRad(sample.headingDeg + declinationDeg_);
    const double psiVeh = std::remainder(
        psiPhone - kAzimuthAxisOffset - cabinAligner_.mountYaw(), 2.0 * M_PI);
    ekf_.updateCompass(psiVeh, 0.05, tcnEngine_.isStandstill());
    updateSolution();
}
```

The more robust approach is to stop using the OS azimuth, which degenerates when the phone is mounted upright. Instead, feed the raw magnetometer vector through `R_mount_` and compute `atan2` in the vehicle frame.

### `updateSolution`: report vehicle attitude, not mount attitude (#1, #10)

```cpp
currentSolution_.rollRad  = 0.0;                         // vehicle (leveled frame); or EKF estimate
currentSolution_.pitchRad = 0.0;
currentSolution_.mountRollRad  = cabinAligner_.mountRoll();   // new diagnostic fields
currentSolution_.mountPitchRad = cabinAligner_.mountPitch();
currentSolution_.mountYawRad   = cabinAligner_.mountYaw();
...
if (hasGnssRef_ && (isTunnelOutage_ || currentHdop_ > kMaxUsableHdop)) { /* drift */ }
```

### `stepSimulation` race (#8)

```cpp
void IdrPipeline::stepSimulation(double dt) {
    ImuSample imu;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        imu.timestamp = lastImuTimestamp_ + dt;
    }
    imu.accel = {0.0, 0.0, GRAVITY_STANDARD};
    imu.gyro  = {0.0, 0.0, 0.0};
    processImu(imu);
}
```

### Unsynchronized accessors (#9)

Return copies of the sub-modules under the lock. Better still, expose only `NavSolution`, which is already a locked snapshot. If you keep the reference accessors, document that they are not thread-safe and remove them from the UI path.

---

## Verification checklist

1. **Level test.** Hold the phone at 60° pitch in the mount, stationary. Expect `R_level_ * g_mean ≈ [0