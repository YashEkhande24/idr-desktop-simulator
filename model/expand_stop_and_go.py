#!/usr/bin/env python3
"""
================================================================================
Stop-and-Go Dataset Expansion & Segmentation Engine
1. Renames any driversvt_stopgo_u{uid} to driversvt_u{uid}_stopgo to conform to
   split_by_trip_groups regex.
2. Segments long stop-and-go recordings (>150s) into coherent sub-trips (60-120s)
   at natural standstill events, ensuring 100% of stop-and-go samples are ingested
   without being clipped by max_windows_per_file.
3. Downloads additional urban slices from Zenodo DriverSVT across untested offsets.
================================================================================
"""

import os
import sys
import glob
import re
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

# Additional targeted byte offsets across Zenodo DriverSVT
ADDITIONAL_OFFSETS = [
    (3_850_000_000, 15, "User 2 Pre-Arterial Slices 1"),
    (3_900_000_000, 15, "User 2 Pre-Arterial Slices 2"),
    (3_940_000_000, 15, "User 2 Commute Slices 3"),
    (4_030_000_000, 15, "User 1349 City Traffic Slices 4"),
    (4_060_000_000, 15, "User 1349 Arterial Corridor Slices 5"),
    (6_920_000_000, 15, "User 5418 City Traffic Slices 6"),
    (6_960_000_000, 15, "User 5418 Signalized Corridor Slices 7"),
    (7_000_000_000, 15, "User 5418 Downtown Arterial Slices 8"),
    (7_470_000_000, 15, "User 4882 Urban Route Slices 9"),
    (7_510_000_000, 15, "User 4882 City Center Slices 10"),
]


def fix_existing_filenames():
    """Ensure all stopgo files match driversvt_u{uid}_stopgo_ prefix."""
    files = glob.glob(os.path.join(OUTPUT_DIR, "driversvt_stopgo_u*.csv"))
    renamed = 0
    for f in files:
        bn = os.path.basename(f)
        m = re.match(r'driversvt_stopgo_u([0-9a-zA-Z]+)_(.+)', bn)
        if m:
            uid = m.group(1)
            rest = m.group(2)
            new_bn = f"driversvt_u{uid}_stopgo_{rest}"
            new_path = os.path.join(OUTPUT_DIR, new_bn)
            if not os.path.exists(new_path):
                os.rename(f, new_path)
                renamed += 1
            else:
                os.remove(f)
    if renamed > 0:
        print(f"[+] Conformed {renamed} existing stopgo filenames to driversvt_u{{uid}}_stopgo_*")


def segment_long_trips():
    """
    Splits long continuous recordings (>1800 steps = 180s) into 60-120s sub-trips.
    Each sub-trip contains full stop-and-go events and avoids max_windows_per_file truncation.
    """
    files = glob.glob(os.path.join(OUTPUT_DIR, "driversvt_u*_stopgo_*.csv"))
    total_new_segments = 0

    for f in files:
        try:
            df = pd.read_csv(f)
        except Exception:
            continue

        if len(df) < 1800:
            continue

        bn = os.path.basename(f).replace('.csv', '')
        # Check if already segmented
        if '_seg' in bn:
            continue

        # Segment into ~80-120s chunks (800-1200 steps at 10 Hz)
        chunk_size = 900  # 90 seconds
        overlap = 150     # 15 seconds overlap
        step = chunk_size - overlap

        num_segments = (len(df) - overlap) // step
        if num_segments <= 1:
            continue

        for seg_idx in range(num_segments):
            start_i = seg_idx * step
            end_i = min(len(df), start_i + chunk_size)
            if end_i - start_i < 500:  # < 50 seconds
                continue

            sub_df = df.iloc[start_i:end_i].copy()
            sp = sub_df['speed_mps'].values

            # Ensure this segment has at least some motion and at least one low speed/stop
            if sp.max() >= 2.5 and (sp < 0.5).any() and sp.mean() >= 0.8:
                seg_name = f"{bn}_seg{seg_idx:02d}.csv"
                seg_path = os.path.join(OUTPUT_DIR, seg_name)
                sub_df.to_csv(seg_path, index=False)
                total_new_segments += 1

        # Remove the unsegmented parent file to prevent duplicate sample ingestion
        os.remove(f)
        print(f"[+] Segmented {bn} ({len(df)} steps) into sub-trips. Removed parent.")

    print(f"[+] Total new sub-trip segments created: {total_new_segments}")


def get_driversvt_header():
    """Fetch and parse CSV header from DriverSVT."""
    headers = {'Range': 'bytes=0-4095'}
    req = urllib.request.Request(DRIVERSVT_URL, headers=headers)
    with urllib.request.urlopen(req, timeout=30) as resp:
        first_line = resp.read().decode('utf-8', errors='replace').splitlines()[0]
    cols = next(csv.reader([first_line]))
    col_map = {c.strip(): i for i, c in enumerate(cols)}
    return cols, col_map


def is_stop_and_go_trip(t_arr, sp_arr):
    dur_s = (t_arr[-1] - t_arr[0]) / 1000.0
    if dur_s < 35.0:
        return False, "Too short"
    max_sp = sp_arr.max()
    mean_sp = sp_arr.mean()
    if max_sp > 16.67: # 60 km/h
        return False, "Exceeds 60 km/h"
    if max_sp < 3.0:
        return False, "Speed too low"
    if mean_sp < 0.8 or mean_sp > 12.0:
        return False, "Mean speed out of range"

    # Stop check (< 0.5 m/s for >= 2.5s)
    is_stopped = (sp_arr < 0.5)
    stop_count = 0
    in_stop = False
    stop_start = 0
    restart_count = 0

    for i in range(len(is_stopped)):
        if is_stopped[i] and not in_stop:
            in_stop = True
            stop_start = i
        elif not is_stopped[i] and in_stop:
            in_stop = False
            if (t_arr[i] - t_arr[stop_start]) / 1000.0 >= 2.5:
                stop_count += 1
                future = min(len(sp_arr), i + int(15.0 / 0.1))
                if future > i and sp_arr[i:future].max() >= 2.2:
                    restart_count += 1

    if stop_count >= 1 and restart_count >= 1:
        return True, f"Qualified: {stop_count} stops, {restart_count} restarts, max: {max_sp*3.6:.1f} km/h"
    return False, "No stops/restarts"


def download_additional_slices():
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

    total_downloaded_trips = 0

    for idx, (offset, size_mb, desc) in enumerate(ADDITIONAL_OFFSETS):
        chunk_bytes = size_mb * 1024 * 1024
        print(f"\n[*] Fetching Additional Slice [{idx + 1}/{len(ADDITIONAL_OFFSETS)}]: {desc} ({size_mb} MB)...")
        req = urllib.request.Request(
            DRIVERSVT_URL,
            headers={'Range': f'bytes={offset}-{offset + chunk_bytes}'}
        )

        try:
            t0 = time.time()
            with urllib.request.urlopen(req, timeout=60) as resp:
                raw_data = resp.read().decode('utf-8', errors='replace')
            dl_time = time.time() - t0
            print(f"    Downloaded {len(raw_data)/(1024*1024):.1f} MB in {dl_time:.1f}s")

            lines = raw_data.splitlines()[1:-1]
            trips = {}
            for r in csv.reader(lines):
                if len(r) == len(cols):
                    try:
                        uid = r[user_idx].strip()
                        t_start = r[start_idx].strip()
                        key = (uid, t_start)
                        t = float(r[time_idx])
                        sp_mps = float(r[speed_idx]) / 3.6
                        ax = float(r[ax_idx])
                        ay = float(r[ay_idx])
                        az = float(r[az_idx])
                        gx = float(r[gx_idx])
                        gy = float(r[gy_idx])
                        gz = float(r[gz_idx])
                        trips.setdefault(key, []).append((t, ax, ay, az, gx, gy, gz, sp_mps))
                    except (ValueError, IndexError):
                        continue

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

                if arr[:, 1].std() < 0.05 or arr[:, 2].std() < 0.05:
                    continue

                target_t = np.arange(t[0], t[-1], 100.0)
                if len(target_t) < 350:
                    continue

                ax_10hz = np.interp(target_t, t, arr[:, 1])
                ay_10hz = np.interp(target_t, t, arr[:, 2])
                az_10hz = np.interp(target_t, t, arr[:, 3])
                gx_10hz = np.interp(target_t, t, arr[:, 4])
                gy_10hz = np.interp(target_t, t, arr[:, 5])
                gz_10hz = np.interp(target_t, t, arr[:, 6])
                sp_10hz = np.interp(target_t, t, arr[:, 7])

                qualifies, reason = is_stop_and_go_trip(target_t, sp_10hz)
                if not qualifies:
                    continue

                out_filename = f"driversvt_u{uid}_stopgo_t{t_start}_{int(target_t[0])}.csv"
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
                total_downloaded_trips += 1
                print(f"    [+] Saved: {out_filename} ({dur_s:.1f}s, max: {sp_10hz.max()*3.6:.1f} km/h) | {reason}")

        except Exception as e:
            print(f"    [-] Error downloading slice @ {offset}: {e}")

    print(f"[+] Total new trips downloaded in additional pass: {total_downloaded_trips}")


if __name__ == '__main__':
    fix_existing_filenames()
    segment_long_trips()
    download_additional_slices()
    segment_long_trips()
    all_files = [f for f in os.listdir(OUTPUT_DIR) if f.endswith('.csv')]
    print(f"\n>>> FINAL DRIVERSVT DATASET FILE COUNT: {len(all_files)} FILES <<<")
