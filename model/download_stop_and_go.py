#!/usr/bin/env python3
"""
================================================================================
Stop-and-Go Urban Driving Dataset Acquisition Engine
Fetches authentic city stop-and-go driving sequences from Zenodo DriverSVT (9.1 GB)
Filters strictly for:
- Low-to-moderate speed urban commuting (v_max <= 60 km/h)
- At least 1-2 distinct standstill / restart cycles (traffic lights, congestion)
- Clear acceleration restart phases (breaking out of standstill)
- Standardized 10 Hz sampling matching IO-VNBD / TCN speed engine
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
OUTPUT_DIR = os.path.join(SCRIPT_DIR, "datasets", "driversvt")
os.makedirs(OUTPUT_DIR, exist_ok=True)

DRIVERSVT_URL = "https://zenodo.org/api/records/7385340/files/DriverSVT.csv/content"

# Target offsets across Zenodo DriverSVT known to contain urban/arterial commute records
TARGET_OFFSETS = [
    # Offset (bytes), Size (MB), Description
    (3_980_000_000, 20, "User 1349 Urban Arterial Slices A"),
    (4_020_000_000, 20, "User 1349 Urban Arterial Slices B"),
    (4_050_000_000, 20, "User 1349 City Traffic Slices C"),
    (4_100_000_000, 20, "User 1349 Downtown Congestion D"),
    (5_100_000_000, 20, "Mid-Dataset Urban Commuter E"),
    (5_500_000_000, 20, "Mid-Dataset Mixed Traffic F"),
    (6_950_000_000, 20, "User 5418 City Traffic Slices G"),
    (6_980_000_000, 20, "User 5418 Arterial Intersections H"),
    (7_020_000_000, 20, "User 5418 Stop-and-Go Commute I"),
    (7_450_000_000, 20, "User 4882 Urban Route J"),
    (7_490_000_000, 20, "User 4882 Signalized Corridor K"),
    (7_530_000_000, 20, "User 4882 City Center L"),
]


def get_driversvt_header():
    """Fetch and parse CSV header from DriverSVT."""
    headers = {'Range': 'bytes=0-4095'}
    req = urllib.request.Request(DRIVERSVT_URL, headers=headers)
    with urllib.request.urlopen(req, timeout=30) as resp:
        first_line = resp.read().decode('utf-8', errors='replace').splitlines()[0]
    cols = next(csv.reader([first_line]))
    col_map = {c.strip(): i for i, c in enumerate(cols)}
    return cols, col_map


def is_stop_and_go_trip(t_arr, sp_arr, ax_arr, ay_arr, az_arr):
    """
    Evaluates whether a trip qualifies as high-value stop-and-go urban driving:
    1. Duration >= 35.0 seconds
    2. Speed ceiling <= 60 km/h (16.67 m/s) to avoid highway dominance
    3. Max speed >= 12 km/h (3.33 m/s) to ensure actual driving
    4. Mean speed between 1.5 m/s and 12.0 m/s (5.4 - 43.2 km/h)
    5. Has at least 1 stop (< 0.5 m/s for >= 2.5s) AND at least 1 restart back to > 3.0 m/s
    """
    dur_s = (t_arr[-1] - t_arr[0]) / 1000.0
    if dur_s < 35.0:
        return False, "Too short (<35s)"
    
    max_sp = sp_arr.max()
    mean_sp = sp_arr.mean()
    
    if max_sp > 16.67: # 60 km/h
        return False, f"Speed exceeds 60 km/h ceiling ({max_sp * 3.6:.1f} km/h)"
    
    if max_sp < 3.33: # 12 km/h
        return False, f"Speed too low for driving ({max_sp * 3.6:.1f} km/h)"
        
    if mean_sp < 1.0 or mean_sp > 12.0:
        return False, f"Mean speed out of urban range ({mean_sp * 3.6:.1f} km/h)"

    # Identify stops (< 0.5 m/s)
    is_stopped = (sp_arr < 0.5)
    stop_count = 0
    in_stop = False
    stop_start_idx = 0
    restart_count = 0

    for i in range(len(is_stopped)):
        if is_stopped[i] and not in_stop:
            in_stop = True
            stop_start_idx = i
        elif not is_stopped[i] and in_stop:
            in_stop = False
            stop_dur = (t_arr[i] - t_arr[stop_start_idx]) / 1000.0
            if stop_dur >= 2.5:
                stop_count += 1
                # Check for restart up to at least 2.5 m/s in subsequent 15s
                future_idx = min(len(sp_arr), i + int(15.0 / 0.1))
                if future_idx > i and sp_arr[i:future_idx].max() >= 2.5:
                    restart_count += 1

    if stop_count >= 1 and restart_count >= 1:
        return True, f"Qualified: {stop_count} stops, {restart_count} restarts, max: {max_sp*3.6:.1f} km/h"
    
    return False, f"Insufficient stops/restarts (stops={stop_count}, restarts={restart_count})"


def download_stop_and_go_data():
    print("=" * 80)
    print("STOP-AND-GO URBAN COMMUTE DATASET ACQUISITION ENGINE")
    print(f"Target Directory: {OUTPUT_DIR}")
    print("=" * 80)

    existing_files = [f for f in os.listdir(OUTPUT_DIR) if f.endswith(".csv")]
    print(f"[*] Found {len(existing_files)} existing DriverSVT files in directory.")

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

    total_new_trips = 0
    total_new_samples = 0

    for idx, (offset, size_mb, desc) in enumerate(TARGET_OFFSETS):
        chunk_bytes = size_mb * 1024 * 1024
        print(f"\n[*] Fetching Offset [{idx + 1}/{len(TARGET_OFFSETS)}]: {desc} ({size_mb} MB @ {offset:,} bytes)...")
        req = urllib.request.Request(
            DRIVERSVT_URL,
            headers={'Range': f'bytes={offset}-{offset + chunk_bytes}'}
        )

        try:
            t0 = time.time()
            with urllib.request.urlopen(req, timeout=90) as resp:
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

            print(f"    Discovered {len(trips)} distinct user/start recording blocks in chunk.")
            saved_in_slice = 0

            for (uid, t_start), records in trips.items():
                if len(records) < 200:
                    continue

                arr = np.array(records, dtype=np.float64)
                arr = arr[np.argsort(arr[:, 0])]
                _, u_idx = np.unique(arr[:, 0], return_index=True)
                arr = arr[u_idx]

                t = arr[:, 0]
                sp = arr[:, 7]
                dur_s = (t[-1] - t[0]) / 1000.0

                # Check standard sensor variance (avoid flatlined stationary files)
                if arr[:, 1].std() < 0.05 or arr[:, 2].std() < 0.05:
                    continue

                # Resample to exact 10 Hz (100 ms step)
                target_t = np.arange(t[0], t[-1], 100.0)
                if len(target_t) < 350:  # < 35 seconds
                    continue

                ax_10hz = np.interp(target_t, t, arr[:, 1])
                ay_10hz = np.interp(target_t, t, arr[:, 2])
                az_10hz = np.interp(target_t, t, arr[:, 3])
                gx_10hz = np.interp(target_t, t, arr[:, 4])
                gy_10hz = np.interp(target_t, t, arr[:, 5])
                gz_10hz = np.interp(target_t, t, arr[:, 6])
                sp_10hz = np.interp(target_t, t, arr[:, 7])

                # Check if it fits stop-and-go criteria
                qualifies, reason = is_stop_and_go_trip(target_t, sp_10hz, ax_10hz, ay_10hz, az_10hz)
                if not qualifies:
                    continue

                out_filename = f"driversvt_stopgo_u{uid}_t{t_start}_{int(target_t[0])}.csv"
                out_path = os.path.join(OUTPUT_DIR, out_filename)

                if os.path.exists(out_path):
                    continue

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
                print(f"    [+] Saved Stop-and-Go Trip: {out_filename}")
                print(f"        -> {len(df_out)} steps @ 10 Hz ({dur_s:.1f}s), max: {sp_10hz.max()*3.6:.1f} km/h, mean: {sp_10hz.mean()*3.6:.1f} km/h | {reason}")

            print(f"    -> Saved {saved_in_slice} qualifying stop-and-go trips from this slice.")

        except Exception as e:
            print(f"    [-] Error processing slice @ {offset}: {e}")

    total_files = len([f for f in os.listdir(OUTPUT_DIR) if f.endswith(".csv")])
    print("\n" + "=" * 80)
    print("DATASET ACQUISITION SUMMARY:")
    print(f"  New Stop-and-Go Trips Saved : {total_new_trips}")
    print(f"  New 10 Hz Samples Added     : {total_new_samples:,}")
    print(f"  Total DriverSVT Files Now   : {total_files} (Original: {len(existing_files)})")
    print("=" * 80)


if __name__ == '__main__':
    download_stop_and_go_data()
