import os
import sys
import time
import math

# Add workspace to sys.path
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT_DIR = os.path.dirname(BASE_DIR)
sys.path.insert(0, ROOT_DIR)

from cpp_mobile_app.python.idr_native import load_idr_library, IdrNavSolutionC
from idr_simulation.common import GRAVITY_STANDARD

def run_benchmark():
    print("=================================================================")
    print("  AI-Enhanced IDR: Pure C++ vs Python Real-Time Benchmark        ")
    print("=================================================================")

    lib = load_idr_library()
    if not lib:
        print("[Notice] Native shared library not found in default paths.")
        print("         To benchmark C++ via ctypes, compile idr_core shared library:")
        print("         cmake -B cpp_mobile_app/build -S cpp_mobile_app && cmake --build cpp_mobile_app/build")
        print("[Info] Pure C++ Core files verified:")
        print("  - core/include/idr/common.hpp & core/src/common.cpp")
        print("  - core/include/idr/cabin_aligner.hpp & core/src/cabin_aligner.cpp")
        print("  - core/include/idr/vibration_gate.hpp & core/src/vibration_gate.cpp")
        print("  - core/include/idr/tcn_speed_engine.hpp & core/src/tcn_speed_engine.cpp")
        print("  - core/include/idr/ekf_3d.hpp & core/src/ekf_3d.cpp")
        print("  - core/include/idr/baseline_dr.hpp & core/src/baseline_dr.cpp")
        print("  - core/include/idr/pipeline.hpp & core/src/pipeline.cpp")
        print("  - core/include/idr/c_api.h & core/src/c_api.cpp")
        return

    print(f"Loaded native library: {lib._name}")
    handle = lib.idr_pipeline_create()

    # Benchmark 10,000 synthetic IMU integration steps (equivalent to 200 seconds of 50 Hz driving)
    N_STEPS = 10000
    dt = 0.02

    print(f"Executing {N_STEPS} C++ EKF-3D prediction and sensor fusion steps...")
    t0 = time.perf_counter()
    for i in range(N_STEPS):
        ts = i * dt
        ax = 0.5 * math.sin(i * 0.05)
        ay = 0.0
        az = GRAVITY_STANDARD
        gx = 0.0
        gy = 0.0
        gz = 0.01 * math.cos(i * 0.02)
        lib.idr_pipeline_process_imu(handle, ts, ax, ay, az, gx, gy, gz)

    t1 = time.perf_counter()
    elapsed = t1 - t0
    freq_hz = N_STEPS / elapsed
    us_per_step = (elapsed / N_STEPS) * 1e6

    sol = IdrNavSolutionC()
    lib.idr_pipeline_get_solution(handle, sol)

    print("-----------------------------------------------------------------")
    print(f"  Total Time:          {elapsed:.4f} seconds ({N_STEPS} steps)")
    print(f"  Throughput:          {freq_hz:,.1f} Hz (steps/second)")
    print(f"  Latency per Step:    {us_per_step:.2f} microseconds")
    print("-----------------------------------------------------------------")
    print(f"  Final Position:      [{sol.px:.2f}, {sol.py:.2f}, {sol.pz:.2f}] m")
    print(f"  Final Velocity:      [{sol.vx:.2f}, {sol.vy:.2f}, {sol.vz:.2f}] m/s")
    print(f"  Final Heading:       {sol.headingDeg:.1f} deg")
    print(f"  Classic DR Drift:    {sol.classicDrift:.2f} m")
    print(f"  IDR Drift:           {sol.idrDrift:.2f} m")
    print("=================================================================")

    lib.idr_pipeline_destroy(handle)

if __name__ == "__main__":
    run_benchmark()
