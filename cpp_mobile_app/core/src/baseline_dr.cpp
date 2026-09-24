#include "idr/baseline_dr.hpp"
#include "idr/common.hpp"
#include <cmath>

namespace idr {

BaselineDeadReckoning::BaselineDeadReckoning() {
    reset();
}

void BaselineDeadReckoning::reset(const Vec3& initPos, double initYaw) {
    position_ = initPos;
    velocity_ = {0, 0, 0};
    yaw_ = initYaw;
}

void BaselineDeadReckoning::syncWithGnss(const Vec3& position, const Vec3& velocity, double yaw) {
    position_ = position;
    velocity_ = velocity;
    yaw_ = yaw;
}

void BaselineDeadReckoning::step(double dt, const Vec3& accel, const Vec3& gyro) {
    if (dt <= 1e-4) return;

    // Classic open-loop gyro heading integration (uncompensated for bias)
    yaw_ += gyro.z * dt;

    // Rotate body acceleration to world ENU using raw integrated yaw
    double cy = std::cos(yaw_), sy = std::sin(yaw_);
    double axWorld = cy * accel.x - sy * accel.y;
    double ayWorld = sy * accel.x + cy * accel.y;
    double azWorld = accel.z - GRAVITY_STANDARD; // Gravity subtraction

    // Double integration: p = p + v*dt + 0.5*a*dt^2
    position_.x += velocity_.x * dt + 0.5 * axWorld * dt * dt;
    position_.y += velocity_.y * dt + 0.5 * ayWorld * dt * dt;
    position_.z += velocity_.z * dt + 0.5 * azWorld * dt * dt;

    velocity_.x += axWorld * dt;
    velocity_.y += ayWorld * dt;
    velocity_.z += azWorld * dt;
}

} // namespace idr
