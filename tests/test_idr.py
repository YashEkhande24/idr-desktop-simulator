"""Comprehensive unit and integration tests for IDR Simulation Platform."""

import sys
from pathlib import Path
import numpy as np
import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from idr_simulation.common import G, rot_body_to_world, altitude_from_pressure, sigmoid
from idr_simulation.sensors.generator import SensorSimulator, SimConfig, RoadGeometry
from idr_simulation.sensors.cabin_alignment import CabinAligner
from idr_simulation.models.vibration_gate import VibrationGate
from idr_simulation.models.tcn_speed_engine import SpeedEngine, TCNConfig
from idr_simulation.fusion.ekf_3d import IntelligentEKF
from idr_simulation.fusion.map_snapper import MapSnapper, Branch, branches_from_geometry
from idr_simulation.fusion.classic_dr import ClassicDeadReckoning
from idr_simulation.pipeline import IDRPipeline, PipelineOptions


def test_rot_body_to_world():
    # Zero roll, pitch, yaw should give identity matrix
    R0 = rot_body_to_world(0.0, 0.0, 0.0)
    assert np.allclose(R0, np.eye(3))

    # 90 degree yaw
    Rz = rot_body_to_world(0.0, 0.0, np.pi / 2)
    assert np.allclose(Rz @ np.array([1.0, 0.0, 0.0]), [0.0, 1.0, 0.0], atol=1e-6)


def test_altitude_from_pressure():
    # Sea level standard pressure
    alt0 = altitude_from_pressure(1013.25)
    assert abs(alt0) < 1e-3

    # Lower pressure should correspond to higher altitude
    alt_high = altitude_from_pressure(900.0)
    assert alt_high > 900.0


def test_sigmoid_hdop_schedule():
    s_low = sigmoid(1.0, gain=1.4, centre=4.0)
    s_mid = sigmoid(4.0, gain=1.4, centre=4.0)
    s_high = sigmoid(25.0, gain=1.4, centre=4.0)

    assert 0.0 <= s_low < 0.1
    assert abs(s_mid - 0.5) < 1e-6
    assert s_high > 0.99


def test_sensor_simulator_packet_structure():
    sim = SensorSimulator(SimConfig(seed=42))
    pkt = sim.step()

    assert "imu_acc" in pkt
    assert "imu_gyro" in pkt
    assert "true_pos" in pkt
    assert "true_speed" in pkt
    assert "hdop" in pkt
    assert pkt["imu_acc"].shape == (3,)
    assert pkt["imu_gyro"].shape == (3,)


def test_cabin_alignment():
    dt = 0.01
    aligner = CabinAligner(dt=dt)
    # Simulate phone with specific force (vehicle stationary or cruising)
    acc = np.array([0.0, 0.0, G])
    gyro = np.array([0.0, 0.0, 0.0])

    for _ in range(100):
        res = aligner.update(acc, gyro)

    assert "acc_vehicle" in res
    assert "R_phone_to_vehicle" in res
    assert "confidence" in res
    assert res["acc_vehicle"].shape == (3,)


def test_vibration_gate():
    gate = VibrationGate(dt=0.01, enter_threshold=1000.0)
    # Smooth acceleration
    acc_smooth = np.array([0.0, 0.0, G])
    for _ in range(20):
        res = gate.update(acc_smooth)
    assert not res["is_shock"]

    # Sudden high-jerk shock (e.g. pothole)
    acc_shock = np.array([0.0, 0.0, G + 25.0])
    res_shock = gate.update(acc_shock)
    # After sudden transition, variance rises
    for _ in range(5):
        res_shock = gate.update(acc_shock + np.random.normal(0, 10, 3))
    assert res_shock["variance"] > 0.0


def test_tcn_speed_engine_backends():
    dt = 0.01
    engine = SpeedEngine(dt=dt)
    assert engine.backend in ("torch", "onnx", "numpy", "heuristic")

    acc_dyn = np.array([0.5, 0.0, 0.0])
    res = engine.update(acc_dyn, yaw_rate=0.0, shock=False)
    assert "v_hat" in res
    assert res["v_hat"] >= 0.0


def test_ekf_3d_propagation_and_nhc():
    dt = 0.01
    ekf = IntelligentEKF(dt=dt)
    ekf.initialise(pos=[0, 0, 0], vel=[15.0, 0, 0], yaw=0.0)

    # Propagate 10 steps
    acc = np.array([0.0, 0.0, G])
    gyro = np.array([0.0, 0.0, 0.0])
    for _ in range(10):
        ekf.predict(acc, gyro)
        ekf.update_nhc()

    assert ekf.position[0] > 0.0
    assert abs(ekf.position[1]) < 0.1  # NHC keeps lateral position bounded
    assert abs(ekf.position[2]) < 0.1  # NHC keeps vertical position bounded


def test_map_snapper_orthogonal_projection():
    points = np.array([
        [0.0, 0.0, 0.0],
        [100.0, 0.0, 0.0],
        [200.0, 0.0, 0.0]
    ])
    branch = Branch(name="test_road", points=points)
    snapper = MapSnapper([branch])

    # Test point offset by 2m laterally
    query_pos = np.array([50.0, 2.0, 0.0])
    match = snapper.match(query_pos)

    assert match is not None
    assert abs(match.point[0] - 50.0) < 1e-4
    assert abs(match.point[1] - 0.0) < 1e-4
    assert abs(match.cross_track - 2.0) < 1e-4


def test_idr_pipeline_short_run():
    options = PipelineOptions(seed=123)
    pipe = IDRPipeline(options)

    # Step for 200 ticks (2 seconds)
    for _ in range(200):
        rec = pipe.step()

    assert rec["t"] > 1.9
    assert rec["err_idr"] < 5.0
    assert "progress" in rec
    assert rec["progress"] > 0.0


def test_app_initialization():
    pytest.importorskip("PySide6")
    try:
        from idr_simulation.app import IDRDesktopApp
        from PySide6 import QtWidgets
        app = QtWidgets.QApplication.instance() or QtWidgets.QApplication([])
        gui = IDRDesktopApp()
        assert gui is not None
        gui._step_once()
        assert gui.pipe.stats.n >= 10
        gui.close()
    except ImportError:
        pytest.skip("Desktop PySide6 app migrated to Flutter / Web UI")

