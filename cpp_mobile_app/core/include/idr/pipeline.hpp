#pragma once

#include <memory>
#include <mutex>
#include "idr/types.hpp"
#include "idr/cabin_aligner.hpp"
#include "idr/vibration_gate.hpp"
#include "idr/tcn_speed_engine.hpp"
#include "idr/ekf_3d.hpp"
#include "idr/baseline_dr.hpp"

namespace idr {

class IdrPipeline {
public:
    IdrPipeline();

    // Sensor ingest
    void processImu(const ImuSample& sample);
    void processGnss(const GnssSample& sample);
    void processBaro(const BaroSample& sample);
    void processMag(const MagSample& sample);

    // Map matching and heading aiding
    void updateMapMatching(const Vec3& normal2D, double crossTrackDistance, double sigma, double roadElevation = -9999.0);
    void updateMapHeading(double roadHeadingRad, double confidence);

    // External AI speed injection (from Dart ONNX model)
    void updateTcnSpeed(double speedMps, double variance);

    // Pedestrian mode
    void setPedestrianMode(bool isPedestrian);
    bool isPedestrian() const;

    // Direct reference coordinate setting
    void setReferenceAnchor(double lat, double lon, double alt);
    void syncGnssSpeed(double speedMps, double hdop, bool isDenied = false);

    // Simulation / synthetic benchmark step
    void stepSimulation(double dt);

    // Controls
    void setTunnelOutage(bool outage);
    void toggleTunnelOutage();
    bool isTunnelOutage() const { return isTunnelOutage_; }

    void reset();

    // Current navigation state snapshot
    NavSolution solution() const;

    // Sub-modules access
    const CabinAligner& cabinAligner() const { return cabinAligner_; }
    const VibrationGate& vibrationGate() const { return vibrationGate_; }
    const TcnSpeedEngine& tcnSpeedEngine() const { return tcnEngine_; }
    const Ekf3D& ekf() const { return ekf_; }
    const BaselineDeadReckoning& baselineDr() const { return baselineDr_; }

private:
    void updateSolution();

    mutable std::mutex mutex_;

    CabinAligner cabinAligner_;
    VibrationGate vibrationGate_;
    TcnSpeedEngine tcnEngine_;
    Ekf3D ekf_;
    BaselineDeadReckoning baselineDr_;

    bool isTunnelOutage_ = false;
    double lastImuTimestamp_ = 0.0;
    double refLat_ = 0.0, refLon_ = 0.0, refAlt_ = 0.0;
    bool hasGnssRef_ = false;
    double currentHdop_ = 1.0;
    Vec3 latestGnssEnu_{0, 0, 0};

    NavSolution currentSolution_;
};

} // namespace idr
