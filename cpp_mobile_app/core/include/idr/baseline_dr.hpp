#pragma once

#include <Eigen/Dense>
#include "idr/types.hpp"

namespace idr {

class BaselineDeadReckoning {
public:
    BaselineDeadReckoning();

    // Step unassisted open-loop double integration
    void step(double dt, const Vec3& accel, const Vec3& gyro);

    // Synchronize state with nominal GNSS (holds drift at 0.0 m)
    void syncWithGnss(const Vec3& position, const Vec3& velocity, double yaw);

    void reset(const Vec3& initPos = {0, 0, 0}, double initYaw = 0.0);

    Vec3 position() const { return position_; }
    Vec3 velocity() const { return velocity_; }
    double yaw() const { return yaw_; }

private:
    Vec3 position_{0, 0, 0};
    Vec3 velocity_{0, 0, 0};
    double yaw_ = 0.0;
};

} // namespace idr
