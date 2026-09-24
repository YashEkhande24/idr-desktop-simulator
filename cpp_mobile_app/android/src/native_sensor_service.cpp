#include "native_sensor_service.hpp"
#include "idr/common.hpp"
#include <android/log.h>
#include <cmath>

#define LOG_TAG "IDR_NativeSensors"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace idr {

NativeSensorService::NativeSensorService(IdrPipeline& pipeline)
    : pipeline_(pipeline) {}

NativeSensorService::~NativeSensorService() {
    stop();
}

bool NativeSensorService::init(ALooper* looper) {
    sensorManager_ = ASensorManager_getInstance();
    if (!sensorManager_) {
        LOGE("Failed to obtain ASensorManager!");
        return false;
    }

    eventQueue_ = ASensorManager_createEventQueue(sensorManager_, looper, SENSOR_LOOPER_ID, nullptr, nullptr);
    if (!eventQueue_) {
        LOGE("Failed to create ASensorEventQueue!");
        return false;
    }

    // 1. Accelerometer
    accelSensor_ = ASensorManager_getDefaultSensor(sensorManager_, ASENSOR_TYPE_ACCELEROMETER);
    if (accelSensor_) {
        ASensorEventQueue_enableSensor(eventQueue_, accelSensor_);
        ASensorEventQueue_setEventRate(eventQueue_, accelSensor_, 20000); // 50 Hz (20,000 us)
        LOGI("Hardware Accelerometer enabled at 50 Hz");
    }

    // 2. Gyroscope
    gyroSensor_ = ASensorManager_getDefaultSensor(sensorManager_, ASENSOR_TYPE_GYROSCOPE);
    if (gyroSensor_) {
        ASensorEventQueue_enableSensor(eventQueue_, gyroSensor_);
        ASensorEventQueue_setEventRate(eventQueue_, gyroSensor_, 20000); // 50 Hz
        LOGI("Hardware Gyroscope enabled at 50 Hz");
    }

    // 3. Magnetometer
    magSensor_ = ASensorManager_getDefaultSensor(sensorManager_, ASENSOR_TYPE_MAGNETIC_FIELD);
    if (magSensor_) {
        ASensorEventQueue_enableSensor(eventQueue_, magSensor_);
        ASensorEventQueue_setEventRate(eventQueue_, magSensor_, 40000); // 25 Hz
        LOGI("Hardware Magnetometer enabled at 25 Hz");
    }

    // 4. Barometer
    baroSensor_ = ASensorManager_getDefaultSensor(sensorManager_, ASENSOR_TYPE_PRESSURE);
    if (baroSensor_) {
        ASensorEventQueue_enableSensor(eventQueue_, baroSensor_);
        ASensorEventQueue_setEventRate(eventQueue_, baroSensor_, 100000); // 10 Hz
        LOGI("Hardware Barometer enabled at 10 Hz");
    }

    return true;
}

void NativeSensorService::pollEvents() {
    if (!eventQueue_) return;

    ASensorEvent event;
    while (ASensorEventQueue_getEvents(eventQueue_, &event, 1) > 0) {
        double timestamp = static_cast<double>(event.timestamp) * 1e-9; // convert nanoseconds to seconds

        if (event.type == ASENSOR_TYPE_ACCELEROMETER) {
            lastAccel_ = {event.acceleration.x, event.acceleration.y, event.acceleration.z};
            lastImuTime_ = timestamp;

            ImuSample sample;
            sample.timestamp = timestamp;
            sample.accel = lastAccel_;
            sample.gyro = lastGyro_;
            pipeline_.processImu(sample);
        } else if (event.type == ASENSOR_TYPE_GYROSCOPE) {
            lastGyro_ = {event.vector.x, event.vector.y, event.vector.z};
        } else if (event.type == ASENSOR_TYPE_MAGNETIC_FIELD) {
            MagSample sample;
            sample.timestamp = timestamp;
            sample.magField = {event.magnetic.x, event.magnetic.y, event.magnetic.z};
            sample.headingDeg = computeTiltCompensatedHeading(sample.magField, lastAccel_);
            pipeline_.processMag(sample);
        } else if (event.type == ASENSOR_TYPE_PRESSURE) {
            BaroSample sample;
            sample.timestamp = timestamp;
            sample.pressureHpa = event.pressure;
            pipeline_.processBaro(sample);
        }
    }
}

void NativeSensorService::stop() {
    if (eventQueue_ && sensorManager_) {
        if (accelSensor_) ASensorEventQueue_disableSensor(eventQueue_, accelSensor_);
        if (gyroSensor_)  ASensorEventQueue_disableSensor(eventQueue_, gyroSensor_);
        if (magSensor_)   ASensorEventQueue_disableSensor(eventQueue_, magSensor_);
        if (baroSensor_)  ASensorEventQueue_disableSensor(eventQueue_, baroSensor_);
        ASensorManager_destroyEventQueue(sensorManager_, eventQueue_);
        eventQueue_ = nullptr;
    }
}

} // namespace idr
