#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
  #define IDR_EXPORT __declspec(dllexport)
#else
  #define IDR_EXPORT __attribute__((visibility("default")))
#endif

typedef struct {
    double timestamp;
    double px, py, pz;
    double vx, vy, vz;
    double yawRad;
    double headingDeg;
    double rollRad;
    double pitchRad;
    double positionStd;
    double hdop;
    double trustWeight;
    int isShock;
    int isStandstill;
    int isOutage;
    double idrDrift;
    double classicDrift;

    // Extended diagnostics
    double gyroBiasZ;
    double accelBiasX;
    double forwardSpeed;
    double climbRate;
    double cabinConfidence;
    int isCabinLocked;
    int isPedestrian;
    double rawJerk;
    double jerkVariance;
    double covPxx;
    double covPyy;
    double covPzz;
    double covPyaw;
    double covPvfwd;
    double covPvz;
} IdrNavSolutionC;

IDR_EXPORT void* idr_pipeline_create(void);
IDR_EXPORT void  idr_pipeline_destroy(void* handle);
IDR_EXPORT void  idr_pipeline_reset(void* handle);

IDR_EXPORT void  idr_pipeline_process_imu(void* handle, double timestamp, double ax, double ay, double az, double gx, double gy, double gz);
IDR_EXPORT void  idr_pipeline_process_gnss(void* handle, double timestamp, double lat, double lon, double alt, double hdop, double speed, double course);
IDR_EXPORT void  idr_pipeline_process_baro(void* handle, double timestamp, double pressureHpa);
IDR_EXPORT void  idr_pipeline_process_mag(void* handle, double timestamp, double mx, double my, double mz, double headingDeg);

IDR_EXPORT void  idr_pipeline_update_map_matching(void* handle, double nx, double ny, double crossTrackDist, double sigma, double roadElev);
IDR_EXPORT void  idr_pipeline_update_map_heading(void* handle, double roadHeadingRad, double confidence);
IDR_EXPORT void  idr_pipeline_update_tcn_speed(void* handle, double speedMps, double variance);
IDR_EXPORT void  idr_pipeline_set_pedestrian_mode(void* handle, int isPedestrian);
IDR_EXPORT int   idr_pipeline_is_pedestrian(void* handle);
IDR_EXPORT void  idr_pipeline_set_reference_anchor(void* handle, double lat, double lon, double alt);
IDR_EXPORT void  idr_pipeline_sync_gnss_speed(void* handle, double speedMps, double hdop, int isDenied);

IDR_EXPORT void  idr_pipeline_set_outage(void* handle, int outage);
IDR_EXPORT void  idr_pipeline_toggle_outage(void* handle);
IDR_EXPORT int   idr_pipeline_is_outage(void* handle);

IDR_EXPORT void  idr_pipeline_get_solution(void* handle, IdrNavSolutionC* outSol);

#ifdef __cplusplus
}
#endif
