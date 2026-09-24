#include <pybind11/pybind11.h>
#include <pybind11/eigen.h>
#include <pybind11/stl.h>

#include "idr/types.hpp"
#include "idr/common.hpp"
#include "idr/cabin_aligner.hpp"
#include "idr/vibration_gate.hpp"
#include "idr/tcn_speed_engine.hpp"
#include "idr/ekf_3d.hpp"
#include "idr/baseline_dr.hpp"
#include "idr/pipeline.hpp"

namespace py = pybind11;
using namespace idr;

PYBIND11_MODULE(idr_cpp, m) {
    m.doc() = "High-Performance C++20 Intelligent Dead Reckoning (IDR) Engine";

    // Common mathematical utilities
    m.def("rot_body_to_world", &rotBodyToWorld, "Roll, pitch, yaw -> R_world_body");
    m.def("rot_world_to_body", &rotWorldToBody, "Roll, pitch, yaw -> R_body_world");
    m.def("forward_unit_vector", &forwardUnitVector, "Pitch, yaw -> forward unit vector");
    m.def("euler_rates", &eulerRates, "Roll, pitch, gyro -> euler rates");
    m.def("euler_rate_jacobian", &eulerRateJacobian, "Roll, pitch -> d(euler_rates)/d(gyro)");
    m.def("body_rates", &bodyRates, "Roll, pitch, euler_dot -> body rates");
    m.def("altitude_from_pressure", &altitudeFromPressure, "Pressure [hPa] -> Altitude [m]");
    m.def("pressure_from_altitude", &pressureFromAltitude, "Altitude [m] -> Pressure [hPa]");
    m.def("sigmoid", &sigmoid, "Safe logistic sigmoid", py::arg("x"), py::arg("gain") = 1.0, py::arg("centre") = 0.0);
    m.def("enu_to_compass_deg", &enuToCompassDeg, "ENU yaw [rad] -> Nav Azimuth [deg]");
    m.def("compass_to_enu_rad", &compassToEnuRad, "Nav Azimuth [deg] -> ENU yaw [rad]");

    // Types
    py::class_<Vec3>(m, "Vec3")
        .def(py::init<double, double, double>(), py::arg("x") = 0.0, py::arg("y") = 0.0, py::arg("z") = 0.0)
        .def_readwrite("x", &Vec3::x)
        .def_readwrite("y", &Vec3::y)
        .def_readwrite("z", &Vec3::z)
        .def("norm", &Vec3::norm);

    py::class_<NavSolution>(m, "NavSolution")
        .def_readonly("timestamp", &NavSolution::timestamp)
        .def_readonly("position_enu", &NavSolution::positionEnu)
        .def_readonly("velocity", &NavSolution::velocity)
        .def_readonly("yaw_rad", &NavSolution::yawRad)
        .def_readonly("heading_deg", &NavSolution::headingDeg)
        .def_readonly("roll_rad", &NavSolution::rollRad)
        .def_readonly("pitch_rad", &NavSolution::pitchRad)
        .def_readonly("position_std", &NavSolution::positionStd)
        .def_readonly("hdop", &NavSolution::hdop)
        .def_readonly("trust_weight", &NavSolution::trustWeight)
        .def_readonly("is_shock", &NavSolution::isShock)
        .def_readonly("is_standstill", &NavSolution::isStandstill)
        .def_readonly("is_outage", &NavSolution::isOutage)
        .def_readonly("idr_drift", &NavSolution::idrDrift)
        .def_readonly("classic_drift", &NavSolution::classicDrift);

    // EKF-3D
    py::class_<Ekf3D>(m, "Ekf3D")
        .def(py::init<double>(), py::arg("init_yaw_rad") = 0.0)
        .def("predict", &Ekf3D::predict, py::arg("dt"), py::arg("v_forward"), py::arg("omega_z"), py::arg("pitch_rad"), py::arg("trust_weight") = 1.0)
        .def("apply_nhc", &Ekf3D::applyNhc, py::arg("sigma_nhc") = 0.22)
        .def("apply_standstill", &Ekf3D::applyStandstill, py::arg("raw_gyro_z"))
        .def("update_gnss", &Ekf3D::updateGnss, py::arg("gnss_enu"), py::arg("hdop"), py::arg("sigma_base") = 2.0)
        .def("update_baro", &Ekf3D::updateBaro, py::arg("altitude_m"), py::arg("sigma_baro") = 1.5)
        .def("update_course", &Ekf3D::updateCourse, py::arg("course_rad"), py::arg("hdop"))
        .def("reset", &Ekf3D::reset, py::arg("init_pos") = Vec3{0, 0, 0}, py::arg("init_yaw") = 0.0)
        .def_property_readonly("position", &Ekf3D::position)
        .def_property_readonly("velocity", &Ekf3D::velocity)
        .def_property_readonly("yaw", &Ekf3D::yaw)
        .def_property_readonly("forward_speed", &Ekf3D::forwardSpeed)
        .def_property_readonly("position_std", &Ekf3D::positionStd)
        .def_property_readonly("gyro_bias_z", &Ekf3D::gyroBiasZ);

    // Vibration Gate
    py::class_<VibrationGate>(m, "VibrationGate")
        .def(py::init<double, double, int>(), py::arg("lambda") = 0.05, py::arg("shock_threshold") = 450.0, py::arg("window_size") = 10)
        .def("update", &VibrationGate::update, py::arg("aligned_accel"), py::arg("dt"), py::arg("is_stationary") = false)
        .def_property_readonly("trust_weight", &VibrationGate::trustWeight)
        .def_property_readonly("shock_detected", &VibrationGate::shockDetected)
        .def_property_readonly("jerk_variance", &VibrationGate::jerkVariance)
        .def("reset", &VibrationGate::reset);

    // Cabin Aligner
    py::class_<CabinAligner>(m, "CabinAligner")
        .def(py::init<int>(), py::arg("calibration_window") = 100)
        .def("add_sample", &CabinAligner::addSample, py::arg("accel"))
        .def_property_readonly("is_calibrated", &CabinAligner::isCalibrated)
        .def_property_readonly("mount_pitch", &CabinAligner::mountPitch)
        .def_property_readonly("mount_roll", &CabinAligner::mountRoll)
        .def_property_readonly("mount_yaw", &CabinAligner::mountYaw)
        .def("align_accel", &CabinAligner::alignAccel, py::arg("raw_accel"))
        .def("align_gyro", &CabinAligner::alignGyro, py::arg("raw_gyro"))
        .def("reset", &CabinAligner::reset);

    // TCN Speed Engine
    py::class_<TcnSpeedEngine>(m, "TcnSpeedEngine")
        .def(py::init<int>(), py::arg("window_size") = 50)
        .def("update", &TcnSpeedEngine::update, py::arg("aligned_accel"), py::arg("aligned_gyro"), py::arg("dt"), py::arg("gnss_speed_mps") = -1.0)
        .def_property_readonly("speed_mps", &TcnSpeedEngine::speedMps)
        .def_property_readonly("speed_kmh", &TcnSpeedEngine::speedKmh)
        .def_property_readonly("is_standstill", &TcnSpeedEngine::isStandstill)
        .def("reset", &TcnSpeedEngine::reset);

    // IdrPipeline
    py::class_<IdrPipeline>(m, "IdrPipeline")
        .def(py::init<>())
        .def("set_tunnel_outage", &IdrPipeline::setTunnelOutage, py::arg("outage"))
        .def("toggle_tunnel_outage", &IdrPipeline::toggleTunnelOutage)
        .def_property_readonly("is_tunnel_outage", &IdrPipeline::isTunnelOutage)
        .def("reset", &IdrPipeline::reset)
        .def("solution", &IdrPipeline::solution);
}
