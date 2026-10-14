#!/usr/bin/env python3
"""
Extracts and validates curated real-world driving test scenarios
for the SIH model submission package.
"""

import os
import sys
import glob
import pandas as pd
import numpy as np
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from model.train import load_and_parse_iovnbd_file

def find_file(filename):
    matches = glob.glob(str(REPO_ROOT / 'model' / '**' / filename), recursive=True)
    if not matches:
        raise FileNotFoundError(f"Could not find {filename}")
    return matches[0]

def extract_slice(src_file, start_idx, duration_s, output_file, sample_hz=10):
    num_rows = int(duration_s * sample_hz)
    df = None
    for enc in ['latin1', 'cp1252', 'utf-8']:
        try:
            df = pd.read_csv(src_file, encoding=enc, on_bad_lines='skip', low_memory=False)
            break
        except Exception:
            continue
    if df is None:
        raise ValueError(f"Failed to read {src_file}")

    total_len = len(df)
    end_idx = min(total_len, start_idx + num_rows)
    sub_df = df.iloc[start_idx:end_idx].copy()
    
    # Save clean UTF-8 CSV
    os.makedirs(os.path.dirname(output_file), exist_ok=True)
    sub_df.to_csv(output_file, index=False, encoding='utf-8')
    print(f"[+] Saved {output_file} ({len(sub_df)} rows, ~{os.path.getsize(output_file)/1024:.1f} KB)")
    return output_file

def main():
    target_dir = REPO_ROOT / "idr_model_submission" / "sample_data"
    os.makedirs(target_dir, exist_ok=True)

    configs = [
        {
            "name": "scenario_1_highway_tunnel_outage.csv",
            "src": "S-Vw16a.csv",
            "start": 1500,
            "duration": 120, # 120s tunnel outage
            "description": "Simulated 120s GNSS Tunnel Blackout @ 70 km/h (Expressway)"
        },
        {
            "name": "scenario_2_urban_stop_and_go.csv",
            "src": "S-Vta1a.csv",
            "start": 0,
            "duration": 120, # 120s stop-and-go
            "description": "Dense Urban Stop-and-Go Traffic with Red Light Standstill (120s)"
        },
        {
            "name": "scenario_3_interstate_highway_cruise.csv",
            "src": "S-Vw2.csv",
            "start": 200,
            "duration": 120, # 120s sustained highway
            "description": "Interstate Highway High-Speed Sustained Cruise 75 km/h (120s)"
        },
        {
            "name": "scenario_4_winding_road_and_turns.csv",
            "src": "S-Vta8.csv",
            "start": 100,
            "duration": 120, # 120s curved trajectory
            "description": "Suburban Curved Arterial Route with Multi-Turn Roundabouts (120s)"
        },
        {
            "name": "scenario_5_two_wheeler_urban_commute.csv",
            "src": "S-M.csv",
            "start": 0,
            "duration": 120, # 120s motorbike commute
            "description": "Two-Wheeler Motorbike Urban Transfer Scenario (120s)"
        }
    ]

    for cfg in configs:
        src_path = find_file(cfg["src"])
        out_path = target_dir / cfg["name"]
        extract_slice(src_path, cfg["start"], cfg["duration"], out_path)

        # Validate that load_and_parse_iovnbd_file can parse it without issues
        parsed = load_and_parse_iovnbd_file(str(out_path))
        if parsed is None:
            print(f"[-] WARNING: Failed to parse {out_path} with standard parser!")
        else:
            imu, speed = parsed
            print(f"    Validation OK: {imu.shape[0]} IMU steps, Speed mean={np.mean(speed)*3.6:.1f} km/h, max={np.max(speed)*3.6:.1f} km/h")

if __name__ == "__main__":
    main()
