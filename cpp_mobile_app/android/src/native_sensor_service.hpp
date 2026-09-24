#pragma once

#include <android/sensor.h>
#include <android/looper.h>
#include <memory>
#include "idr/pipeline.hpp"

namespace idr {

class NativeSensorService {
public:
    static constexpr int SENSOR_LOOPER_ID = 3; // Corresponds to LOOPER_ID_USER in native_app_glue

    NativeSensorService(IdrPipeline& pipeline);
    ~NativeSensorService();

    bool init(ALooper* looper);
    void pollEvents();
    void stop();

private:
    IdrPipeline& pipeline_;
    ASensorManager* sensorManager_ = nullptr;
    ASensorEventQueue* eventQueue_ = nullptr;

    const ASensor* accelSensor_ = nullptr;
    const ASensor* gyroSensor_  = nullptr;
    const ASensor* magSensor_   = nullptr;
    const ASensor* baroSensor_  = nullptr;

    Vec3 lastAccel_{0, 0, 9.81};
    Vec3 lastGyro_{0, 0, 0};
    double lastImuTime_ = 0.0;
};

} // namespace idr
