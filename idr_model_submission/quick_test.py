#!/usr/bin/env python3
"""
================================================================================
IDR-NeuroSpeed-TCN : 30-Second Quick Test for Evaluators
Smart India Hackathon (SIH 2026) Model Verification
================================================================================
This script is designed for hackathon judges who want a clean, zero-friction test.
It runs a single 120-second tunnel outage test in ~2 seconds and shows the verdict.

How to run:
    python quick_test.py
================================================================================
"""

import sys
import json
from pathlib import Path
import numpy as np

def run_quick_evaluation():
    base_dir = Path(__file__).resolve().parent
    sys.path.insert(0, str(base_dir))
    from test import load_scenario_csv, prepare_sliding_windows, apply_production_filter

    model_path = base_dir / "idr_neurospeed_tcn.onnx"
    stats_path = base_dir / "normalize_stats.json"
    data_path = base_dir / "sample_data" / "scenario_1_highway_tunnel_outage.csv"

    print("=" * 68)
    print("   IDR-NeuroSpeed-TCN : QUICK EVALUATOR VERIFICATION (SIH 2026)")
    print("=" * 68)

    # 1. Load ONNX Runtime
    try:
        import onnxruntime as ort
    except ImportError:
        print("[!] onnxruntime not found. Please install: pip install onnxruntime")
        return

    print("[1/3] Loading ONNX model and normalization parameters...")
    session = ort.InferenceSession(str(model_path))
    with open(stats_path) as f:
        stats = json.load(f)

    mean = np.array(stats["mean"], dtype=np.float32)
    std = np.array(stats["std"], dtype=np.float32)
    scale = float(stats["speed_scale"])

    # 2. Parse sample scenario CSV
    print("[2/3] Loading 120-second simulated tunnel outage scenario...")
    imu, speed = load_scenario_csv(str(data_path))

    # Prepare sliding windows (40 steps = 4.0 seconds at 10 Hz)
    W = 40
    samples, num_windows = prepare_sliding_windows(imu, window_size=W)
    normed = (samples - mean[:, None][None, :, :]) / std[:, None][None, :, :]

    # 3. Model Inference
    print("[3/3] Running neural speed estimation...")
    input_name = session.get_inputs()[0].name
    outputs = session.run(None, {input_name: normed})
    raw_speeds = np.maximum(0.0, outputs[0].flatten() * scale)

    # Apply production exponential smoothing & zero-velocity deadband
    filtered_speeds = apply_production_filter(raw_speeds, zupt_threshold=0.15, alpha=0.65)

    # 4. Compute dead reckoning drift
    dt = 0.1  # 10 Hz sampling rate
    true_speed = speed[W - 1:]
    ground_truth_dist = float(np.sum(true_speed) * dt)
    predicted_dist = float(np.sum(filtered_speeds) * dt)
    position_error = abs(predicted_dist - ground_truth_dist)
    drift_percent = (position_error / ground_truth_dist) * 100.0
    mae_speed = float(np.mean(np.abs(filtered_speeds - true_speed)))

    # 5. Display scorecard
    print("-" * 68)
    print(f"  Test Scenario             : 120-Second Highway Tunnel Blackout")
    print(f"  Ground Truth GPS Distance : {ground_truth_dist:8.1f} meters (CAN/GPS)")
    print(f"  AI Estimated DR Distance  : {predicted_dist:8.1f} meters (Phone IMU only)")
    print(f"  Positional Drift Error    : {position_error:8.1f} meters")
    print(f"  Speed Estimation Error    : {mae_speed:8.2f} m/s ({mae_speed * 3.6:.1f} km/h)")
    print(f"  Calculated Drift Rate     : {drift_percent:8.2f}%")
    print(f"  Official SIH Pass Limit   : < 10.00% drift")
    print("-" * 68)

    if drift_percent < 10.0:
        print("\033[92m\033[1m  >>> OFFICIAL SIH VERDICT: [PASSED] <<<\033[0m")
        print("  The model easily outperforms the hackathon < 10% drift criterion!")
    else:
        print("\033[91m\033[1m  >>> OFFICIAL SIH VERDICT: [FAILED] <<<\033[0m")
    print("=" * 68)
    print("\nTip: To test all 5 driving scenarios, run:  python test.py")

if __name__ == "__main__":
    run_quick_evaluation()
