#include "idr/pipeline.hpp"
#include "idr/common.hpp"
#include <cmath>

namespace idr {

IdrPipeline::IdrPipeline() {
    reset();
}

void IdrPipeline::reset() {
    std::lock_guard<std::mutex> lock(mutex_);
    cabinAligner_.reset();
    vibrationGate_.reset();
    tcnEngine_.reset();
    ekf_.reset();
    baselineDr_.reset();

    isTunnelOutage_ = false;
    lastImuTimestamp_ = 0.0;
    hasGnssRef_ = false;
    currentHdop_ = 1.0;
    latestGnssEnu_ = {0, 0, 0};
    lastAlignedAx_ = 0.0;
    lastGnssSpeed_ = -1.0;
    lastGnssTime_ = 0.0;

    currentSolution_ = NavSolution();
}

void IdrPipeline::setTunnelOutage(bool outage) {
    std::lock_guard<std::mutex> lock(mutex_);
    isTunnelOutage_ = outage;
    tcnEngine_.setOutageMode(outage, ekf_.forwardSpeed());
}

void IdrPipeline::toggleTunnelOutage() {
    std::lock_guard<std::mutex> lock(mutex_);
    isTunnelOutage_ = !isTunnelOutage_;
    tcnEngine_.setOutageMode(isTunnelOutage_, ekf_.forwardSpeed());
}

void IdrPipeline::processImu(const ImuSample& sample) {
    std::lock_guard<std::mutex> lock(mutex_);

    double dt = (lastImuTimestamp_ > 0.0) ? (sample.timestamp - lastImuTimestamp_) : 0.02;
    if (dt <= 0.0 || dt > 0.5) dt = 0.02;
    lastImuTimestamp_ = sample.timestamp;

    // 1. Cabin Alignment (pass gyro for turn rejection)
    cabinAligner_.addSample(sample.accel, sample.gyro);
    if (!cabinAligner_.isCalibrated()) {
        updateSolution();
        return; // Prevent gravity-polluted data entering filters prior to leveling
    }
    Vec3 aAligned = cabinAligner_.alignAccel(sample.accel);
    Vec3 wAligned = cabinAligner_.alignGyro(sample.gyro);
    lastAlignedAx_ = aAligned.x;

    // 2. TCN Speed Engine (use leveled vehicle road pitch ~ 0, NOT cradle mount pitch)
    const double vehPitch = 0.0;
    tcnEngine_.update(aAligned, wAligned, dt, -1.0, vehPitch);
    const bool standstill = tcnEngine_.isStandstill();

    // 3. Vibration & Jerk Gate
    vibrationGate_.update(aAligned, dt, standstill);
    double trust = vibrationGate_.trustWeight();

    // 4. EKF-3D Kinematic Prediction & Standstill Updates
    if (standstill) {
        if (cabinAligner_.isLocked()) {
            ekf_.applyStandstill(wAligned.z, aAligned.x);
        } else {
            ekf_.applyStandstill(wAligned.z, 0.0);
        }
    } else {
        ekf_.predict(dt, tcnEngine_.speedMps(), wAligned.z, vehPitch, /*roll*/ 0.0, trust);
    }
    if (!tcnEngine_.isPedestrian()) {
        ekf_.applyNhc();
    }

    // 5. Classic Dead Reckoning with unified HDOP threshold
    const bool gnssUsable = hasGnssRef_ && !isTunnelOutage_ && currentHdop_ <= kMaxUsableHdop;
    if (!gnssUsable) {
        if (standstill) {
            baselineDr_.syncWithGnss(baselineDr_.position(), {0, 0, 0}, baselineDr_.yaw());
        } else {
            baselineDr_.step(dt, aAligned, wAligned);
        }
    } else {
        baselineDr_.syncWithGnss(ekf_.position(), ekf_.velocity(), ekf_.yaw());
    }

    updateSolution();
}

void IdrPipeline::processGnss(const GnssSample& sample) {
    std::lock_guard<std::mutex> lock(mutex_);
    const bool courseValid = sample.speed >= 2.0 && sample.course >= 0.0;

    if (!hasGnssRef_) {
        refLat_ = sample.lat;
        refLon_ = sample.lon;
        refAlt_ = sample.alt;
        hasGnssRef_ = true;
        const double yaw0 = courseValid ? compassToEnuRad(sample.course) : ekf_.yaw();
        ekf_.reset({0, 0, 0}, yaw0);
        baselineDr_.reset({0, 0, 0}, yaw0);
    }

    Eigen::Vector3d enu = geodeticToEnu(sample.lat, sample.lon, sample.alt, refLat_, refLon_, refAlt_);
    latestGnssEnu_ = Vec3::fromEigen(enu);
    currentHdop_ = sample.hdop;

    // Resolve forward/backward pi ambiguity using GNSS dv/dt
    if (lastGnssSpeed_ >= 0.0 && (sample.timestamp > lastGnssTime_)) {
        double dt_gnss = sample.timestamp - lastGnssTime_;
        if (dt_gnss > 0.05 && dt_gnss < 2.0) {
            double aLong = (sample.speed - lastGnssSpeed_) / dt_gnss;
            cabinAligner_.resolveForwardSign(aLong, lastAlignedAx_);
        }
    }
    lastGnssSpeed_ = sample.speed;
    lastGnssTime_ = sample.timestamp;

    tcnEngine_.synchronizeGnssSpeed(sample.speed, sample.hdop, isTunnelOutage_);

    if (!isTunnelOutage_ && sample.hdop <= kMaxUsableHdop) {
        ekf_.updateGnss(latestGnssEnu_, sample.hdop);
        if (sample.speed >= 0.6 && sample.course >= 0.0) {
            double courseRad = compassToEnuRad(sample.course);
            ekf_.updateCourse(courseRad, sample.speed, sample.hdop);
        }
    }

    updateSolution();
}

void IdrPipeline::processBaro(const BaroSample& sample) {
    std::lock_guard<std::mutex> lock(mutex_);
    double alt = altitudeFromPressure(sample.pressureHpa);
    ekf_.updateBaro(alt);
    updateSolution();
}

void IdrPipeline::processMag(const MagSample& sample) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!cabinAligner_.isLocked()) return;

    // Compensate phone magnetic azimuth for cradle mount yaw and Android +Y axis 90 deg offset
    const double psiPhone = compassToEnuRad(sample.headingDeg + declinationDeg_);
    const double psiVeh = std::remainder(
        psiPhone - kAzimuthAxisOffset - cabinAligner_.mountYaw(),
        2.0 * 3.14159265358979323846);
    bool isStationary = tcnEngine_.isStandstill();
    ekf_.updateCompass(psiVeh, 0.05, isStationary);
    updateSolution();
}

void IdrPipeline::updateMapMatching(const Vec3& normal2D, double crossTrackDistance, double sigma, double roadElevation) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!tcnEngine_.isPedestrian()) {
        ekf_.updateMapMatching(normal2D, crossTrackDistance, sigma, roadElevation);
        updateSolution();
    }
}

void IdrPipeline::updateMapHeading(double roadHeadingRad, double confidence) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!tcnEngine_.isPedestrian() && isTunnelOutage_) {
        ekf_.updateMapHeading(roadHeadingRad, confidence);
        updateSolution();
    }
}

void IdrPipeline::updateTcnSpeed(double speedMps, double variance) {
    std::lock_guard<std::mutex> lock(mutex_);
    tcnEngine_.setExternalSpeed(speedMps, variance);
    ekf_.updateTcnSpeed(speedMps, variance);
    updateSolution();
}

void IdrPipeline::setPedestrianMode(bool isPedestrian) {
    std::lock_guard<std::mutex> lock(mutex_);
    tcnEngine_.setPedestrianMode(isPedestrian);
}

bool IdrPipeline::isPedestrian() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return tcnEngine_.isPedestrian();
}

void IdrPipeline::setReferenceAnchor(double lat, double lon, double alt) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (hasGnssRef_ && (refLat_ != lat || refLon_ != lon)) {
        Eigen::Vector3d deltaEnu = geodeticToEnu(refLat_, refLon_, refAlt_, lat, lon, alt);
        Vec3 delta = Vec3::fromEigen(deltaEnu);
        ekf_.translatePosition(delta);
        baselineDr_.translatePosition(delta);
        latestGnssEnu_ += delta;
    }
    refLat_ = lat;
    refLon_ = lon;
    refAlt_ = alt;
    hasGnssRef_ = true;
}

void IdrPipeline::syncGnssSpeed(double speedMps, double hdop, bool isDenied) {
    std::lock_guard<std::mutex> lock(mutex_);
    tcnEngine_.synchronizeGnssSpeed(speedMps, hdop, isDenied);
}

void IdrPipeline::stepSimulation(double dt) {
    double ts;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        ts = lastImuTimestamp_ + dt;
    }
    ImuSample imu;
    imu.timestamp = ts;
    imu.accel = {0.0, 0.0, GRAVITY_STANDARD};
    imu.gyro  = {0.0, 0.0, 0.0};
    processImu(imu);
}

void IdrPipeline::updateSolution() {
    currentSolution_.timestamp = lastImuTimestamp_;
    currentSolution_.positionEnu = ekf_.position();
    currentSolution_.velocity = ekf_.velocity();
    currentSolution_.yawRad = ekf_.yaw();
    currentSolution_.headingDeg = enuToCompassDeg(ekf_.yaw());
    currentSolution_.rollRad = ekf_.roll();
    currentSolution_.pitchRad = ekf_.pitch();

    currentSolution_.positionStd = ekf_.positionStd();
    currentSolution_.hdop = currentHdop_;
    currentSolution_.trustWeight = vibrationGate_.trustWeight();
    currentSolution_.isShock = vibrationGate_.shockDetected();
    currentSolution_.isStandstill = tcnEngine_.isStandstill();
    currentSolution_.isOutage = isTunnelOutage_;

    // Extended diagnostics
    currentSolution_.gyroBiasZ = ekf_.gyroBiasZ();
    currentSolution_.accelBiasX = ekf_.accelBiasX();
    currentSolution_.forwardSpeed = ekf_.forwardSpeed();
    currentSolution_.climbRate = ekf_.climbRate();
    currentSolution_.cabinConfidence = cabinAligner_.confidence();
    currentSolution_.isCabinLocked = cabinAligner_.isLocked();
    currentSolution_.isPedestrian = tcnEngine_.isPedestrian();
    currentSolution_.rawJerk = vibrationGate_.shockDetected() ? 1.0 : 0.0;
    currentSolution_.jerkVariance = vibrationGate_.jerkVariance();

    const auto& P = ekf_.covariance();
    currentSolution_.covDiagonal[0] = P(0, 0);
    currentSolution_.covDiagonal[1] = P(1, 1);
    currentSolution_.covDiagonal[2] = P(2, 2);
    currentSolution_.covDiagonal[3] = P(3, 3);
    currentSolution_.covDiagonal[4] = P(4, 4);
    currentSolution_.covDiagonal[5] = P(5, 5);

    // Drift calculation relative to latest GNSS fix during outage / dead-reckoning
    if (hasGnssRef_ && (isTunnelOutage_ || currentHdop_ > kMaxUsableHdop)) {
        Vec3 diffIdr = ekf_.position() - latestGnssEnu_;
        currentSolution_.idrDrift = std::sqrt(diffIdr.x * diffIdr.x + diffIdr.y * diffIdr.y);

        Vec3 diffClassic = baselineDr_.position() - latestGnssEnu_;
        currentSolution_.classicDrift = std::sqrt(diffClassic.x * diffClassic.x + diffClassic.y * diffClassic.y);
    } else {
        currentSolution_.idrDrift = 0.0;
        currentSolution_.classicDrift = 0.0;
    }
}

NavSolution IdrPipeline::solution() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return currentSolution_;
}

} // namespace idr
