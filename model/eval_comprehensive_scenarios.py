"""
Comprehensive Real-World Scenario Test Suite for Vehicle Speed TCN & IDR Pipeline

Categories evaluated:
1. Full-Trip Endurance (Entire journey evaluation from 5 to 55 minutes, up to 37 km)
2. Simulated GNSS Tunnel Outages (60s, 120s, and 300s dead-reckoning blackouts @ 70-100 km/h)
3. Maneuver-Specific Stress Scenarios:
   - Heavy Stop-and-Go Congestion (multiple stops & starts, low-speed crawl)
   - High-Speed Highway Cruise (sustained 70-110 km/h)
   - Sharp Corners & Roundabouts (high lateral acceleration and yaw rate)
   - Extended Standstill / Red Lights (60s - 200s stationary hold testing ZUPT)
4. Multi-Vehicle Transfer (Passenger cars, Motorbikes, Scooters, Commercial vans)
5. Dual Mode Evaluation: Raw ONNX vs Production Pipeline (with ZUPT & Kinematics)
"""

import os
import sys
import glob
import json
import math
from pathlib import Path
import numpy as np
import onnxruntime as ort

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from model.train import load_and_parse_iovnbd_file

ONNX_PATH = REPO_ROOT / "assets" / "models" / "vehicle_speed_tcn.onnx"
STATS_PATH = REPO_ROOT / "assets" / "models" / "normalize_stats.json"

class ProductionAppPipelineSimulator:
    """Exact replica of the Flutter IDR pipeline logic in tcn_speed_engine.dart:
    - Skog GLRT Zero-Velocity Update (ZUPT)
    - Kinematic launch forward accumulator during throttle tip-in
    - Hysteresis standstill latching and release
    - Dynamic exponential filter blending
    """
    def __init__(self):
        self.estimated_speed = 0.0
        self.launch_kinematic_speed = 0.0
        self.stationary_counter = 5
        self.stationary_hysteresis = 5
        self.is_stationary = True
        self.resting_fwd_accel = None

    def reset(self):
        self.estimated_speed = 0.0
        self.launch_kinematic_speed = 0.0
        self.stationary_counter = self.stationary_hysteresis
        self.is_stationary = True
        self.resting_fwd_accel = None

    def step(self, raw_pred_speed, imu_window, dt=0.1):
        # imu_window is (W, 6): [ax, ay, az, gx, gy, gz]
        w_acc = imu_window[:, 0:3]
        w_gyr = imu_window[:, 3:6]
        
        norm_a = np.linalg.norm(w_acc, axis=1)
        norm_w = np.linalg.norm(w_gyr, axis=1)
        
        acc_var = float(np.var(norm_a))
        gyr_var = float(np.var(norm_w))
        avg_yaw = float(np.mean(np.abs(w_gyr[:, 2])))
        avg_lat = float(np.mean(np.abs(w_acc[:, 1])))
        mean_x = float(np.mean(w_acc[:, 0]))

        is_coupled_turn = (avg_yaw > 0.20 and avg_lat > 0.40)

        # Adapt resting forward acceleration baseline (phone mount tilt / road slope)
        if self.resting_fwd_accel is None:
            self.resting_fwd_accel = mean_x
        elif self.is_stationary and avg_yaw < 0.20 and not is_coupled_turn:
            self.resting_fwd_accel = self.resting_fwd_accel * 0.95 + mean_x * 0.05

        fwd_throttle = mean_x - self.resting_fwd_accel

        # Forward throttle delta & launch assist (clamped to 6.0 m/s matching tcn_speed_engine.dart line 203-212)
        if fwd_throttle > 0.20:
            self.launch_kinematic_speed = min(6.0, max(0.0, self.launch_kinematic_speed + fwd_throttle * dt))
        elif fwd_throttle < -0.25:
            self.launch_kinematic_speed = max(0.0, self.launch_kinematic_speed + fwd_throttle * dt)
        else:
            self.launch_kinematic_speed = max(0.0, self.launch_kinematic_speed * (1.0 - 0.5 * dt))
            
        # Standstill detection (ZUPT) matching tcn_speed_engine.dart exactly:
        # Physical motion is required to break out of standstill (throttle or road roughness),
        # not stationary engine idle vibration noise.
        has_active_motion = (
            fwd_throttle > 0.25 or 
            self.launch_kinematic_speed > 0.20 or 
            (not self.is_stationary and acc_var > 2.5) or 
            is_coupled_turn
        )
        
        is_still = (acc_var < 0.50 and gyr_var < 0.08 and fwd_throttle < 0.18 and not has_active_motion)
        
        if has_active_motion:
            self.stationary_counter = 0
            self.is_stationary = False
        elif is_still:
            self.stationary_counter = min(self.stationary_counter + 1, self.stationary_hysteresis + 5)
            if self.stationary_counter >= self.stationary_hysteresis:
                self.is_stationary = True
                self.launch_kinematic_speed = 0.0

        if self.is_stationary:
            self.estimated_speed = 0.0
            return 0.0

        # Dynamic speed estimation
        z = max(0.0, float(raw_pred_speed))
        if self.estimated_speed == 0.0:
            self.estimated_speed = max(z, self.launch_kinematic_speed)
        else:
            self.estimated_speed = self.estimated_speed * 0.35 + z * 0.65

        return self.estimated_speed


class ScenarioEvaluator:
    def __init__(self):
        with open(STATS_PATH) as f:
            stats = json.load(f)
        self.mean = np.array(stats['mean'], dtype=np.float32)
        self.std = np.array(stats['std'], dtype=np.float32)
        self.scale = float(stats['speed_scale'])
        self.session = ort.InferenceSession(str(ONNX_PATH))
        self.pipeline_sim = ProductionAppPipelineSimulator()

    def run_inference(self, imu, W=40, batch_size=500):
        """Runs memory-safe batched inference over an IMU time series (N, 6)."""
        N = len(imu) - W
        if N <= 0:
            return np.array([]), np.array([])
        
        all_preds = []
        for start_idx in range(0, N, batch_size):
            end_idx = min(N, start_idx + batch_size)
            b_samples = []
            for i in range(start_idx, end_idx):
                w_acc = imu[i:i+W, 0:3]
                w_gyr = imu[i:i+W, 3:6]
                norm_a = np.linalg.norm(w_acc, axis=1, keepdims=True)
                norm_w = np.linalg.norm(w_gyr, axis=1, keepdims=True)
                w8 = np.concatenate([imu[i:i+W, :], norm_a, norm_w], axis=1).T
                b_samples.append(w8)
            b_arr = np.array(b_samples, dtype=np.float32)
            b_arr = (b_arr - self.mean[:, None][None, :, :]) / self.std[:, None][None, :, :]
            out = self.session.run(None, {'imu_input': b_arr})[0].flatten() * self.scale
            all_preds.append(np.maximum(0.0, out))
            
        return np.concatenate(all_preds), imu[W:]

    def evaluate_scenario(self, imu_slice, speed_slice, scenario_name, scenario_type):
        """Evaluates a slice under both Raw NN and Production Pipeline."""
        W = 40
        if len(imu_slice) <= W:
            return None
            
        raw_preds, imu_aligned = self.run_inference(imu_slice, W=W)
        truths = speed_slice[W-1:W-1+len(raw_preds)]
        
        if len(raw_preds) == 0 or len(truths) == 0:
            return None
            
        self.pipeline_sim.reset()
        pipe_preds = np.zeros_like(raw_preds)
        for k in range(len(raw_preds)):
            window = imu_slice[k:k+W]
            pipe_preds[k] = self.pipeline_sim.step(raw_preds[k], window, dt=0.1)
            
        dt = 0.1
        t_dist = float(np.sum(truths) * dt)
        raw_dist = float(np.sum(raw_preds) * dt)
        pipe_dist = float(np.sum(pipe_preds) * dt)
        
        pipe_err = abs(pipe_dist - t_dist)
        raw_err = abs(raw_dist - t_dist)
        
        if t_dist < 30.0:
            pipe_drift = (pipe_err / 30.0) * 100.0
            raw_drift = (raw_err / 30.0) * 100.0
            pipe_pass = (pipe_err < 8.0)
        else:
            pipe_drift = (pipe_err / t_dist) * 100.0
            raw_drift = (raw_err / t_dist) * 100.0
            pipe_pass = (pipe_drift < 10.0) or (pipe_err < 5.0)
            
        pipe_mae = float(np.mean(np.abs(pipe_preds - truths)))
        raw_mae = float(np.mean(np.abs(raw_preds - truths)))
        
        return {
            'name': scenario_name,
            'type': scenario_type,
            'duration_s': len(truths) * dt,
            'true_dist_m': t_dist,
            'raw_dist_m': raw_dist,
            'pipe_dist_m': pipe_dist,
            'raw_err_m': raw_err,
            'pipe_err_m': pipe_err,
            'raw_drift_pct': raw_drift,
            'pipe_drift_pct': pipe_drift,
            'raw_mae': raw_mae,
            'pipe_mae': pipe_mae,
            'passed': pipe_pass,
            'max_true_speed': float(np.max(truths)) * 3.6,
            'mean_true_speed': float(np.mean(truths)) * 3.6,
        }

def find_candidate_files():
    all_s = glob.glob(str(REPO_ROOT / 'model' / '**' / 'S-*.csv'), recursive=True)
    unique_by_name = {}
    for f in all_s:
        bn = os.path.basename(f)
        if bn not in unique_by_name:
            unique_by_name[bn] = f
    return unique_by_name

def run_all_scenarios():
    evaluator = ScenarioEvaluator()
    file_map = find_candidate_files()
    
    scenarios_results = []
    
    print("=" * 80)
    print("       STARTING COMPREHENSIVE AUTOMOTIVE SCENARIO BENCHMARK")
    print("=" * 80)
    
    # -------------------------------------------------------------
    # CATEGORY 1: FULL-TRIP ENDURANCE BENCHMARK (Entire Journey)
    # -------------------------------------------------------------
    print("\n--- CATEGORY 1: FULL-TRIP ENDURANCE SCENARIOS ---")
    full_trip_keys = [
        ('S-Vta1.csv', 'Urban Commute (Full 7 min)'),
        ('S-Vta2.csv', 'City Perimeter Drive (Full 7.5 min)'),
        ('S-Vta7.csv', 'Suburban Route (Full 6 min)'),
        ('S-Vta11.csv', 'Arterial Corridor (Full 7.5 min)'),
        ('S-Vtb2.csv', 'Mixed City/Ring-road (Full 9 min)'),
        ('S-Vtb8.csv', 'Free-Flow Suburban Loop (Full 5 min)'),
        ('S-Vtb1.csv', 'Long-Haul Highway Endurance (Full 54 min / 37 km)'),
        ('S-Vw16a.csv', 'Highway Express Route (Full 10 min / 8 km)'),
    ]
    for fn, label in full_trip_keys:
        if fn in file_map:
            parsed = load_and_parse_iovnbd_file(file_map[fn])
            if parsed:
                imu, speed = parsed
                res = evaluator.evaluate_scenario(imu, speed, f"{fn} - {label}", "Full-Trip Endurance")
                if res:
                    scenarios_results.append(res)
                    stat = "[PASS]" if res['passed'] else "[FAIL]"
                    print(f"  {stat} {res['name']:<48} | Dist: {res['true_dist_m']:7.1f}m | Drift: {res['pipe_drift_pct']:5.2f}% | MAE: {res['pipe_mae']:.2f} m/s")

    # -------------------------------------------------------------
    # CATEGORY 2: SIMULATED GNSS TUNNEL OUTAGES (60s, 120s, 300s)
    # -------------------------------------------------------------
    print("\n--- CATEGORY 2: SIMULATED GNSS TUNNEL OUTAGES ---")
    # Take authentic high-speed motorway sections (>70 km/h) for simulated tunnel outages
    tunnel_configs = [
        ('S-Vtb1.csv', 10000, 60, 'Short Underpass Outage (60s @ 80 km/h)'),
        ('S-Vtb1.csv', 12500, 120, 'Standard Highway Tunnel (120s @ 70 km/h)'),
        ('S-Vtb1.csv', 21500, 300, 'Deep Mountain/Subsea Tunnel (300s / 5 min @ 75 km/h)'),
        ('S-Vw16a.csv', 1500, 120, 'Metropolitan Expressway Tunnel (120s @ 70 km/h)'),
        ('S-Vfa02.csv', 2000, 120, 'Long-Span Bridge/Tunnel Complex (120s @ 90 km/h)'),
        ('S-Vw14b.csv', 3000, 120, 'High-Speed Tunnel Corridor (120s @ 95 km/h)'),
    ]
    for fn, start_step, duration_s, label in tunnel_configs:
        if fn in file_map:
            parsed = load_and_parse_iovnbd_file(file_map[fn])
            if parsed:
                imu, speed = parsed
                end_step = min(len(speed), start_step + int(duration_s * 10))
                if end_step - start_step >= int(duration_s * 10 * 0.8):
                    res = evaluator.evaluate_scenario(imu[start_step:end_step], speed[start_step:end_step], label, "Simulated Tunnel Outage")
                    if res:
                        scenarios_results.append(res)
                        stat = "[PASS]" if res['passed'] else "[FAIL]"
                        print(f"  {stat} {res['name']:<48} | Dist: {res['true_dist_m']:7.1f}m | Drift: {res['pipe_drift_pct']:5.2f}% | MAE: {res['pipe_mae']:.2f} m/s")

    # -------------------------------------------------------------
    # CATEGORY 3: MANEUVER-SPECIFIC STRESS SCENARIOS
    # -------------------------------------------------------------
    print("\n--- CATEGORY 3: MANEUVER-SPECIFIC STRESS SCENARIOS ---")
    
    # 3A. Stop-and-Go Congestion (windows with repeated zero stops and throttle restarts)
    stopgo_files = ['S-Vta1a.csv', 'S-Vta1b.csv', 'S-Vta4.csv', 'S-Vta6.csv', 'S-Vta9.csv', 'S-Vtb5.csv', 'S-Vw14a.csv', 'S-Vw14b.csv']
    for fn in stopgo_files:
        if fn in file_map:
            parsed = load_and_parse_iovnbd_file(file_map[fn])
            if parsed:
                imu, speed = parsed
                end = min(len(speed), 1200)
                res = evaluator.evaluate_scenario(imu[:end], speed[:end], f"{fn} - Stop-and-Go Traffic Window (120s)", "Stop-and-Go Congestion")
                if res:
                    scenarios_results.append(res)
                    stat = "[PASS]" if res['passed'] else "[FAIL]"
                    print(f"  {stat} {res['name']:<48} | Dist: {res['true_dist_m']:7.1f}m | Drift: {res['pipe_drift_pct']:5.2f}% | MAE: {res['pipe_mae']:.2f} m/s")

    # 3B. High-Speed Motorway Cruise
    highway_configs = [
        ('S-Vfa02.csv', 1500, 1200, 'Motorway Cruise 85 km/h'),
        ('S-Vw14b.csv', 2500, 1200, 'Expressway Cruise 95 km/h'),
        ('S-Vw2.csv', 2000, 1200, 'Interstate Cruise 75 km/h'),
        ('S-Vtb6.csv', 0, 480, 'Sprint Cruise 65 km/h'),
    ]
    for fn, start, length, label in highway_configs:
        if fn in file_map:
            parsed = load_and_parse_iovnbd_file(file_map[fn])
            if parsed:
                imu, speed = parsed
                end = min(len(speed), start + length)
                res = evaluator.evaluate_scenario(imu[start:end], speed[start:end], f"{fn} - {label}", "Highway Cruise")
                if res:
                    scenarios_results.append(res)
                    stat = "[PASS]" if res['passed'] else "[FAIL]"
                    print(f"  {stat} {res['name']:<48} | Dist: {res['true_dist_m']:7.1f}m | Drift: {res['pipe_drift_pct']:5.2f}% | MAE: {res['pipe_mae']:.2f} m/s")

    # 3C. Sharp Corners & Roundabouts (high gyro Z energy)
    curve_files = ['S-Vta8.csv', 'S-Vta12.csv', 'S-Vta14.csv', 'S-Vtb9.csv', 'S-Vw10.csv']
    for fn in curve_files:
        if fn in file_map:
            parsed = load_and_parse_iovnbd_file(file_map[fn])
            if parsed:
                imu, speed = parsed
                best_start, best_yaw = 0, 0
                for s in range(0, max(1, len(speed) - 1200), 200):
                    y_var = np.var(imu[s:s+1200, 5])
                    if y_var > best_yaw:
                        best_yaw = y_var
                        best_start = s
                end = best_start + 1200
                res = evaluator.evaluate_scenario(imu[best_start:end], speed[best_start:end], f"{fn} - Curved Road & Roundabouts", "Sharp Corners & Winding Road")
                if res:
                    scenarios_results.append(res)
                    stat = "[PASS]" if res['passed'] else "[FAIL]"
                    print(f"  {stat} {res['name']:<48} | Dist: {res['true_dist_m']:7.1f}m | Drift: {res['pipe_drift_pct']:5.2f}% | MAE: {res['pipe_mae']:.2f} m/s")

    # 3D. Extended Standstill / Red Lights (Verifying 0m drift with ZUPT)
    idle_files = [
        ('S-Vw1.csv', 'Long Engine Idle Calibration (200s)', 2000),
        ('S-Vta20.csv', 'Curb Standstill Holding (180s)', 1800),
        ('S-Vtb1.csv', 'Initial Red Light Wait (60s)', 600),
    ]
    for fn, label, n_samples in idle_files:
        if fn in file_map:
            parsed = load_and_parse_iovnbd_file(file_map[fn])
            if parsed:
                imu, speed = parsed
                end = min(len(speed), n_samples)
                res = evaluator.evaluate_scenario(imu[:end], speed[:end], f"{fn} - {label}", "Extended Standstill")
                if res:
                    scenarios_results.append(res)
                    stat = "[PASS]" if res['passed'] else "[FAIL]"
                    print(f"  {stat} {res['name']:<48} | Dist: {res['true_dist_m']:7.1f}m | Drift: {res['pipe_drift_pct']:5.2f}% | Pipe Err: {res['pipe_err_m']:.2f}m")

    # -------------------------------------------------------------
    # CATEGORY 4: MULTI-VEHICLE TRANSFER
    # -------------------------------------------------------------
    print("\n--- CATEGORY 4: MULTI-VEHICLE CROSS-TRANSFER ---")
    multi_vehicles = [
        ('S-M.csv', 'Motorbike (Driver B)'),
        ('S-S1.csv', 'Scooter Commute 1 (Driver A)'),
        ('S-S2.csv', 'Scooter Commute 2 (Driver A)'),
        ('S-S3a.csv', 'Scooter Trip 3a (Driver A)'),
        ('S-Y1.csv', 'Heavy Commercial Van (Driver D)'),
    ]
    for fn, label in multi_vehicles:
        if fn in file_map:
            parsed = load_and_parse_iovnbd_file(file_map[fn])
            if parsed:
                imu, speed = parsed
                # Limit to first 3000 steps (5 mins) for cross-transfer check
                end = min(len(speed), 3000)
                res = evaluator.evaluate_scenario(imu[:end], speed[:end], f"{fn} - {label}", "Multi-Vehicle Transfer")
                if res:
                    scenarios_results.append(res)
                    stat = "[PASS]" if res['passed'] else "[FAIL]"
                    print(f"  {stat} {res['name']:<48} | Dist: {res['true_dist_m']:7.1f}m | Drift: {res['pipe_drift_pct']:5.2f}% | MAE: {res['pipe_mae']:.2f} m/s")

    # -------------------------------------------------------------
    # SUMMARY SCORECARD
    # -------------------------------------------------------------
    total = len(scenarios_results)
    passed = sum(1 for r in scenarios_results if r['passed'])
    pass_rate = (passed / total) * 100.0 if total > 0 else 0.0
    
    print("\n" + "=" * 80)
    print("       COMPREHENSIVE AUTOMOTIVE SCENARIO SCORECARD")
    print("=" * 80)
    print(f"Total Scenarios Evaluated: {total}")
    print(f"Passed SIH Dead-Reckoning Criteria: {passed} / {total} ({pass_rate:.1f}%)")
    
    by_cat = {}
    for r in scenarios_results:
        cat = r['type']
        if cat not in by_cat:
            by_cat[cat] = []
        by_cat[cat].append(r)
        
    print("\nCategory Performance Breakdown:")
    print("-" * 80)
    print(f"{'Category':<30} | {'Count':<6} | {'Passed':<8} | {'Avg Dist':<12} | {'Avg MAE':<10} | {'Avg Drift':<10}")
    print("-" * 80)
    for cat, items in by_cat.items():
        c_passed = sum(1 for i in items if i['passed'])
        avg_dist = np.mean([i['true_dist_m'] for i in items])
        avg_mae = np.mean([i['pipe_mae'] for i in items])
        avg_drift = np.mean([i['pipe_drift_pct'] for i in items])
        print(f"{cat:<30} | {len(items):<6} | {c_passed}/{len(items):<6} | {avg_dist:9.1f}m   | {avg_mae:6.2f} m/s  | {avg_drift:6.2f}%")
    print("=" * 80)

    # Save results as JSON
    out_json = REPO_ROOT / "model" / "comprehensive_scenario_results.json"
    with open(out_json, "w") as f:
        json.dump(scenarios_results, f, indent=2)
    print(f"\nDetailed scenario report saved to: {out_json}")
    return scenarios_results

if __name__ == '__main__':
    run_all_scenarios()
