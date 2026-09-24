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

    currentSolution_ = NavSolution();
}

void IdrPipeline::setTunnelOutage(bool outage) {
    std::lock_guard<std::mutex> lock(mutex_);
    isTunnelOutage_ = outage;
}

void IdrPipeline::toggleTunnelOutage() {
    std::lock_guard<std::mutex> lock(mutex_);
    isTunnelOutage_ = !isTunnelOutage_;
}

void IdrPipeline::processImu(const ImuSample& sample) {
    std::lock_guard<std::mutex> lock(mutex_);

    double dt = (lastImuTimestamp_ > 0.0) ? (sample.timestamp - lastImuTimestamp_) : 0.02;
    if (dt <= 0.0 || dt > 0.5) dt = 0.02;
    lastImuTimestamp_ = sample.timestamp;

    // 1. Cabin Alignment
    cabinAligner_.addSample(sample.accel);
    Vec3 aAligned = cabinAligner_.alignAccel(sample.accel);
    Vec3 wAligned = cabinAligner_.alignGyro(sample.gyro);

    // 2. Vibration & Jerk Gate
    bool isStationary = tcnEngine_.isStandstill();
    vibrationGate_.update(aAligned, dt, isStationary);
    double trust = vibrationGate_.trustWeight();

    // 3. TCN Speed Engine & ZUPT
    tcnEngine_.update(aAligned, wAligned, dt);
    double vFwd = tcnEngine_.isStandstill() ? 0.0 : tcnEngine_.speedMps();

    if (tcnEngine_.isStandstill()) {
        ekf_.applyStandstill(sample.gyro.z, aAligned.x);
    }

    // 4. EKF-3D Kinematic Prediction (freeze position integration at standstill)
    if (!tcnEngine_.isStandstill()) {
        ekf_.predict(dt, vFwd, wAligned.z, cabinAligner_.mountPitch(), trust);
    }
    if (!tcnEngine_.isPedestrian()) {
        ekf_.applyNhc();
    }

    // 5. Classic Dead Reckoning
    if (isTunnelOutage_ || !hasGnssRef_ || currentHdop_ > 3.0) {
        if (tcnEngine_.isStandstill()) {
            baselineDr_.syncWithGnss(baselineDr_.position(), {0, 0, 0}, baselineDr_.yaw());
        } else {
            // GNSS lost or Outage active: Open-loop double integration drifts
            baselineDr_.step(dt, sample.accel, sample.gyro);
        }
    } else {
        // Nominal GNSS: Synchronize Baseline DR to current solution (drift = 0.0 m)
        baselineDr_.syncWithGnss(ekf_.position(), ekf_.velocity(), ekf_.yaw());
    }

    updateSolution();
}

void IdrPipeline::processGnss(const GnssSample& sample) {
    std::lock_guard<std::mutex> lock(mutex_);

    if (!hasGnssRef_) {
        refLat_ = sample.lat;
        refLon_ = sample.lon;
        refAlt_ = sample.alt;
        hasGnssRef_ = true;
        ekf_.reset({0, 0, 0}, compassToEnuRad(sample.course));
        baselineDr_.reset({0, 0, 0}, compassToEnuRad(sample.course));
    }

    Eigen::Vector3d enu = geodeticToEnu(sample.lat, sample.lon, sample.alt, refLat_, refLon_, refAlt_);
    latestGnssEnu_ = Vec3::fromEigen(enu);
    currentHdop_ = sample.hdop;

    tcnEngine_.synchronizeGnssSpeed(sample.speed, sample.hdop, isTunnelOutage_);

    if (!isTunnelOutage_ && sample.hdop <= 4.0) {
        ekf_.updateGnss(latestGnssEnu_, sample.hdop);
        if (sample.speed >= 0.6) {
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
    double enuYaw = compassToEnuRad(sample.headingDeg);
    bool isStationary = tcnEngine_.isStandstill();
    ekf_.updateCompass(enuYaw, 0.05, isStationary);
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
    // Synthetic simulation tick for headless benchmarks
    ImuSample imu;
    imu.timestamp = lastImuTimestamp_ + dt;
    imu.accel = {0.0, 0.0, GRAVITY_STANDARD};
    imu.gyro = {0.0, 0.0, 0.0};
    processImu(imu);
}

void IdrPipeline::updateSolution() {
    currentSolution_.timestamp = lastImuTimestamp_;
    currentSolution_.positionEnu = ekf_.position();
    currentSolution_.velocity = ekf_.velocity();
    currentSolution_.yawRad = ekf_.yaw();
    currentSolution_.headingDeg = enuToCompassDeg(ekf_.yaw());
    currentSolution_.rollRad = cabinAligner_.mountRoll();
    currentSolution_.pitchRad = cabinAligner_.mountPitch();

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
    if (hasGnssRef_ && (isTunnelOutage_ || currentHdop_ > 5.0)) {
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
