#!/usr/bin/env python3
"""
================================================================================
Post-Training Dataset Acquisition Engine
Downloads fresh, high-velocity naturalistic smartphone driving sequences from
the Zenodo DriverSVT corpus into an isolated, self-contained directory:
`model/datasets/post_training/`

This allows for seamless fine-tuning and easy, one-command cleanup when finished.
================================================================================
"""

import os
import sys
import csv
import time
import urllib.request
import numpy as np
import pandas as pd

if hasattr(sys.stdout, 'reconfigure'):
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace', line_buffering=True)
        sys.stderr.reconfigure(encoding='utf-8', errors='replace', line_buffering=True)
    except Exception:
        pass

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
POST_TRAIN_DIR = os.path.join(SCRIPT_DIR, "datasets", "post_training")
os.makedirs(POST_TRAIN_DIR, exist_ok=True)

DRIVERSVT_URL = "https://zenodo.org/api/records/7385340/files/DriverSVT.csv/content"

# Verified active driving byte offsets across the Zenodo corpus:
POST_TRAIN_SLICES = [
    (2_020_000_000, 15, "Driver Batch Alpha - User 28 High-Speed Motorway (155 km/h)"),
    (3_525_000_000, 15, "Driver Batch Beta - User 2 Expressway Cruising"),
    (4_005_000_000, 15, "Driver Batch Gamma - User 1349 Arterial & City Commute"),
    (4_505_000_000, 15, "Driver Batch Delta - User 2 Return Highway Sprint"),
]


def get_driversvt_header():
    """Fetch and parse CSV header from DriverSVT to map column indices dynamically."""
    headers = {'Range': 'bytes=0-4095'}
    req = urllib.request.Request(DRIVERSVT_URL, headers=headers)
    with urllib.request.urlopen(req, timeout=30) as resp:
        first_line = resp.read().decode('utf-8', errors='replace').splitlines()[0]
    cols = next(csv.reader([first_line]))
    col_map = {c.strip(): i for i, c in enumerate(cols)}
    return cols, col_map


def ingest_uah_driveset():
    """Ingest standardized UAH-DriveSet trips if present in excluded_datasets."""
    import glob, shutil
    uah_dir = os.path.join(SCRIPT_DIR, "excluded_datasets", "uah_driveset")
    if not os.path.exists(uah_dir):
        return 0
    uah_files = sorted(glob.glob(os.path.join(uah_dir, "*.csv")))
    count = 0
    for f in uah_files:
        bn = os.path.basename(f)
        trip_num = bn.split('_')[-1].split('.')[0]
        out_name = f"driversvt_uUAH_t{trip_num}_0.csv"
        dst_path = os.path.join(POST_TRAIN_DIR, out_name)
        if not os.path.exists(dst_path):
            shutil.copyfile(f, dst_path)
            count += 1
    if count > 0:
        print(f"[+] Ingested {count} real-world passenger car trips from UAH-DriveSet.")
    return count


def download_post_training_dataset():
    print("=" * 80)
    print("ACQUIRING POST-TRAINING DATASET INTO ISOLATED DIRECTORY")
    print(f"Target Directory: {POST_TRAIN_DIR}")
    print("=" * 80)

    ingest_uah_driveset()

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

    total_trips = 0
    total_samples = 0

    for idx, (offset, size_mb, desc) in enumerate(POST_TRAIN_SLICES):
        chunk_bytes = size_mb * 1024 * 1024
        print(f"\n[*] Fetching Post-Training Slice [{idx + 1}/{len(POST_TRAIN_SLICES)}]: {desc}...")
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
            print(f"    Downloaded {len(raw_data)/(1024*1024):.1f} MB in {dl_time:.1f}s ({speed_mb:.2f} MB/s)")

            lines = raw_data.splitlines()[1:-1]
            trips = {}
            for r in csv.reader(lines):
                if len(r) == len(cols):
                    try:
                        uid = r[user_idx].strip()
                        t_start = r[start_idx].strip()
                        key = (uid, t_start)
                        t = float(r[time_idx])
                        sp_mps = float(r[speed_idx]) / 3.6  # km/h -> m/s
                        ax = float(r[ax_idx])
                        ay = float(r[ay_idx])
                        az = float(r[az_idx])
                        gx = float(r[gx_idx])
                        gy = float(r[gy_idx])
                        gz = float(r[gz_idx])
                        trips.setdefault(key, []).append((t, ax, ay, az, gx, gy, gz, sp_mps))
                    except (ValueError, IndexError):
                        continue

            saved_in_slice = 0
            for (uid, t_start), records in trips.items():
                if len(records) < 150:
                    continue

                arr = np.array(records, dtype=np.float64)
                arr = arr[np.argsort(arr[:, 0])]
                _, u_idx = np.unique(arr[:, 0], return_index=True)
                arr = arr[u_idx]

                t = arr[:, 0]
                sp = arr[:, 7]
                dur_s = (t[-1] - t[0]) / 1000.0

                # Filter for active moving trips
                if dur_s < 25.0 or sp.max() < 4.0 or sp.mean() < 0.8:
                    continue
                if arr[:, 1].std() < 0.05 or arr[:, 2].std() < 0.05:
                    continue

                # Resample to exact 10 Hz
                target_t = np.arange(t[0], t[-1], 100.0)
                if len(target_t) < 250:
                    continue

                ax_10hz = np.interp(target_t, t, arr[:, 1])
                ay_10hz = np.interp(target_t, t, arr[:, 2])
                az_10hz = np.interp(target_t, t, arr[:, 3])
                gx_10hz = np.interp(target_t, t, arr[:, 4])
                gy_10hz = np.interp(target_t, t, arr[:, 5])
                gz_10hz = np.interp(target_t, t, arr[:, 6])
                sp_10hz = np.interp(target_t, t, arr[:, 7])

                out_filename = f"driversvt_u{uid}_t{t_start}_{int(target_t[0])}.csv"
                out_path = os.path.join(POST_TRAIN_DIR, out_filename)

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
                total_trips += 1
                total_samples += len(df_out)
                print(f"    [+] Saved trip {out_filename}: {len(df_out)} samples @ 10 Hz "
                      f"({dur_s:.1f}s, max: {sp.max() * 3.6:.1f} km/h, mean: {sp.mean() * 3.6:.1f} km/h)")

            if saved_in_slice == 0:
                print("    [-] No moving trips in this slice (stationary vehicle records).")

        except Exception as e:
            print(f"    [-] Error downloading slice @ {offset}: {e}")

    print("\n" + "=" * 80)
    print("POST-TRAINING DATASET ACQUISITION COMPLETE")
    print(f"  Isolated Directory: {POST_TRAIN_DIR}")
    print(f"  Total Trips Saved : {total_trips}")
    print(f"  Total 10 Hz Samples: {total_samples:,}")
    print("=" * 80)


if __name__ == '__main__':
    download_post_training_dataset()
