#!/usr/bin/env python3
"""
================================================================================
Multi-Dataset Acquisition & Standardization Engine for Vehicle Dead Reckoning
Supported Datasets:
  1. DriverSVT (Smartphone Telemetry in Passenger Cars, 633 Drivers, Zenodo)
  2. IO-VNBD (Inertial and Odometry Smartphone Benchmark Dataset)
Note: TartanIMU (off-road rover) and UAH-DriveSet are excluded to maintain
pure smartphone-in-car physical consistency.
================================================================================
"""

import os
import sys
import csv
import io
import time
import urllib.request
import numpy as np
import pandas as pd
from tqdm import tqdm

if hasattr(sys.stdout, 'reconfigure'):
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace', line_buffering=True)
        sys.stderr.reconfigure(encoding='utf-8', errors='replace', line_buffering=True)
    except Exception:
        pass

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DATASETS_DIR = os.path.join(SCRIPT_DIR, "datasets")
DRIVERSVT_DIR = os.path.join(DATASETS_DIR, "driversvt")

os.makedirs(DRIVERSVT_DIR, exist_ok=True)

DRIVERSVT_URL = "https://zenodo.org/api/records/7385340/files/DriverSVT.csv/content"
TOTAL_FILE_BYTES = 9091056568


def get_driversvt_header():
    """Fetch and parse CSV header from DriverSVT to dynamically map columns."""
    headers = {'Range': 'bytes=0-4095'}
    req = urllib.request.Request(DRIVERSVT_URL, headers=headers)
    with urllib.request.urlopen(req, timeout=30) as resp:
        first_line = resp.read().decode('utf-8', errors='replace').splitlines()[0]
    cols = next(csv.reader([first_line]))
    col_map = {c.strip(): i for i, c in enumerate(cols)}
    return cols, col_map


def download_and_process_driversvt(num_chunks=30, chunk_size_mb=20, min_total_samples=250000):
    """
    Downloads and extracts diverse smartphone driving sequences from DriverSVT across
    the entire 9.1 GB dataset using targeted HTTP Range slices.
    
    Each slice is segmented by (userid, datetimestart), filtered for active driving
    (speed > 15 km/h, duration >= 30s), and resampled to exact 10 Hz (100ms step).
    """
    print("\n" + "=" * 80)
    print("ACQUIRING & STANDARDIZING DRIVERSVT (SMARTPHONE IN PASSENGER CARS)")
    print(f"Target Directory: {DRIVERSVT_DIR}")
    print("=" * 80)

    # Check existing files
    existing_files = [f for f in os.listdir(DRIVERSVT_DIR) if f.startswith("driversvt_") and f.endswith(".csv")]
    existing_samples = 0
    for f in existing_files:
        try:
            with open(os.path.join(DRIVERSVT_DIR, f), 'r') as fp:
                existing_samples += sum(1 for _ in fp) - 1
        except Exception:
            pass

    print(f"[*] Existing DriverSVT trips found: {len(existing_files)} ({existing_samples:,} samples @ 10 Hz)")
    if existing_samples >= min_total_samples:
        print(f"[OK] DriverSVT corpus already exceeds target {min_total_samples:,} samples. Skipping download.")
        return len(existing_files), existing_samples

    cols, col_map = get_driversvt_header()
    time_idx = col_map['datetime']
    start_idx = col_map['datetimestart']
    speed_idx = col_map['speed']
    user_idx = col_map['userid']
    ax_idx = col_map['accelerometer_data_raw_X']
    ay_idx = col_map['accelerometer_data_raw_Y']
    az_idx = col_map['accelerometer_data_raw_Z']
    gx_idx = col_map['gyroscope_data_raw_X']
    gy_idx = col_map['gyroscope_data_raw_Y']
    gz_idx = col_map['gyroscope_data_raw_Z']

    # Targeted active driving regions across verified multi-driver trips:
    # User 28 (highway 0-150 km/h), User 2 (0-158 km/h), User 1349 (0-68 km/h),
    # User 5418 (city 0-32 km/h), User 4882 (suburban 0-25 km/h)
    target_slices = [
        (1_990_000_000, 15, "User 28 - Highway Sprint 1"),
        (2_010_000_000, 15, "User 28 - Highway Sprint 2"),
        (3_490_000_000, 15, "User 2 - Expressway Cruising 1"),
        (3_510_000_000, 15, "User 2 - Expressway Cruising 2"),
        (3_990_000_000, 15, "User 1349 - Arterial / Urban"),
        (4_490_000_000, 15, "User 2 - Return Highway Trip"),
        (6_990_000_000, 15, "User 5418 - City Traffic"),
        (7_490_000_000, 15, "User 4882 - Suburban Routes"),
    ]

    total_new_trips = 0
    total_new_samples = existing_samples

    for chunk_idx, (offset, size_mb, desc) in enumerate(target_slices):
        if total_new_samples >= min_total_samples:
            print(f"\n[+] Reached target dataset size: {total_new_samples:,} samples across {len(os.listdir(DRIVERSVT_DIR))} trips.")
            break

        chunk_bytes = size_mb * 1024 * 1024
        print(f"\n[*] Fetching Slice [{chunk_idx + 1}/{len(target_slices)}]: {desc} ({size_mb} MB @ {offset / (1024**3):.2f} GB)...")
        req = urllib.request.Request(
            DRIVERSVT_URL,
            headers={'Range': f'bytes={offset}-{offset + chunk_bytes}'}
        )

        try:
            t0 = time.time()
            with urllib.request.urlopen(req, timeout=60) as resp:
                raw_data = resp.read().decode('utf-8', errors='replace')
            dl_time = time.time() - t0
            speed_mb = (len(raw_data) / (1024 * 1024)) / max(0.1, dl_time)
            print(f"    Downloaded in {dl_time:.1f}s ({speed_mb:.2f} MB/s)")

            lines = raw_data.splitlines()[1:-1]  # Drop partial edge lines
            trips = {}
            for r in csv.reader(lines):
                if len(r) == len(cols):
                    try:
                        uid = r[user_idx].strip()
                        t_start = r[start_idx].strip()
                        key = (uid, t_start)
                        t = float(r[time_idx])
                        sp_mps = float(r[speed_idx]) / 3.6  # Convert km/h -> m/s
                        ax = float(r[ax_idx])
                        ay = float(r[ay_idx])
                        az = float(r[az_idx])
                        gx = float(r[gx_idx])
                        gy = float(r[gy_idx])
                        gz = float(r[gz_idx])
                        trips.setdefault(key, []).append((t, ax, ay, az, gx, gy, gz, sp_mps))
                    except (ValueError, IndexError):
                        continue

            # Process trips found in this slice
            saved_in_slice = 0
            for (uid, t_start), records in trips.items():
                if len(records) < 150:
                    continue  # Too short

                arr = np.array(records, dtype=np.float64)
                arr = arr[np.argsort(arr[:, 0])]  # Sort chronologically
                _, u_idx = np.unique(arr[:, 0], return_index=True)
                arr = arr[u_idx]

                t = arr[:, 0]
                sp = arr[:, 7]
                dur_s = (t[-1] - t[0]) / 1000.0

                # Quality Filters:
                # 1. Minimum duration: 30 seconds
                # 2. Minimum peak speed: 15 km/h (4.17 m/s)
                # 3. Minimum mean speed: 3 km/h (0.83 m/s)
                # 4. Valid sensor activity (std > 0.05 m/s^2)
                if dur_s < 30.0 or sp.max() < 4.17 or sp.mean() < 0.83:
                    continue
                if arr[:, 1].std() < 0.05 or arr[:, 2].std() < 0.05 or arr[:, 3].std() < 0.05:
                    continue

                # Resample to exact 10 Hz (100 ms intervals)
                target_t = np.arange(t[0], t[-1], 100.0)
                if len(target_t) < 300:
                    continue

                ax_10hz = np.interp(target_t, t, arr[:, 1])
                ay_10hz = np.interp(target_t, t, arr[:, 2])
                az_10hz = np.interp(target_t, t, arr[:, 3])
                gx_10hz = np.interp(target_t, t, arr[:, 4])
                gy_10hz = np.interp(target_t, t, arr[:, 5])
                gz_10hz = np.interp(target_t, t, arr[:, 6])
                sp_10hz = np.interp(target_t, t, arr[:, 7])

                out_filename = f"driversvt_u{uid}_t{t_start}_{int(target_t[0])}.csv"
                out_path = os.path.join(DRIVERSVT_DIR, out_filename)

                df_out = pd.DataFrame({
                    'accel_x': ax_10hz,
                    'accel_y': ay_10hz,
                    'accel_z': az_10hz,
                    'gyr_x': gx_10hz,
                    'gyr_y': gy_10hz,
                    'gyr_z': gz_10hz,
                    'speed_mps': sp_10hz
                })
                df_out.to_csv(out_path, index=False)
                saved_in_slice += 1
                total_new_trips += 1
                total_new_samples += len(df_out)
                print(f"    [+] Saved trip {out_filename}: {len(df_out)} samples @ 10 Hz "
                      f"({dur_s:.1f}s, max: {sp.max() * 3.6:.1f} km/h, mean: {sp.mean() * 3.6:.1f} km/h)")

            if saved_in_slice == 0:
                print("    [-] No moving driving trips found in this slice (driver was stationary/parked).")

        except Exception as e:
            print(f"    [-] Error processing slice @ {offset}: {e}")

    final_files = [f for f in os.listdir(DRIVERSVT_DIR) if f.startswith("driversvt_") and f.endswith(".csv")]
    print("\n" + "=" * 80)
    print("DRIVERSVT ACQUISITION COMPLETE")
    print(f"  Total Standardized Trips   : {len(final_files)}")
    print(f"  Total 10 Hz Driving Samples: {total_new_samples:,}")
    print("=" * 80)
    return len(final_files), total_new_samples


def main():
    download_and_process_driversvt()

    print("\n" + "=" * 80)
    print("DATASET INGESTION SUMMARY")
    print("=" * 80)

    driversvt_files = [f for f in os.listdir(DRIVERSVT_DIR) if f.endswith('.csv')]
    iovnbd_dir = os.path.join(SCRIPT_DIR, "IO-VNBD")
    iovnbd_files = []
    if os.path.exists(iovnbd_dir):
        for root, _, files in os.walk(iovnbd_dir):
            for f in files:
                if f.endswith('.csv') and f.startswith('S-'):
                    iovnbd_files.append(os.path.join(root, f))

    print(f"  1. DriverSVT (Zenodo / Smartphone Car): {len(driversvt_files)} standardized CSV driving trips")
    print(f"  2. IO-VNBD Local (Smartphone Odometry): {len(iovnbd_files)} synchronized vehicle & phone trips")
    print(f"  Total Clean Training Corpus           : {len(driversvt_files) + len(iovnbd_files)} passenger vehicle files")
    print("=" * 80 + "\n")


if __name__ == "__main__":
    main()
