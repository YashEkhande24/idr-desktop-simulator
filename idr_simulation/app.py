"""AI-ML Intelligent Dead Reckoning (IDR) Desktop Simulator - Smart India Hackathon
High-Performance Interactive Navigation Cockpit using PySide6 & PyQtGraph.

Features:
- Dual 2D Bird's-Eye & 3D OpenGL Viewport (gl.GLViewWidget)
- Multi-channel Telemetry HUD (Speed, HDOP, GNSS Status, Drift Error, Alignment, Gate)
- Triple Synchronized Real-time Oscilloscopes (Jerk Gate, Barometric Elevation, TCN Speed)
- Dynamic Scenario Toggles (Potholes, GNSS Outage, NHC, Map Snapping, Baro, TCN Engine)
- Multi-speed Playback Controls (Play/Pause, Step, Reset, 1x-50x Simulation Multiplier)
"""

from __future__ import annotations

import sys
from pathlib import Path

# Ensure repo root is on sys.path when running app.py directly
REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

import numpy as np
from PySide6 import QtCore, QtGui, QtWidgets
import pyqtgraph as pg
try:
    import pyqtgraph.opengl as gl
    HAS_OPENGL = True
except Exception:
    HAS_OPENGL = False

try:
    from idr_simulation.pipeline import IDRPipeline, PipelineOptions
    from idr_simulation.sensors.generator import (
        TAG_ROUGH,
        TAG_FLYOVER,
        TAG_TUNNEL,
        TAG_CANYON,
        TAG_SPLIT,
    )
except ImportError:
    from pipeline import IDRPipeline, PipelineOptions
    from sensors.generator import (
        TAG_ROUGH,
        TAG_FLYOVER,
        TAG_TUNNEL,
        TAG_CANYON,
        TAG_SPLIT,
    )


# ===================================================================== STYLING
DARK_STYLESHEET = """
QMainWindow {
    background-color: #0b0e14;
    color: #e6edf3;
    font-family: 'Segoe UI', -apple-system, BlinkMacSystemFont, Roboto, sans-serif;
}
QWidget {
    color: #c9d1d9;
    font-size: 12px;
}
QGroupBox {
    background-color: #121824;
    border: 1px solid #1f2a3d;
    border-radius: 8px;
    margin-top: 14px;
    padding: 10px 8px 8px 8px;
    font-weight: 600;
    font-size: 11px;
    letter-spacing: 0.5px;
    text-transform: uppercase;
    color: #58a6ff;
}
QGroupBox::title {
    subcontrol-origin: margin;
    subcontrol-position: top left;
    left: 12px;
    top: 2px;
    padding: 0 4px;
    background-color: #121824;
}
QFrame#MetricCard {
    background-color: #161f30;
    border: 1px solid #23334d;
    border-radius: 6px;
    padding: 6px 8px;
}
QLabel#MetricLabel {
    color: #8b949e;
    font-size: 10px;
    font-weight: 600;
    text-transform: uppercase;
}
QLabel#MetricValue {
    color: #f0f6fc;
    font-size: 15px;
    font-weight: 700;
    font-family: 'Consolas', monospace;
}
QPushButton {
    background-color: #1f2b3e;
    border: 1px solid #304461;
    border-radius: 6px;
    color: #f0f6fc;
    padding: 6px 12px;
    font-weight: 600;
    font-size: 12px;
}
QPushButton:hover {
    background-color: #263852;
    border-color: #3b5377;
}
QPushButton:pressed {
    background-color: #162232;
}
QPushButton#PrimaryBtn {
    background-color: #1f6feb;
    border: 1px solid #388bfd;
    color: #ffffff;
}
QPushButton#PrimaryBtn:hover {
    background-color: #388bfd;
}
QPushButton#DangerBtn {
    background-color: #da3633;
    border: 1px solid #f85149;
    color: #ffffff;
}
QPushButton#DangerBtn:hover {
    background-color: #f85149;
}
QCheckBox {
    spacing: 6px;
    color: #c9d1d9;
    font-size: 11px;
}
QCheckBox::indicator {
    width: 15px;
    height: 15px;
    border-radius: 3px;
    border: 1px solid #304461;
    background-color: #0d131d;
}
QCheckBox::indicator:checked {
    background-color: #238636;
    border-color: #2ea043;
}
QSlider::groove:horizontal {
    border: 1px solid #23334d;
    height: 5px;
    background: #161f30;
    border-radius: 2px;
}
QSlider::sub-page:horizontal {
    background: #1f6feb;
    border-radius: 2px;
}
QSlider::handle:horizontal {
    background: #58a6ff;
    border: 1px solid #79c0ff;
    width: 14px;
    margin-top: -5px;
    margin-bottom: -5px;
    border-radius: 7px;
}
QComboBox {
    background-color: #161f30;
    border: 1px solid #23334d;
    border-radius: 5px;
    padding: 4px 8px;
    color: #f0f6fc;
    font-weight: 500;
}
QComboBox QAbstractItemView {
    background-color: #161f30;
    border: 1px solid #23334d;
    selection-background-color: #1f6feb;
    color: #f0f6fc;
}
QProgressBar {
    border: 1px solid #23334d;
    border-radius: 4px;
    background-color: #121824;
    text-align: center;
    color: #f0f6fc;
    font-weight: 600;
    font-size: 10px;
    height: 14px;
}
QProgressBar::chunk {
    background-color: qlineargradient(x1:0, y1:0, x2:1, y2:0, stop:0 #1f6feb, stop:1 #00e676);
    border-radius: 3px;
}
QTabBar::tab {
    background: #121824;
    border: 1px solid #1f2a3d;
    border-bottom: none;
    color: #8b949e;
    padding: 6px 14px;
    border-top-left-radius: 6px;
    border-top-right-radius: 6px;
    font-weight: 600;
}
QTabBar::tab:selected {
    background: #161f30;
    border-color: #388bfd;
    color: #58a6ff;
}
QScrollArea {
    border: none;
    background: transparent;
}
"""


# =================================================================== 3D WIDGET
class IDR3DWidget(QtWidgets.QWidget):
    """Interactive 3D OpenGL viewport showing flyover climb, tunnel, and trajectories."""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.layout = QtWidgets.QVBoxLayout(self)
        self.layout.setContentsMargins(0, 0, 0, 0)

        if not HAS_OPENGL:
            fallback = QtWidgets.QLabel("PyQtGraph OpenGL (pyqtgraph.opengl) is not available.")
            fallback.setAlignment(QtCore.Qt.AlignCenter)
            self.layout.addWidget(fallback)
            self.view = None
            return

        self.view = gl.GLViewWidget()
        self.view.setBackgroundColor('#090d14')
        self.view.setCameraPosition(distance=450, elevation=35, azimuth=45)
        self.layout.addWidget(self.view)

        # Ground reference grid (at z=0)
        self.grid = gl.GLGridItem()
        self.grid.setSize(x=4500, y=1000, z=0)
        self.grid.setSpacing(x=100, y=100, z=0)
        self.grid.setColor((35, 50, 75, 80))
        self.view.addItem(self.grid)

        # 3D Centerline road representation
        self.road_line = gl.GLLinePlotItem(
            pos=np.zeros((2, 3)),
            color=(0.3, 0.4, 0.5, 0.6),
            width=2.5,
            antialias=True,
            mode='line_strip'
        )
        self.view.addItem(self.road_line)

        # Decoy service road under flyover
        self.decoy_line = gl.GLLinePlotItem(
            pos=np.zeros((2, 3)),
            color=(0.4, 0.4, 0.25, 0.5),
            width=1.5,
            antialias=True,
            mode='line_strip'
        )
        self.view.addItem(self.decoy_line)

        # Ground Truth 3D path (White dotted style / bright white)
        self.gt_line = gl.GLLinePlotItem(
            pos=np.zeros((2, 3)),
            color=(1.0, 1.0, 1.0, 0.9),
            width=2.0,
            antialias=True,
            mode='line_strip'
        )
        self.view.addItem(self.gt_line)

        # Proposed IDR 3D path (Neon Green)
        self.idr_line = gl.GLLinePlotItem(
            pos=np.zeros((2, 3)),
            color=(0.0, 0.95, 0.45, 1.0),
            width=3.5,
            antialias=True,
            mode='line_strip'
        )
        self.view.addItem(self.idr_line)

        # Classic Dead Reckoning 3D path (Bright Red)
        self.classic_line = gl.GLLinePlotItem(
            pos=np.zeros((2, 3)),
            color=(1.0, 0.25, 0.25, 0.85),
            width=2.0,
            antialias=True,
            mode='line_strip'
        )
        self.view.addItem(self.classic_line)

        # Vehicle current 3D position marker
        self.vehicle_marker = gl.GLScatterPlotItem(
            pos=np.zeros((1, 3)),
            color=(0.0, 0.85, 1.0, 1.0),
            size=14,
            pxMode=True
        )
        self.view.addItem(self.vehicle_marker)

        self.follow_vehicle = True

    def set_static_roads(self, centerline: np.ndarray, decoy: np.ndarray):
        if self.view is None:
            return
        if len(centerline) >= 2:
            self.road_line.setData(pos=centerline)
        if len(decoy) >= 2:
            self.decoy_line.setData(pos=decoy)

    def update_paths(self, gt_pts: np.ndarray, idr_pts: np.ndarray,
                     cls_pts: np.ndarray, current_pos: np.ndarray):
        if self.view is None:
            return
        stride = max(1, len(gt_pts) // 1200)

        if len(gt_pts) >= 2:
            self.gt_line.setData(pos=gt_pts[::stride])
        if len(idr_pts) >= 2:
            self.idr_line.setData(pos=idr_pts[::stride])
        if len(cls_pts) >= 2:
            self.classic_line.setData(pos=cls_pts[::stride])

        self.vehicle_marker.setData(pos=current_pos[None, :])

        if self.follow_vehicle and current_pos is not None:
            # Smooth camera tracking towards vehicle
            cx, cy, cz = current_pos
            self.view.opts['center'] = QtGui.QVector3D(cx, cy, cz + 2.0)


# ======================================================= SIMULATION WORKER THREAD
class SimulationWorker(QtCore.QThread):
    """Dedicated background simulation worker thread.

    Executes IDRPipeline.step(), EKF, sensor synthesis, neural TCN inference,
    and road map snapping entirely off the Qt GUI thread. Emits downsampled,
    pre-sliced telemetry snapshots to the GUI thread at ~30 Hz so the GUI thread
    remains 100% responsive and free of computation lag.
    """
    sig_telemetry = QtCore.Signal(dict, dict)
    sig_finished = QtCore.Signal()
    sig_reset_done = QtCore.Signal(dict, dict)

    def __init__(self, options: PipelineOptions, parent=None):
        super().__init__(parent)
        self.options = options
        self.pipe = IDRPipeline(self.options)

        self._mutex = QtCore.QMutex()
        self._is_running = True
        self._speed_multiplier = 1.0
        self._step_once_count = 0
        self._stop_requested = False
        self._reset_requested = False
        self._pending_options: PipelineOptions | None = None

        # Precompute initial step for immediate first paint
        rec0 = self.pipe.step()
        snap0 = self._make_snapshot(rec0)
        self.initial_rec = rec0
        self.initial_snap = snap0

    @property
    def geometry(self):
        return self.pipe.geometry

    @property
    def is_finished(self) -> bool:
        with QtCore.QMutexLocker(self._mutex):
            return self.pipe.finished

    @property
    def is_running(self) -> bool:
        with QtCore.QMutexLocker(self._mutex):
            return self._is_running

    @property
    def speed_multiplier(self) -> float:
        with QtCore.QMutexLocker(self._mutex):
            return self._speed_multiplier

    def toggle_playback(self) -> bool:
        with QtCore.QMutexLocker(self._mutex):
            self._is_running = not self._is_running
            return self._is_running

    def pause(self):
        with QtCore.QMutexLocker(self._mutex):
            self._is_running = False

    def resume(self):
        with QtCore.QMutexLocker(self._mutex):
            self._is_running = True

    def step_n(self, n: int = 10, wait: bool = False):
        target = self.pipe.stats.n + n
        with QtCore.QMutexLocker(self._mutex):
            self._is_running = False
            self._step_once_count += n
        if wait:
            import time
            t0 = time.perf_counter()
            while time.perf_counter() - t0 < 0.5:
                if self.pipe.stats.n >= target or self.pipe.finished:
                    break
                self.msleep(2)

    def request_reset(self, options: PipelineOptions | None = None):
        with QtCore.QMutexLocker(self._mutex):
            self._reset_requested = True
            self._is_running = True
            if options is not None:
                self._pending_options = PipelineOptions(
                    enable_potholes=options.enable_potholes,
                    enable_gnss_outage=options.enable_gnss_outage,
                    enable_nhc=options.enable_nhc,
                    enable_map_snapping=options.enable_map_snapping,
                    enable_vibration_gate=options.enable_vibration_gate,
                    enable_baro=options.enable_baro,
                    enable_tcn=options.enable_tcn,
                )

    def set_speed(self, mult: float):
        with QtCore.QMutexLocker(self._mutex):
            self._speed_multiplier = mult

    def update_options(self, options: PipelineOptions):
        with QtCore.QMutexLocker(self._mutex):
            self._pending_options = PipelineOptions(
                enable_potholes=options.enable_potholes,
                enable_gnss_outage=options.enable_gnss_outage,
                enable_nhc=options.enable_nhc,
                enable_map_snapping=options.enable_map_snapping,
                enable_vibration_gate=options.enable_vibration_gate,
                enable_baro=options.enable_baro,
                enable_tcn=options.enable_tcn,
            )

    def stop(self):
        with QtCore.QMutexLocker(self._mutex):
            self._stop_requested = True

    def __del__(self):
        try:
            self.stop()
            self.wait(500)
        except Exception:
            pass

    def _make_snapshot(self, rec: dict) -> dict:
        h = self.pipe.history
        n_pts = len(h["truth"])
        stride = max(1, n_pts // 1200)

        gt_arr = np.asarray(h["truth"][::stride], dtype=np.float32) if n_pts > 0 else np.empty((0, 3), dtype=np.float32)
        idr_arr = np.asarray(h["idr"][::stride], dtype=np.float32) if n_pts > 0 else np.empty((0, 3), dtype=np.float32)
        cls_arr = np.asarray(h["classic"][::stride], dtype=np.float32) if n_pts > 0 else np.empty((0, 3), dtype=np.float32)

        n_gnss = len(h["gnss"])
        if n_gnss > 0:
            gnss_stride = max(1, n_gnss // 500)
            gnss_arr = np.asarray(h["gnss"][::gnss_stride], dtype=np.float32)
        else:
            gnss_arr = np.empty((0, 3), dtype=np.float32)

        n_t = len(h["t"])
        win = min(n_t, 2500)
        if n_t > 0:
            sub_t = np.asarray(h["t"][-win:], dtype=np.float32)
            j_raw = np.asarray(h["jerk_raw"][-win:], dtype=np.float32)
            j_var = np.asarray(h["jerk_gated"][-win:], dtype=np.float32)
            alt_t = np.asarray(h["alt_true"][-win:], dtype=np.float32)
            alt_i = np.asarray(h["alt_idr"][-win:], dtype=np.float32)
            s_true = np.asarray(h["speed_true"][-win:], dtype=np.float32)
            s_tcn = np.asarray(h["speed_tcn"][-win:], dtype=np.float32)
            s_cls = np.asarray(h["speed_classic"][-win:], dtype=np.float32) if len(h["speed_classic"]) >= win else s_true
        else:
            empty = np.empty(0, dtype=np.float32)
            sub_t = j_raw = j_var = alt_t = alt_i = s_true = s_tcn = s_cls = empty

        n_baro = len(h["alt_baro"])
        if n_baro > 0:
            b_win = min(n_baro, 250)
            b_pts = h["alt_baro"][-b_win:]
            baro_t = np.asarray([pt[0] for pt in b_pts], dtype=np.float32)
            baro_z = np.asarray([pt[1] for pt in b_pts], dtype=np.float32)
        else:
            baro_t = np.empty(0, dtype=np.float32)
            baro_z = np.empty(0, dtype=np.float32)

        return {
            "gt_arr": gt_arr,
            "idr_arr": idr_arr,
            "cls_arr": cls_arr,
            "gnss_arr": gnss_arr,
            "sub_t": sub_t,
            "j_raw": j_raw,
            "j_var": j_var,
            "gate_thresh": float(self.pipe.gate.enter_threshold),
            "alt_t": alt_t,
            "alt_i": alt_i,
            "baro_t": baro_t,
            "baro_z": baro_z,
            "s_true": s_true,
            "s_tcn": s_tcn,
            "s_cls": s_cls,
            "total_len": float(self.pipe.geometry.total_length),
            "n_pts": n_pts,
        }

    def run(self):
        import time
        last_time = time.perf_counter()
        sim_debt = 0.0
        last_emit_time = time.perf_counter()
        EMIT_INTERVAL = 0.033  # ~30 Hz UI refresh

        while True:
            # --- Phase 1: Read control flags under a SHORT lock ---
            with QtCore.QMutexLocker(self._mutex):
                if self._stop_requested:
                    break

                do_reset = self._reset_requested
                if do_reset:
                    self._reset_requested = False
                    reset_opts = self._pending_options or self.pipe.options
                    self._pending_options = None

                do_step_once = self._step_once_count
                if do_step_once > 0:
                    self._step_once_count = 0

                if self._pending_options is not None:
                    self.pipe.options = self._pending_options
                    self._pending_options = None

                is_running = self._is_running
                finished = self.pipe.finished
                speed = self._speed_multiplier

            # --- Phase 2: Execute simulation work WITHOUT holding the lock ---

            # Handle reset
            if do_reset:
                self.pipe.reset(reset_opts)
                sim_debt = 0.0
                last_time = time.perf_counter()
                rec = self.pipe.step()
                snap = self._make_snapshot(rec)
                self.sig_reset_done.emit(rec, snap)
                continue

            # Handle single-step requests
            if do_step_once > 0:
                rec = None
                for _ in range(do_step_once):
                    if not self.pipe.finished:
                        rec = self.pipe.step()
                if rec is not None:
                    snap = self._make_snapshot(rec)
                    self.sig_telemetry.emit(rec, snap)
                if self.pipe.finished:
                    self.sig_finished.emit()
                continue

            # Idle when paused or simulation complete
            if not is_running or finished:
                self.msleep(20)
                last_time = time.perf_counter()
                continue

            now = time.perf_counter()
            dt = now - last_time
            last_time = now
            dt = min(dt, 0.1)

            sim_debt += dt * 100.0 * speed
            steps_to_run = int(sim_debt)

            if steps_to_run <= 0:
                self.msleep(1)
                continue

            batch = min(steps_to_run, 250)
            sim_debt -= batch
            if sim_debt > 300:
                sim_debt = 300.0

            rec = None
            finished_now = False
            for _ in range(batch):
                if self.pipe.finished:
                    finished_now = True
                    break
                rec = self.pipe.step()

            # --- Phase 3: Build snapshot & emit signals WITHOUT holding the lock ---
            now_emit = time.perf_counter()
            if (now_emit - last_emit_time >= EMIT_INTERVAL or finished_now) and rec is not None:
                last_emit_time = now_emit
                snap = self._make_snapshot(rec)
                self.sig_telemetry.emit(rec, snap)

            if finished_now:
                self.sig_finished.emit()
                self.msleep(20)


# =================================================================== MAIN APP
class IDRDesktopApp(QtWidgets.QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("SIH 2026: AI-ML Dead Reckoning Navigation Cockpit")
        self.resize(1560, 960)
        self.setStyleSheet(DARK_STYLESHEET)

        # Simulation pipeline and background worker setup
        self.options = PipelineOptions()
        self.worker = SimulationWorker(self.options, parent=None)
        self.worker.sig_telemetry.connect(self._on_worker_telemetry)
        self.worker.sig_reset_done.connect(self._on_worker_telemetry)
        self.worker.sig_finished.connect(self._on_worker_finished)

        self._last_rec = self.worker.initial_rec
        self._last_snap = self.worker.initial_snap

        # UI components
        self._init_ui()
        self._init_plots()
        self._fit_view_all()

        # Render initial frame
        self._render_ui(self._last_rec, self._last_snap)

        # Start background simulation worker thread
        self.worker.start()

    @property
    def pipe(self) -> IDRPipeline:
        return self.worker.pipe

    @property
    def is_running(self) -> bool:
        return self.worker.is_running

    @is_running.setter
    def is_running(self, val: bool):
        if val:
            self.worker.resume()
        else:
            self.worker.pause()

    @property
    def speed_multiplier(self) -> float:
        return self.worker.speed_multiplier

    @speed_multiplier.setter
    def speed_multiplier(self, val: float):
        self.worker.set_speed(val)

    # ---------------------------------------------------------------- UI INIT
    def _init_ui(self):
        central = QtWidgets.QWidget()
        self.setCentralWidget(central)
        main_layout = QtWidgets.QHBoxLayout(central)
        main_layout.setContentsMargins(10, 10, 10, 10)
        main_layout.setSpacing(10)

        # --------------------- LEFT SIDEBAR (HUD & CONTROLS) ---------------------
        sidebar = QtWidgets.QWidget()
        sidebar.setFixedWidth(360)
        s_layout = QtWidgets.QVBoxLayout(sidebar)
        s_layout.setContentsMargins(0, 0, 0, 0)
        s_layout.setSpacing(8)

        # Header Title Card
        title_card = QtWidgets.QFrame()
        title_card.setObjectName("MetricCard")
        tc_layout = QtWidgets.QVBoxLayout(title_card)
        tc_layout.setContentsMargins(8, 8, 8, 8)
        lbl_brand = QtWidgets.QLabel("SMART INDIA HACKATHON 2026")
        lbl_brand.setStyleSheet("font-size: 10px; font-weight: 800; color: #58a6ff; letter-spacing: 1px;")
        lbl_title = QtWidgets.QLabel("AI-ML Intelligent Dead Reckoning")
        lbl_title.setStyleSheet("font-size: 15px; font-weight: 700; color: #f0f6fc;")
        lbl_sub = QtWidgets.QLabel("GNSS-Denied Subterranean & Multi-Level Fusion")
        lbl_sub.setStyleSheet("font-size: 10px; color: #8b949e;")
        tc_layout.addWidget(lbl_brand)
        tc_layout.addWidget(lbl_title)
        tc_layout.addWidget(lbl_sub)
        s_layout.addWidget(title_card)

        # Master Status Banner
        self.status_card = QtWidgets.QFrame()
        self.status_card.setObjectName("MetricCard")
        sc_layout = QtWidgets.QVBoxLayout(self.status_card)
        sc_layout.setContentsMargins(8, 8, 8, 8)

        self.lbl_master_gnss = QtWidgets.QLabel("GNSS: NOMINAL ACQUISITION")
        self.lbl_master_gnss.setStyleSheet("font-size: 12px; font-weight: 700; color: #00e676;")
        self.lbl_master_gate = QtWidgets.QLabel("VIBRATION GATE: MONITORING")
        self.lbl_master_gate.setStyleSheet("font-size: 11px; font-weight: 600; color: #8b949e;")
        self.lbl_zone_phase = QtWidgets.QLabel("Route Phase: Straight Highway")
        self.lbl_zone_phase.setStyleSheet("font-size: 11px; color: #58a6ff; font-weight: 500;")

        sc_layout.addWidget(self.lbl_master_gnss)
        sc_layout.addWidget(self.lbl_master_gate)
        sc_layout.addWidget(self.lbl_zone_phase)
        s_layout.addWidget(self.status_card)

        # Route Progress Bar
        prog_box = QtWidgets.QGroupBox("Route Arc-Length Progress")
        pb_layout = QtWidgets.QVBoxLayout(prog_box)
        self.prog_bar = QtWidgets.QProgressBar()
        self.prog_bar.setRange(0, 100)
        self.prog_bar.setValue(0)
        self.lbl_prog_text = QtWidgets.QLabel("0 m / 4064 m (0%)")
        self.lbl_prog_text.setStyleSheet("font-size: 10px; color: #8b949e;")
        self.lbl_prog_text.setAlignment(QtCore.Qt.AlignRight)
        pb_layout.addWidget(self.prog_bar)
        pb_layout.addWidget(self.lbl_prog_text)
        s_layout.addWidget(prog_box)

        # Scrollable Metrics Area
        scroll = QtWidgets.QScrollArea()
        scroll.setWidgetResizable(True)
        scroll_content = QtWidgets.QWidget()
        m_layout = QtWidgets.QVBoxLayout(scroll_content)
        m_layout.setContentsMargins(0, 0, 4, 0)
        m_layout.setSpacing(6)

        # Card 1: Real-Time Drift Error Comparison
        c_drift = QtWidgets.QFrame()
        c_drift.setObjectName("MetricCard")
        cd_layout = QtWidgets.QVBoxLayout(c_drift)
        cd_layout.setContentsMargins(8, 6, 8, 6)
        lbl_d_title = QtWidgets.QLabel("HORIZONTAL DRIFT ERROR")
        lbl_d_title.setObjectName("MetricLabel")
        self.lbl_idr_drift = QtWidgets.QLabel("IDR (Proposed): 0.00 m")
        self.lbl_idr_drift.setStyleSheet("font-size: 16px; font-weight: 800; color: #00e676; font-family: Consolas;")
        self.lbl_cls_drift = QtWidgets.QLabel("Classic DR: 0.00 m")
        self.lbl_cls_drift.setStyleSheet("font-size: 13px; font-weight: 700; color: #ff3d71; font-family: Consolas;")
        self.lbl_drift_red = QtWidgets.QLabel("Drift Reduction: 100.0%")
        self.lbl_drift_red.setStyleSheet("font-size: 11px; color: #58a6ff; font-weight: 600;")
        cd_layout.addWidget(lbl_d_title)
        cd_layout.addWidget(self.lbl_idr_drift)
        cd_layout.addWidget(self.lbl_cls_drift)
        cd_layout.addWidget(self.lbl_drift_red)
        m_layout.addWidget(c_drift)

        # Card 2: Speed Estimation & Backend
        c_speed = QtWidgets.QFrame()
        c_speed.setObjectName("MetricCard")
        cs_layout = QtWidgets.QVBoxLayout(c_speed)
        cs_layout.setContentsMargins(8, 6, 8, 6)
        lbl_s_title = QtWidgets.QLabel("FORWARD SPEED ESTIMATOR")
        lbl_s_title.setObjectName("MetricLabel")
        self.lbl_spd_fused = QtWidgets.QLabel("Fused: 0.0 km/h (0.0 m/s)")
        self.lbl_spd_fused.setObjectName("MetricValue")
        self.lbl_spd_truth = QtWidgets.QLabel("Ground Truth: 0.0 km/h")
        self.lbl_spd_truth.setStyleSheet("font-size: 11px; color: #8b949e;")
        self.lbl_spd_backend = QtWidgets.QLabel("Engine: Heuristic (Standstill ZUPT)")
        self.lbl_spd_backend.setStyleSheet("font-size: 10px; color: #e3b341;")
        cs_layout.addWidget(lbl_s_title)
        cs_layout.addWidget(self.lbl_spd_fused)
        cs_layout.addWidget(self.lbl_spd_truth)
        cs_layout.addWidget(self.lbl_spd_backend)
        m_layout.addWidget(c_speed)

        # Card 3: Altitude & Barometer Fusion
        c_alt = QtWidgets.QFrame()
        c_alt.setObjectName("MetricCard")
        ca_layout = QtWidgets.QVBoxLayout(c_alt)
        ca_layout.setContentsMargins(8, 6, 8, 6)
        lbl_a_title = QtWidgets.QLabel("VERTICAL STATE & ALTITUDE")
        lbl_a_title.setObjectName("MetricLabel")
        self.lbl_alt_idr = QtWidgets.QLabel("Fused Alt: 0.0 m")
        self.lbl_alt_idr.setObjectName("MetricValue")
        self.lbl_alt_truth = QtWidgets.QLabel("True Alt: 0.0 m | Baro: 0.0 m")
        self.lbl_alt_truth.setStyleSheet("font-size: 11px; color: #8b949e;")
        self.lbl_climb_rate = QtWidgets.QLabel("Climb Rate: +0.00 m/s")
        self.lbl_climb_rate.setStyleSheet("font-size: 11px; color: #00d2ff;")
        ca_layout.addWidget(lbl_a_title)
        ca_layout.addWidget(self.lbl_alt_idr)
        ca_layout.addWidget(self.lbl_alt_truth)
        ca_layout.addWidget(self.lbl_climb_rate)
        m_layout.addWidget(c_alt)

        # Card 4: In-Cabin Dynamic Alignment
        c_align = QtWidgets.QFrame()
        c_align.setObjectName("MetricCard")
        cal_layout = QtWidgets.QVBoxLayout(c_align)
        cal_layout.setContentsMargins(8, 6, 8, 6)
        lbl_al_title = QtWidgets.QLabel("PHONE CABIN ALIGNMENT (PCA)")
        lbl_al_title.setObjectName("MetricLabel")
        self.lbl_align_mount = QtWidgets.QLabel("Mount: Roll 12.0° | Pitch -35.0°")
        self.lbl_align_mount.setStyleSheet("font-size: 11px; color: #f0f6fc; font-weight: 600;")
        self.lbl_align_conf = QtWidgets.QLabel("Forward PCA Conf: 0.0% | LOCKED: NO")
        self.lbl_align_conf.setStyleSheet("font-size: 10px; color: #8b949e;")
        cal_layout.addWidget(lbl_al_title)
        cal_layout.addWidget(self.lbl_align_mount)
        cal_layout.addWidget(self.lbl_align_conf)
        m_layout.addWidget(c_align)

        # Card 5: GNSS Health & HDOP Weighting
        c_gnss = QtWidgets.QFrame()
        c_gnss.setObjectName("MetricCard")
        cg_layout = QtWidgets.QVBoxLayout(c_gnss)
        cg_layout.setContentsMargins(8, 6, 8, 6)
        lbl_g_title = QtWidgets.QLabel("SIGMOID HDOP COVARIANCE")
        lbl_g_title.setObjectName("MetricLabel")
        self.lbl_hdop_val = QtWidgets.QLabel("HDOP: 0.80 | R_cov: 2.0 m²")
        self.lbl_hdop_val.setStyleSheet("font-size: 11px; color: #f0f6fc; font-weight: 600;")
        self.lbl_gnss_fixes = QtWidgets.QLabel("Fixes Accepted: 0 | Rejected: 0")
        self.lbl_gnss_fixes.setStyleSheet("font-size: 10px; color: #8b949e;")
        cg_layout.addWidget(lbl_g_title)
        cg_layout.addWidget(self.lbl_hdop_val)
        cg_layout.addWidget(self.lbl_gnss_fixes)
        m_layout.addWidget(c_gnss)

        # Card 6: Heading & Gyroscope
        c_yaw = QtWidgets.QFrame()
        c_yaw.setObjectName("MetricCard")
        cy_layout = QtWidgets.QVBoxLayout(c_yaw)
        cy_layout.setContentsMargins(8, 6, 8, 6)
        lbl_y_title = QtWidgets.QLabel("ATTITUDE & HEADING")
        lbl_y_title.setObjectName("MetricLabel")
        self.lbl_yaw_val = QtWidgets.QLabel("Yaw: 0.0° | Error: 0.0°")
        self.lbl_yaw_val.setStyleSheet("font-size: 11px; color: #f0f6fc; font-weight: 600;")
        self.lbl_gyro_bias = QtWidgets.QLabel("Gyro Z Bias Trim: 0.000 °/s")
        self.lbl_gyro_bias.setStyleSheet("font-size: 10px; color: #8b949e;")
        cy_layout.addWidget(lbl_y_title)
        cy_layout.addWidget(self.lbl_yaw_val)
        cy_layout.addWidget(self.lbl_gyro_bias)
        m_layout.addWidget(c_yaw)

        scroll.setWidget(scroll_content)
        s_layout.addWidget(scroll, stretch=1)

        # Simulation Interactive Toggles
        tog_box = QtWidgets.QGroupBox("Live Scenario Toggles")
        tb_layout = QtWidgets.QGridLayout(tog_box)
        tb_layout.setContentsMargins(6, 6, 6, 6)
        tb_layout.setSpacing(4)

        self.chk_potholes = QtWidgets.QCheckBox("Potholes / Rough")
        self.chk_potholes.setChecked(self.options.enable_potholes)
        self.chk_potholes.toggled.connect(self._on_options_changed)

        self.chk_gnss = QtWidgets.QCheckBox("Tunnel Blackout")
        self.chk_gnss.setChecked(self.options.enable_gnss_outage)
        self.chk_gnss.toggled.connect(self._on_options_changed)

        self.chk_nhc = QtWidgets.QCheckBox("NHC Virtual Constraints")
        self.chk_nhc.setChecked(self.options.enable_nhc)
        self.chk_nhc.toggled.connect(self._on_options_changed)

        self.chk_map = QtWidgets.QCheckBox("Map Snapping")
        self.chk_map.setChecked(self.options.enable_map_snapping)
        self.chk_map.toggled.connect(self._on_options_changed)

        self.chk_gate = QtWidgets.QCheckBox("Vibration Gate")
        self.chk_gate.setChecked(self.options.enable_vibration_gate)
        self.chk_gate.toggled.connect(self._on_options_changed)

        self.chk_baro = QtWidgets.QCheckBox("Barometer Fusion")
        self.chk_baro.setChecked(self.options.enable_baro)
        self.chk_baro.toggled.connect(self._on_options_changed)

        tb_layout.addWidget(self.chk_potholes, 0, 0)
        tb_layout.addWidget(self.chk_gnss, 0, 1)
        tb_layout.addWidget(self.chk_nhc, 1, 0)
        tb_layout.addWidget(self.chk_map, 1, 1)
        tb_layout.addWidget(self.chk_gate, 2, 0)
        tb_layout.addWidget(self.chk_baro, 2, 1)
        s_layout.addWidget(tog_box)

        # Playback Controls Card
        ctrl_card = QtWidgets.QFrame()
        ctrl_card.setObjectName("MetricCard")
        cc_layout = QtWidgets.QVBoxLayout(ctrl_card)
        cc_layout.setContentsMargins(6, 6, 6, 6)

        btn_row = QtWidgets.QHBoxLayout()
        self.btn_play = QtWidgets.QPushButton("PAUSE")
        self.btn_play.setObjectName("PrimaryBtn")
        self.btn_play.clicked.connect(self._toggle_playback)

        self.btn_step = QtWidgets.QPushButton("STEP (+10)")
        self.btn_step.clicked.connect(self._step_once)

        self.btn_reset = QtWidgets.QPushButton("RESET")
        self.btn_reset.setObjectName("DangerBtn")
        self.btn_reset.clicked.connect(self._reset_sim)

        btn_row.addWidget(self.btn_play)
        btn_row.addWidget(self.btn_step)
        btn_row.addWidget(self.btn_reset)
        cc_layout.addLayout(btn_row)

        speed_row = QtWidgets.QHBoxLayout()
        lbl_sp = QtWidgets.QLabel("Sim Speed:")
        lbl_sp.setStyleSheet("font-weight: 600; color: #8b949e;")
        self.slider_speed = QtWidgets.QSlider(QtCore.Qt.Horizontal)
        self.slider_speed.setRange(1, 10)
        self.slider_speed.setValue(1)
        self.slider_speed.valueChanged.connect(self._on_speed_changed)
        self.lbl_speed_val = QtWidgets.QLabel("1.0x (100 Hz)")
        self.lbl_speed_val.setStyleSheet("font-weight: 700; color: #58a6ff;")
        speed_row.addWidget(lbl_sp)
        speed_row.addWidget(self.slider_speed)
        speed_row.addWidget(self.lbl_speed_val)
        cc_layout.addLayout(speed_row)

        s_layout.addWidget(ctrl_card)
        main_layout.addWidget(sidebar)

        # --------------------- RIGHT MAIN VIEWPORT & PLOTS ---------------------
        right_panel = QtWidgets.QWidget()
        rp_layout = QtWidgets.QVBoxLayout(right_panel)
        rp_layout.setContentsMargins(0, 0, 0, 0)
        rp_layout.setSpacing(6)

        # Viewport Mode Toolbar & Tabs
        top_bar = QtWidgets.QHBoxLayout()
        self.tab_views = QtWidgets.QTabWidget()
        self.tab_views.setStyleSheet("QTabWidget::pane { border: 1px solid #1f2a3d; border-radius: 6px; }")

        # 2D Map Tab
        self.map_2d = pg.PlotWidget(title="<b>2D Bird's-Eye View: Road Network & Trajectory Tracking</b>")
        self.map_2d.setBackground('#090d14')
        self.map_2d.showGrid(x=True, y=True, alpha=0.25)
        self.map_2d.setAspectLocked(True)
        self.map_2d.setLabel('left', 'World Y (North)', units='m')
        self.map_2d.setLabel('bottom', 'World X (East)', units='m')
        self.tab_views.addTab(self.map_2d, "  2D Bird's-Eye Map  ")

        # 3D OpenGL Tab
        self.map_3d = IDR3DWidget()
        self.tab_views.addTab(self.map_3d, "  3D Multi-Level & Flyover View (OpenGL)  ")

        # Split Dual View Tab
        self.dual_splitter = QtWidgets.QSplitter(QtCore.Qt.Horizontal)
        self.dual_map_2d = pg.PlotWidget(title="<b>2D Bird's-Eye</b>")
        self.dual_map_2d.setBackground('#090d14')
        self.dual_map_2d.showGrid(x=True, y=True, alpha=0.25)
        self.dual_map_2d.setAspectLocked(True)
        self.dual_map_3d = IDR3DWidget()
        self.dual_splitter.addWidget(self.dual_map_2d)
        self.dual_splitter.addWidget(self.dual_map_3d)
        self.tab_views.addTab(self.dual_splitter, "  Dual 2D + 3D View  ")
        self.tab_views.currentChanged.connect(self._on_tab_changed)

        # Viewport options bar
        self.chk_follow = QtWidgets.QCheckBox("Auto-Follow Vehicle")
        self.chk_follow.setChecked(True)

        self.btn_fit_view = QtWidgets.QPushButton("Fit Trajectories")
        self.btn_fit_view.clicked.connect(self._fit_view_all)

        top_bar.addWidget(QtWidgets.QLabel("<b>Viewports:</b>"))
        top_bar.addStretch()
        top_bar.addWidget(self.chk_follow)
        top_bar.addWidget(self.btn_fit_view)
        rp_layout.addLayout(top_bar)
        rp_layout.addWidget(self.tab_views, stretch=5)

        # --------------------- BOTTOM OSCILLOSCOPES ---------------------
        scopes_box = QtWidgets.QGroupBox("Real-Time Telemetry Oscilloscopes")
        sb_layout = QtWidgets.QHBoxLayout(scopes_box)
        sb_layout.setContentsMargins(6, 8, 6, 6)
        sb_layout.setSpacing(6)

        # Scope 1: Jerk & Vibration Gate
        self.scope_jerk = pg.PlotWidget(title="<b>Kinetic Jerk Variance (Pothole Gate)</b>")
        self.scope_jerk.setBackground('#090d14')
        self.scope_jerk.showGrid(x=True, y=True, alpha=0.2)
        self.scope_jerk.setLabel('left', 'Jerk Var', units='m²/s⁶')
        self.scope_jerk.setLabel('bottom', 'Time', units='s')

        # Scope 2: Barometer & Altitude
        self.scope_alt = pg.PlotWidget(title="<b>Elevation (Flyover / Tunnel Altitude)</b>")
        self.scope_alt.setBackground('#090d14')
        self.scope_alt.showGrid(x=True, y=True, alpha=0.2)
        self.scope_alt.setLabel('left', 'Altitude', units='m')
        self.scope_alt.setLabel('bottom', 'Time', units='s')

        # Scope 3: Speed Estimation
        self.scope_speed = pg.PlotWidget(title="<b>Speed Engine (TCN vs Ground Truth)</b>")
        self.scope_speed.setBackground('#090d14')
        self.scope_speed.showGrid(x=True, y=True, alpha=0.2)
        self.scope_speed.setLabel('left', 'Speed', units='m/s')
        self.scope_speed.setLabel('bottom', 'Time', units='s')

        sb_layout.addWidget(self.scope_jerk)
        sb_layout.addWidget(self.scope_alt)
        sb_layout.addWidget(self.scope_speed)
        rp_layout.addWidget(scopes_box, stretch=3)

        main_layout.addWidget(right_panel, stretch=1)

    # -------------------------------------------------------------- PLOTS INIT
    def _init_plots(self):
        # 2D Map Curves
        self.map_2d.addLegend(offset=(10, 10))

        # Static road center line
        centerline = self.pipe.geometry.centerline(step_m=4.0)
        self.curve_road = self.map_2d.plot(
            centerline[:, 0], centerline[:, 1],
            pen=pg.mkPen(color=(70, 85, 105), width=7),
            name="Road Corridor"
        )
        self.curve_road_center = self.map_2d.plot(
            centerline[:, 0], centerline[:, 1],
            pen=pg.mkPen(color=(255, 215, 0, 120), width=1.5, style=QtCore.Qt.DashLine)
        )

        # Service road decoy under flyover
        decoy = self.pipe.geometry.decoy_branch(step_m=4.0)
        if len(decoy) >= 2:
            self.curve_decoy = self.map_2d.plot(
                decoy[:, 0], decoy[:, 1],
                pen=pg.mkPen(color=(120, 100, 50, 140), width=3, style=QtCore.Qt.DotLine),
                name="At-Grade Service Road"
            )

        # Ground Truth Trajectory (White dashed)
        self.curve_gt = self.map_2d.plot(
            pen=pg.mkPen(color=(240, 246, 252, 220), width=2, style=QtCore.Qt.DashLine),
            name="Ground Truth Path"
        )

        # IDR Proposed Trajectory (Vibrant Neon Green)
        self.curve_idr = self.map_2d.plot(
            pen=pg.mkPen(color=(0, 230, 118), width=3.5),
            name="IDR Proposed System"
        )

        # Classic DR Baseline Trajectory (Red Drifting)
        self.curve_classic = self.map_2d.plot(
            pen=pg.mkPen(color=(255, 61, 113, 200), width=2.0),
            name="Classic Double Integration"
        )

        # GNSS Raw Fixes Scatter
        self.scatter_gnss = pg.ScatterPlotItem(
            size=6,
            pen=pg.mkPen(None),
            brush=pg.mkBrush(0, 210, 255, 160),
            name="GNSS Fixes"
        )
        self.map_2d.addItem(self.scatter_gnss)

        # Current Vehicle Marker (Triangle)
        self.marker_veh = pg.ScatterPlotItem(
            size=14,
            symbol='arrow_up',
            brush=pg.mkBrush(0, 210, 255),
            pen=pg.mkPen('w', width=1.5)
        )
        self.map_2d.addItem(self.marker_veh)

        # Map Snapping target line
        self.curve_snap = self.map_2d.plot(
            pen=pg.mkPen(color=(255, 235, 59, 180), width=1.5, style=QtCore.Qt.DotLine)
        )

        # Setup 3D static roads
        self.map_3d.set_static_roads(centerline, decoy)
        self.dual_map_3d.set_static_roads(centerline, decoy)

        # Setup dual 2D view
        self.dual_curve_gt = self.dual_map_2d.plot(
            pen=pg.mkPen(color=(240, 246, 252, 200), width=1.5, style=QtCore.Qt.DashLine)
        )
        self.dual_curve_idr = self.dual_map_2d.plot(
            pen=pg.mkPen(color=(0, 230, 118), width=3.0)
        )
        self.dual_curve_classic = self.dual_map_2d.plot(
            pen=pg.mkPen(color=(255, 61, 113, 180), width=1.5)
        )
        self.dual_marker_veh = pg.ScatterPlotItem(
            size=12,
            symbol='arrow_up',
            brush=pg.mkBrush(0, 210, 255)
        )
        self.dual_map_2d.addItem(self.dual_marker_veh)

        # Oscilloscope 1: Jerk
        self.scope_jerk.addLegend(offset=(10, 10))
        self.osc_jerk_raw = self.scope_jerk.plot(pen=pg.mkPen(color=(0, 210, 255, 160), width=1.2), name="Raw Jerk")
        self.osc_jerk_var = self.scope_jerk.plot(pen=pg.mkPen(color=(255, 171, 0), width=2.0), name="Jerk Variance")
        self.osc_jerk_thresh = self.scope_jerk.plot(
            pen=pg.mkPen(color=(255, 61, 113), width=1.5, style=QtCore.Qt.DashLine),
            name="Shock Threshold"
        )

        # Oscilloscope 2: Altitude
        self.scope_alt.addLegend(offset=(10, 10))
        self.osc_alt_true = self.scope_alt.plot(pen=pg.mkPen(color='w', width=2.0, style=QtCore.Qt.DashLine), name="True Elevation")
        self.osc_alt_idr = self.scope_alt.plot(pen=pg.mkPen(color=(0, 230, 118), width=2.5), name="IDR Altitude")
        self.osc_alt_baro = self.scope_alt.plot(pen=pg.mkPen(color=(0, 210, 255, 180), width=1.2), name="Barometer Alt")

        # Oscilloscope 3: Speed
        self.scope_speed.addLegend(offset=(10, 10))
        self.osc_spd_true = self.scope_speed.plot(pen=pg.mkPen(color='w', width=2.0, style=QtCore.Qt.DashLine), name="True Speed")
        self.osc_spd_idr = self.scope_speed.plot(pen=pg.mkPen(color=(0, 210, 255), width=2.2), name="TCN / Fused Speed")
        self.osc_spd_cls = self.scope_speed.plot(pen=pg.mkPen(color=(255, 61, 113, 160), width=1.5), name="Classic Speed")

    # ------------------------------------------------------------- WORKER SLOTS
    @QtCore.Slot(dict, dict)
    def _on_worker_telemetry(self, rec: dict, snap: dict):
        self._last_rec = rec
        self._last_snap = snap
        self._render_ui(rec, snap)

    @QtCore.Slot()
    def _on_worker_finished(self):
        self.btn_play.setText("REPLAY")
        self.btn_play.setObjectName("")
        self.btn_play.setStyle(self.btn_play.style())

    def _render_ui(self, rec: dict, snap: dict):
        if not rec or "err_idr" not in rec or not snap:
            return

        # 1. Update Telemetry HUD Metrics
        err_idr = rec["err_idr"]
        err_cls = rec["err_classic"]
        self.lbl_idr_drift.setText(f"IDR (Proposed): {err_idr:6.2f} m")
        self.lbl_cls_drift.setText(f"Classic DR:    {err_cls:8.1f} m")

        red_pct = max(0.0, min(100.0, (1.0 - err_idr / max(err_cls, 1e-4)) * 100.0))
        self.lbl_drift_red.setText(f"Drift Reduction: {red_pct:5.1f}%")

        spd_kmh = rec["idr_speed"] * 3.6
        true_kmh = rec["truth_speed"] * 3.6
        self.lbl_spd_fused.setText(f"Fused: {spd_kmh:5.1f} km/h ({rec['idr_speed']:4.1f} m/s)")
        self.lbl_spd_truth.setText(f"Ground Truth: {true_kmh:5.1f} km/h (v_tcn: {rec['v_tcn']:4.1f} m/s)")
        self.lbl_spd_backend.setText(f"Engine: {rec['speed_backend'].upper()} Backend")

        self.lbl_alt_idr.setText(f"Fused Alt: {rec['idr_pos'][2]:6.2f} m")
        baro_txt = f"{rec['baro_alt']:6.2f} m" if rec['baro_alt'] is not None else "N/A"
        self.lbl_alt_truth.setText(f"True: {rec['truth'][2]:6.2f} m | Baro: {baro_txt}")
        self.lbl_climb_rate.setText(f"Climb Rate: {rec['idr_vel'][2]:+5.2f} m/s")

        self.lbl_align_mount.setText(f"Mount: Roll {rec['mount_roll']:+5.1f}° | Pitch {rec['mount_pitch']:+5.1f}°")
        lock_str = "LOCKED" if rec["align_locked"] else "ESTIMATING"
        self.lbl_align_conf.setText(f"PCA Conf: {rec['align_conf']*100:4.1f}% | Status: {lock_str}")

        self.lbl_hdop_val.setText(f"HDOP: {rec['hdop']:5.2f} | R_cov: {rec['gnss_r']:6.1f} m²")
        self.lbl_gnss_fixes.setText(f"Fixes Used: {int(rec['gnss_used'])} | Reject: {rec['gnss_rejects']}")

        yaw_deg = float(np.degrees(rec['idr_yaw']))
        self.lbl_yaw_val.setText(f"Yaw: {yaw_deg:6.1f}° | Error: {rec['yaw_err_deg']:+5.2f}°")
        self.lbl_gyro_bias.setText(f"Gyro Z Bias: {float(np.degrees(rec['gyro_bias_z'])):+6.3f} °/s")

        # 2. Master Status Badges
        if rec["is_tunnel"]:
            self.lbl_master_gnss.setText("GNSS: DENIED (180s Subterranean Tunnel)")
            self.lbl_master_gnss.setStyleSheet("font-size: 12px; font-weight: 800; color: #ff3d71;")
            self.status_card.setStyleSheet("QFrame#MetricCard { border: 1px solid #ff3d71; background-color: #23121b; }")
        elif rec["is_canyon"]:
            self.lbl_master_gnss.setText("GNSS: DEGRADED (Urban Canyon Multipath)")
            self.lbl_master_gnss.setStyleSheet("font-size: 12px; font-weight: 800; color: #ffab00;")
            self.status_card.setStyleSheet("QFrame#MetricCard { border: 1px solid #ffab00; background-color: #241d12; }")
        else:
            self.lbl_master_gnss.setText("GNSS: NOMINAL (Open Sky Fixed)")
            self.lbl_master_gnss.setStyleSheet("font-size: 12px; font-weight: 800; color: #00e676;")
            self.status_card.setStyleSheet("QFrame#MetricCard { border: 1px solid #1f2a3d; background-color: #161f30; }")

        if rec["shock"]:
            self.lbl_master_gate.setText(f"VIBRATION GATE: SHOCK DETECTED (Update Frozen #{rec['shock_events']})")
            self.lbl_master_gate.setStyleSheet("font-size: 11px; font-weight: 700; color: #ffab00;")
        else:
            self.lbl_master_gate.setText("VIBRATION GATE: NORMAL ROAD SURFACE")
            self.lbl_master_gate.setStyleSheet("font-size: 11px; font-weight: 600; color: #8b949e;")

        # Active phase string
        phase = "1. Straight Cruise"
        if rec["is_tunnel"]:
            phase = "6. 180s Deep Tunnel (GNSS Denied)"
        elif rec["is_canyon"]:
            phase = "5. Urban Canyon (Multipath & Shadowing)"
        elif rec["is_flyover"]:
            phase = "4. Multi-Level Flyover Split (+8m Elevation)"
        elif rec["is_rough"]:
            phase = "3. Rough Road & Potholes (Shock Rejection)"
        elif rec["t"] > 15.0:
            phase = "2. High-Speed Gentle Curve"
        self.lbl_zone_phase.setText(f"Route Phase: {phase}")

        # Progress bar
        prog = rec["progress"]
        pct = int(round(prog * 100))
        self.prog_bar.setValue(pct)
        total_len = snap.get("total_len", 4064.0)
        dist = prog * total_len
        self.lbl_prog_text.setText(f"{dist:.0f} m / {total_len:.0f} m ({pct}%)")

        # 3. Viewport-Aware Trajectory Updates
        gt_arr = snap["gt_arr"]
        idr_arr = snap["idr_arr"]
        cls_arr = snap["cls_arr"]
        gnss_arr = snap["gnss_arr"]

        if len(gt_arr) > 1:
            curr_tab = self.tab_views.currentIndex()
            curr_x, curr_y = rec["idr_pos"][0], rec["idr_pos"][1]
            yaw_deg = float(np.degrees(rec["idr_yaw"]))

            # Tab 0: 2D Bird's-Eye Map
            if curr_tab == 0:
                self.curve_gt.setData(gt_arr[:, 0], gt_arr[:, 1])
                self.curve_idr.setData(idr_arr[:, 0], idr_arr[:, 1])
                self.curve_classic.setData(cls_arr[:, 0], cls_arr[:, 1])

                self.marker_veh.setData(x=[curr_x], y=[curr_y], angle=[yaw_deg - 90])

                if len(gnss_arr) > 0:
                    self.scatter_gnss.setData(pos=gnss_arr[:, :2])

                if rec["match"] is not None:
                    foot = rec["match"].point
                    self.curve_snap.setData([curr_x, foot[0]], [curr_y, foot[1]])
                else:
                    self.curve_snap.clear()

                if self.chk_follow.isChecked():
                    span = 140.0
                    self.map_2d.setXRange(curr_x - span, curr_x + span, padding=0)
                    self.map_2d.setYRange(curr_y - span, curr_y + span, padding=0)

            # Tab 1: 3D OpenGL View
            elif curr_tab == 1:
                try:
                    self.map_3d.update_paths(gt_arr, idr_arr, cls_arr, rec["idr_pos"])
                except Exception:
                    pass

            # Tab 2: Dual View (Split 2D + 3D)
            elif curr_tab == 2:
                self.dual_curve_gt.setData(gt_arr[:, 0], gt_arr[:, 1])
                self.dual_curve_idr.setData(idr_arr[:, 0], idr_arr[:, 1])
                self.dual_curve_classic.setData(cls_arr[:, 0], cls_arr[:, 1])
                self.dual_marker_veh.setData(x=[curr_x], y=[curr_y], angle=[yaw_deg - 90])

                if self.chk_follow.isChecked():
                    span = 140.0
                    self.dual_map_2d.setXRange(curr_x - span, curr_x + span, padding=0)
                    self.dual_map_2d.setYRange(curr_y - span, curr_y + span, padding=0)

                try:
                    self.dual_map_3d.update_paths(gt_arr, idr_arr, cls_arr, rec["idr_pos"])
                except Exception:
                    pass

        # 4. Update Oscilloscopes
        sub_t = snap["sub_t"]
        if len(sub_t) > 10:
            # Scope 1: Jerk
            self.osc_jerk_raw.setData(sub_t, snap["j_raw"])
            self.osc_jerk_var.setData(sub_t, snap["j_var"])
            thresh = np.full(len(sub_t), snap["gate_thresh"], dtype=np.float32)
            self.osc_jerk_thresh.setData(sub_t, thresh)

            # Scope 2: Altitude
            self.osc_alt_true.setData(sub_t, snap["alt_t"])
            self.osc_alt_idr.setData(sub_t, snap["alt_i"])
            baro_t = snap["baro_t"]
            if len(baro_t) > 0:
                self.osc_alt_baro.setData(baro_t, snap["baro_z"])

            # Scope 3: Speed
            self.osc_spd_true.setData(sub_t, snap["s_true"])
            self.osc_spd_idr.setData(sub_t, snap["s_tcn"])
            self.osc_spd_cls.setData(sub_t, snap["s_cls"])

    # ------------------------------------------------------------- CONTROLS
    def _on_tab_changed(self, idx: int):
        if self._last_rec is not None and self._last_snap is not None:
            self._render_ui(self._last_rec, self._last_snap)

    def _toggle_playback(self):
        if self.worker.is_finished:
            self._reset_sim()
            return
        is_running = self.worker.toggle_playback()
        if is_running:
            self.btn_play.setText("PAUSE")
            self.btn_play.setObjectName("PrimaryBtn")
        else:
            self.btn_play.setText("PLAY")
            self.btn_play.setObjectName("")
        self.btn_play.setStyle(self.btn_play.style())

    def _step_once(self):
        self.btn_play.setText("PLAY")
        self.btn_play.setObjectName("")
        self.btn_play.setStyle(self.btn_play.style())
        self.worker.step_n(10, wait=True)

    def _reset_sim(self):
        self.btn_play.setText("PAUSE")
        self.btn_play.setObjectName("PrimaryBtn")
        self.btn_play.setStyle(self.btn_play.style())
        self._fit_view_all()
        self.worker.request_reset(self.options)

    def _on_speed_changed(self, val: int):
        # 1 -> 1x, 2 -> 2x, 3 -> 4x, 4 -> 8x, 5 -> 15x, 6 -> 25x, 7 -> 40x, etc.
        multipliers = [1.0, 2.0, 4.0, 8.0, 15.0, 25.0, 40.0, 60.0, 80.0, 100.0]
        mult = multipliers[val - 1]
        self.worker.set_speed(mult)
        self.lbl_speed_val.setText(f"{mult:.0f}x ({int(100*mult)} Hz)")

    def _on_options_changed(self):
        self.options.enable_potholes = self.chk_potholes.isChecked()
        self.options.enable_gnss_outage = self.chk_gnss.isChecked()
        self.options.enable_nhc = self.chk_nhc.isChecked()
        self.options.enable_map_snapping = self.chk_map.isChecked()
        self.options.enable_vibration_gate = self.chk_gate.isChecked()
        self.options.enable_baro = self.chk_baro.isChecked()
        self.worker.update_options(self.options)

    def _fit_view_all(self):
        centerline = self.pipe.geometry.centerline(step_m=10.0)
        xmin, xmax = float(centerline[:, 0].min()) - 50, float(centerline[:, 0].max()) + 50
        ymin, ymax = float(centerline[:, 1].min()) - 50, float(centerline[:, 1].max()) + 50
        self.map_2d.setXRange(xmin, xmax, padding=0.05)
        self.map_2d.setYRange(ymin, ymax, padding=0.05)
        self.dual_map_2d.setXRange(xmin, xmax, padding=0.05)
        self.dual_map_2d.setYRange(ymin, ymax, padding=0.05)

    def close(self) -> bool:
        if hasattr(self, 'worker') and self.worker.isRunning():
            self.worker.stop()
            self.worker.wait(1000)
        return super().close()

    def closeEvent(self, event: QtGui.QCloseEvent):
        if hasattr(self, 'worker') and self.worker.isRunning():
            self.worker.stop()
            self.worker.wait(1000)
        event.accept()

    def __del__(self):
        try:
            if hasattr(self, 'worker') and self.worker is not None:
                self.worker.stop()
                self.worker.wait(500)
        except Exception:
            pass


# =================================================================== MAIN
def main():
    app = QtWidgets.QApplication(sys.argv)
    app.setStyle('Fusion')
    gui = IDRDesktopApp()
    gui.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
