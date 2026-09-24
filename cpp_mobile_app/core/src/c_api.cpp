#include "idr/c_api.h"
#include "idr/pipeline.hpp"
#include <cstring>

using namespace idr;

extern "C" {

void* idr_pipeline_create(void) {
    return new IdrPipeline();
}

void idr_pipeline_destroy(void* handle) {
    if (handle) {
        delete static_cast<IdrPipeline*>(handle);
    }
}

void idr_pipeline_reset(void* handle) {
    if (handle) {
        static_cast<IdrPipeline*>(handle)->reset();
    }
}

void idr_pipeline_process_imu(void* handle, double timestamp, double ax, double ay, double az, double gx, double gy, double gz) {
    if (!handle) return;
    ImuSample sample;
    sample.timestamp = timestamp;
    sample.accel = {ax, ay, az};
    sample.gyro = {gx, gy, gz};
    static_cast<IdrPipeline*>(handle)->processImu(sample);
}

void idr_pipeline_process_gnss(void* handle, double timestamp, double lat, double lon, double alt, double hdop, double speed, double course) {
    if (!handle) return;
    GnssSample sample;
    sample.timestamp = timestamp;
    sample.lat = lat;
    sample.lon = lon;
    sample.alt = alt;
    sample.hdop = hdop;
    sample.speed = speed;
    sample.course = course;
    static_cast<IdrPipeline*>(handle)->processGnss(sample);
}

void idr_pipeline_process_baro(void* handle, double timestamp, double pressureHpa) {
    if (!handle) return;
    BaroSample sample;
    sample.timestamp = timestamp;
    sample.pressureHpa = pressureHpa;
    static_cast<IdrPipeline*>(handle)->processBaro(sample);
}

void idr_pipeline_process_mag(void* handle, double timestamp, double mx, double my, double mz, double headingDeg) {
    if (!handle) return;
    MagSample sample;
    sample.timestamp = timestamp;
    sample.magField = {mx, my, mz};
    sample.headingDeg = headingDeg;
    static_cast<IdrPipeline*>(handle)->processMag(sample);
}

void idr_pipeline_update_map_matching(void* handle, double nx, double ny, double crossTrackDist, double sigma, double roadElev) {
    if (!handle) return;
    static_cast<IdrPipeline*>(handle)->updateMapMatching({nx, ny, 0.0}, crossTrackDist, sigma, roadElev);
}

void idr_pipeline_update_map_heading(void* handle, double roadHeadingRad, double confidence) {
    if (!handle) return;
    static_cast<IdrPipeline*>(handle)->updateMapHeading(roadHeadingRad, confidence);
}

void idr_pipeline_update_tcn_speed(void* handle, double speedMps, double variance) {
    if (!handle) return;
    static_cast<IdrPipeline*>(handle)->updateTcnSpeed(speedMps, variance);
}

void idr_pipeline_set_pedestrian_mode(void* handle, int isPedestrian) {
    if (!handle) return;
    static_cast<IdrPipeline*>(handle)->setPedestrianMode(isPedestrian != 0);
}

int idr_pipeline_is_pedestrian(void* handle) {
    if (!handle) return 0;
    return static_cast<IdrPipeline*>(handle)->isPedestrian() ? 1 : 0;
}

void idr_pipeline_set_reference_anchor(void* handle, double lat, double lon, double alt) {
    if (!handle) return;
    static_cast<IdrPipeline*>(handle)->setReferenceAnchor(lat, lon, alt);
}

void idr_pipeline_sync_gnss_speed(void* handle, double speedMps, double hdop, int isDenied) {
    if (!handle) return;
    static_cast<IdrPipeline*>(handle)->syncGnssSpeed(speedMps, hdop, isDenied != 0);
}

void idr_pipeline_set_outage(void* handle, int outage) {
    if (handle) {
        static_cast<IdrPipeline*>(handle)->setTunnelOutage(outage != 0);
    }
}

void idr_pipeline_toggle_outage(void* handle) {
    if (handle) {
        static_cast<IdrPipeline*>(handle)->toggleTunnelOutage();
    }
}

int idr_pipeline_is_outage(void* handle) {
    if (!handle) return 0;
    return static_cast<IdrPipeline*>(handle)->isTunnelOutage() ? 1 : 0;
}

void idr_pipeline_get_solution(void* handle, IdrNavSolutionC* outSol) {
    if (!handle || !outSol) return;
    NavSolution s = static_cast<IdrPipeline*>(handle)->solution();

    outSol->timestamp = s.timestamp;
    outSol->px = s.positionEnu.x;
    outSol->py = s.positionEnu.y;
    outSol->pz = s.positionEnu.z;
    outSol->vx = s.velocity.x;
    outSol->vy = s.velocity.y;
    outSol->vz = s.velocity.z;
    outSol->yawRad = s.yawRad;
    outSol->headingDeg = s.headingDeg;
    outSol->rollRad = s.rollRad;
    outSol->pitchRad = s.pitchRad;
    outSol->positionStd = s.positionStd;
    outSol->hdop = s.hdop;
    outSol->trustWeight = s.trustWeight;
    outSol->isShock = s.isShock ? 1 : 0;
    outSol->isStandstill = s.isStandstill ? 1 : 0;
    outSol->isOutage = s.isOutage ? 1 : 0;
    outSol->idrDrift = s.idrDrift;
    outSol->classicDrift = s.classicDrift;

    // Extended diagnostics
    outSol->gyroBiasZ = s.gyroBiasZ;
    outSol->accelBiasX = s.accelBiasX;
    outSol->forwardSpeed = s.forwardSpeed;
    outSol->climbRate = s.climbRate;
    outSol->cabinConfidence = s.cabinConfidence;
    outSol->isCabinLocked = s.isCabinLocked ? 1 : 0;
    outSol->isPedestrian = s.isPedestrian ? 1 : 0;
    outSol->rawJerk = s.rawJerk;
    outSol->jerkVariance = s.jerkVariance;
    outSol->covPxx = s.covDiagonal[0];
    outSol->covPyy = s.covDiagonal[1];
    outSol->covPzz = s.covDiagonal[2];
    outSol->covPyaw = s.covDiagonal[3];
    outSol->covPvfwd = s.covDiagonal[4];
    outSol->covPvz = s.covDiagonal[5];
}

} // extern "C"
