#!/usr/bin/env python3
"""
================================================================================
UAH-DriveSet Acquisition & Conversion Engine for IDR TCN Speed Training
================================================================================

UAH-DriveSet: 500+ minutes of naturalistic driving from 6 drivers/vehicles,
recorded with the DriveSafe app on smartphones. Contains:
  - RAW_ACCELEROMETERS.txt: timestamp, activation, ax, ay, az (in Gs!),
    ax_kf, ay_kf, az_kf, roll_deg, pitch_deg, yaw_deg
  - RAW_GPS.txt: timestamp, speed_kmh, lat, lon, alt, v_acc, h_acc, course_deg, ...

This script:
  1. Downloads the dataset from the UAH-DriveSet website (or processes local ZIP)
  2. Parses RAW_ACCELEROMETERS.txt and RAW_GPS.txt for each trip folder
  3. Converts accelerations from Gs to m/s² (× 9.80665)
  4. Synthesizes gyroscope angular rates from attitude derivative:
     omega = d(roll,pitch,yaw)/dt (finite difference of DriveSafe Euler angles)
  5. Resamples all channels to exact 10 Hz
  6. Merges with GPS speed ground truth (km/h → m/s)
  7. Exports standardized CSV: [accel_x, accel_y, accel_z, gyr_x, gyr_y, gyr_z, speed_mps]

Output format matches IO-VNBD / TCN training pipeline exactly.
================================================================================
"""

import os
import sys
import glob
import zipfile
import shutil
import numpy as np
import warnings

warnings.filterwarnings("ignore")

if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace", line_buffering=True)
        sys.stderr.reconfigure(encoding="utf-8", errors="replace", line_buffering=True)
    except Exception:
        pass

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR = os.path.join(SCRIPT_DIR, "datasets", "uah_driveset")
RAW_DIR = os.path.join(SCRIPT_DIR, "datasets", "uah_driveset_raw")

os.makedirs(OUTPUT_DIR, exist_ok=True)
os.makedirs(RAW_DIR, exist_ok=True)

# Physical constant
G_MPS2 = 9.80665

# UAH-DriveSet directory structure after extraction:
# D1/  D2/ ... D6/   (6 drivers)
#   ├── <timestamp_folder>/
#   │   ├── RAW_ACCELEROMETERS.txt
#   │   ├── RAW_GPS.txt
#   │   ├── PROC_LANE_DETECTION.txt
#   │   ├── PROC_VEHICLE_DETECTION.txt
#   │   └── PROC_OPENSTREETMAP_DATA.txt
#   └── <timestamp>.mp4

# Known trip structure: 6 drivers × 2 roads × 3 behaviors = 36 trips
# Each trip ~14-25 minutes of continuous driving


def find_uah_zip():
    """Search for UAH-DriveSet ZIP in common locations."""
    search_paths = [
        os.path.join(SCRIPT_DIR, "uah-driveset.zip"),
        os.path.join(SCRIPT_DIR, "UAH-DriveSet.zip"),
        os.path.join(SCRIPT_DIR, "datasets", "uah-driveset.zip"),
        os.path.join(SCRIPT_DIR, "datasets", "UAH-DriveSet.zip"),
        os.path.expanduser("~/Downloads/uah-driveset.zip"),
        os.path.expanduser("~/Downloads/UAH-DriveSet.zip"),
    ]
    for p in search_paths:
        if os.path.isfile(p):
            return p
    return None


def extract_zip(zip_path):
    """Extract UAH-DriveSet ZIP to raw directory."""
    print(f"[*] Extracting {zip_path} to {RAW_DIR}...")
    with zipfile.ZipFile(zip_path, "r") as zf:
        zf.extractall(RAW_DIR)
    print(f"[OK] Extracted successfully.")


def find_trip_folders(root_dir):
    """
    Recursively find all trip data folders containing RAW_ACCELEROMETERS.txt.
    Returns list of (driver_id, trip_folder_path) tuples.
    """
    trips = []
    for dirpath, dirnames, filenames in os.walk(root_dir):
        if "RAW_ACCELEROMETERS.txt" in filenames and "RAW_GPS.txt" in filenames:
            # Determine driver from parent directory name
            parent = os.path.basename(os.path.dirname(dirpath))
            folder = os.path.basename(dirpath)
            driver_id = parent if parent.startswith("D") else "DX"
            trips.append((driver_id, dirpath, folder))
    return sorted(trips)


def load_space_delimited(filepath, min_cols=3):
    """Load a space-delimited text file with robust error handling."""
    rows = []
    try:
        with open(filepath, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                parts = line.split()
                if len(parts) >= min_cols:
                    try:
                        vals = [float(x) for x in parts]
                        rows.append(vals)
                    except ValueError:
                        continue
    except Exception as e:
        print(f"    [-] Error reading {filepath}: {e}")
        return None

    if len(rows) < 50:
        return None
    return np.array(rows, dtype=np.float64)


def process_trip(driver_id, trip_dir, folder_name):
    """
    Process a single UAH-DriveSet trip folder into standardized 10 Hz CSV.
    
    RAW_ACCELEROMETERS.txt columns:
        0: timestamp (seconds since start of recording)
        1: activation bool (1 if speed > 50 km/h)
        2: X acceleration (Gs)  — lateral (positive = right)
        3: Y acceleration (Gs)  — longitudinal (positive = forward)
        4: Z acceleration (Gs)  — vertical (positive = up, ~1G at rest)
        5: X accel filtered by Kalman (Gs)
        6: Y accel filtered by Kalman (Gs)
        7: Z accel filtered by Kalman (Gs)
        8: Roll (degrees)
        9: Pitch (degrees)
       10: Yaw (degrees)
    
    RAW_GPS.txt columns:
        0: timestamp (seconds since start of recording)
        1: Speed (km/h)
        2: Latitude
        3: Longitude
        4: Altitude
        5: Vertical accuracy
        6: Horizontal accuracy
        7: Course (degrees)
    """
    accel_path = os.path.join(trip_dir, "RAW_ACCELEROMETERS.txt")
    gps_path = os.path.join(trip_dir, "RAW_GPS.txt")

    # Load accelerometer data (need at least 11 columns)
    accel_data = load_space_delimited(accel_path, min_cols=11)
    if accel_data is None:
        return None

    # Load GPS data (need at least 8 columns)
    gps_data = load_space_delimited(gps_path, min_cols=2)
    if gps_data is None:
        return None

    # Extract timestamps
    t_accel = accel_data[:, 0]
    t_gps = gps_data[:, 0]

    # Ensure monotonic timestamps
    if np.any(np.diff(t_accel) < -0.5):
        # Non-monotonic timestamps, try to fix
        mask = np.concatenate([[True], np.diff(t_accel) > -0.01])
        accel_data = accel_data[mask]
        t_accel = accel_data[:, 0]

    if np.any(np.diff(t_gps) < -0.5):
        mask = np.concatenate([[True], np.diff(t_gps) > -0.01])
        gps_data = gps_data[mask]
        t_gps = gps_data[:, 0]

    # Duration check
    duration_s = t_accel[-1] - t_accel[0]
    if duration_s < 30.0:
        return None

    # Deduplicate timestamps
    _, u_idx = np.unique(t_accel, return_index=True)
    accel_data = accel_data[u_idx]
    t_accel = accel_data[:, 0]

    _, u_idx = np.unique(t_gps, return_index=True)
    gps_data = gps_data[u_idx]
    t_gps = gps_data[:, 0]

    # =====================================================================
    # 1. Convert accelerations from Gs to m/s²
    # =====================================================================
    # Raw accelerometer in Gs (columns 2, 3, 4)
    ax_gs = accel_data[:, 2]  # X (lateral)
    ay_gs = accel_data[:, 3]  # Y (longitudinal / forward)
    az_gs = accel_data[:, 4]  # Z (vertical / up)

    ax_mps2 = ax_gs * G_MPS2
    ay_mps2 = ay_gs * G_MPS2
    az_mps2 = az_gs * G_MPS2

    # =====================================================================
    # 2. Synthesize gyroscope angular rates from attitude derivatives
    #    omega ≈ d(euler)/dt using finite differences
    # =====================================================================
    if accel_data.shape[1] >= 11:
        roll_deg = accel_data[:, 8]
        pitch_deg = accel_data[:, 9]
        yaw_deg = accel_data[:, 10]

        roll_rad = np.deg2rad(roll_deg)
        pitch_rad = np.deg2rad(pitch_deg)
        yaw_rad = np.deg2rad(yaw_deg)

        # Handle yaw wrapping (jumps at ±180°)
        yaw_rad = np.unwrap(yaw_rad)
        roll_rad = np.unwrap(roll_rad)

        dt_accel = np.diff(t_accel)
        dt_accel = np.clip(dt_accel, 0.005, 0.5)  # Guard against zero/huge dt

        # Central difference for interior points, forward/backward for edges
        gx = np.zeros_like(roll_rad)
        gy = np.zeros_like(pitch_rad)
        gz = np.zeros_like(yaw_rad)

        # Interior: central difference
        gx[1:-1] = (roll_rad[2:] - roll_rad[:-2]) / (t_accel[2:] - t_accel[:-2])
        gy[1:-1] = (pitch_rad[2:] - pitch_rad[:-2]) / (t_accel[2:] - t_accel[:-2])
        gz[1:-1] = (yaw_rad[2:] - yaw_rad[:-2]) / (t_accel[2:] - t_accel[:-2])

        # Edges: forward/backward difference
        gx[0] = (roll_rad[1] - roll_rad[0]) / dt_accel[0]
        gy[0] = (pitch_rad[1] - pitch_rad[0]) / dt_accel[0]
        gz[0] = (yaw_rad[1] - yaw_rad[0]) / dt_accel[0]
        gx[-1] = (roll_rad[-1] - roll_rad[-2]) / dt_accel[-1]
        gy[-1] = (pitch_rad[-1] - pitch_rad[-2]) / dt_accel[-1]
        gz[-1] = (yaw_rad[-1] - yaw_rad[-2]) / dt_accel[-1]

        # Clamp extreme derivatives (sensor glitches)
        gx = np.clip(gx, -10.0, 10.0)
        gy = np.clip(gy, -10.0, 10.0)
        gz = np.clip(gz, -10.0, 10.0)
    else:
        # No attitude data available, fill with zeros
        gx = np.zeros(len(t_accel))
        gy = np.zeros(len(t_accel))
        gz = np.zeros(len(t_accel))

    # =====================================================================
    # 3. Interpolate GPS speed onto accelerometer timeline
    # =====================================================================
    speed_kmh = gps_data[:, 1]
    speed_mps_gps = speed_kmh / 3.6

    # Clip unrealistic speeds
    speed_mps_gps = np.clip(speed_mps_gps, 0.0, 70.0)  # Max ~250 km/h

    # Interpolate GPS speed to accel timestamps
    speed_at_accel = np.interp(t_accel, t_gps, speed_mps_gps)

    # =====================================================================
    # 4. Resample everything to exact 10 Hz (100 ms intervals)
    # =====================================================================
    t_start = t_accel[0]
    t_end = t_accel[-1]
    t_10hz = np.arange(t_start, t_end, 0.1)  # 100 ms step

    if len(t_10hz) < 300:  # Less than 30 seconds @ 10 Hz
        return None

    ax_10hz = np.interp(t_10hz, t_accel, ax_mps2)
    ay_10hz = np.interp(t_10hz, t_accel, ay_mps2)
    az_10hz = np.interp(t_10hz, t_accel, az_mps2)
    gx_10hz = np.interp(t_10hz, t_accel, gx)
    gy_10hz = np.interp(t_10hz, t_accel, gy)
    gz_10hz = np.interp(t_10hz, t_accel, gz)
    sp_10hz = np.interp(t_10hz, t_accel, speed_at_accel)

    # =====================================================================
    # 5. Quality filters
    # =====================================================================
    # Minimum peak speed: 3 km/h (0.83 m/s) — must be actually driving
    if sp_10hz.max() < 0.83:
        return None

    # Minimum mean speed: 0.5 m/s — not entirely stationary
    if sp_10hz.mean() < 0.5:
        return None

    # Sensor activity check (accel std must be > 0.1 m/s² to indicate real data)
    if ax_10hz.std() < 0.1 and ay_10hz.std() < 0.1:
        return None

    # =====================================================================
    # 6. Export standardized CSV
    # =====================================================================
    out_filename = f"uah_{driver_id}_{folder_name}.csv"
    out_path = os.path.join(OUTPUT_DIR, out_filename)

    # Build output array
    output = np.column_stack([ax_10hz, ay_10hz, az_10hz, gx_10hz, gy_10hz, gz_10hz, sp_10hz])

    # Write CSV with header matching IO-VNBD / DriverSVT format
    header = "accel_x,accel_y,accel_z,gyr_x,gyr_y,gyr_z,speed_mps"
    np.savetxt(out_path, output, delimiter=",", header=header, comments="", fmt="%.6f")

    dur_s = len(t_10hz) / 10.0
    max_speed_kmh = sp_10hz.max() * 3.6
    mean_speed_kmh = sp_10hz.mean() * 3.6

    return {
        "filename": out_filename,
        "samples": len(t_10hz),
        "duration_s": dur_s,
        "max_speed_kmh": max_speed_kmh,
        "mean_speed_kmh": mean_speed_kmh,
    }


def main():
    print("\n" + "=" * 80)
    print("UAH-DRIVESET CONVERSION ENGINE FOR IDR TCN SPEED TRAINING")
    print(f"Output Directory: {OUTPUT_DIR}")
    print("=" * 80)

    # Check for existing converted files
    existing = glob.glob(os.path.join(OUTPUT_DIR, "uah_*.csv"))
    if len(existing) >= 30:
        total_samples = 0
        for f in existing:
            with open(f, "r") as fp:
                total_samples += sum(1 for _ in fp) - 1
        print(f"\n[OK] UAH-DriveSet already converted: {len(existing)} trips ({total_samples:,} samples @ 10 Hz)")
        print("[OK] Skipping re-conversion. Delete output directory to force re-processing.")
        return

    # Step 1: Look for ZIP file or extracted data
    zip_path = find_uah_zip()
    if zip_path:
        print(f"\n[*] Found UAH-DriveSet ZIP: {zip_path}")
        extract_zip(zip_path)

    # Step 2: Find trip folders (either from ZIP extraction or pre-existing)
    search_roots = [RAW_DIR, SCRIPT_DIR, os.path.join(SCRIPT_DIR, "datasets")]
    all_trips = []
    for root in search_roots:
        if os.path.isdir(root):
            found = find_trip_folders(root)
            all_trips.extend(found)

    # Deduplicate by folder path
    seen = set()
    unique_trips = []
    for driver, path, folder in all_trips:
        if path not in seen:
            seen.add(path)
            unique_trips.append((driver, path, folder))

    if not unique_trips:
        print("\n" + "=" * 80)
        print("UAH-DRIVESET NOT FOUND — MANUAL DOWNLOAD REQUIRED")
        print("=" * 80)
        print("""
The UAH-DriveSet requires accepting a license agreement before download.

Steps to acquire:
  1. Visit: http://www.robesafe.com/personal/eduardo.romera/uah-driveset/
  2. Scroll to the "Download" section
  3. Check "I Agree to Terms & Conditions"
  4. Enter your email and click "Download file"
  5. Save the ZIP to one of these locations:
     - {script_dir}/uah-driveset.zip
     - {script_dir}/datasets/uah-driveset.zip
     - ~/Downloads/uah-driveset.zip
  6. Re-run this script: python download_uah_driveset.py

Alternatively, extract the ZIP manually into:
  {raw_dir}/
and place the driver folders (D1/, D2/, ..., D6/) inside.
""".format(
            script_dir=SCRIPT_DIR,
            raw_dir=RAW_DIR,
        ))
        return

    print(f"\n[*] Found {len(unique_trips)} trip folders across UAH-DriveSet")

    # Step 3: Process each trip
    total_saved = 0
    total_samples = 0
    total_duration = 0.0

    for i, (driver, path, folder) in enumerate(unique_trips):
        print(f"\n[{i + 1}/{len(unique_trips)}] Processing {driver}/{folder}...")
        result = process_trip(driver, path, folder)

        if result is None:
            print(f"    [-] Skipped (too short, stationary, or corrupt data)")
            continue

        total_saved += 1
        total_samples += result["samples"]
        total_duration += result["duration_s"]
        print(
            f"    [+] Saved {result['filename']}: "
            f"{result['samples']:,} samples @ 10 Hz "
            f"({result['duration_s']:.0f}s, "
            f"max: {result['max_speed_kmh']:.1f} km/h, "
            f"mean: {result['mean_speed_kmh']:.1f} km/h)"
        )

    # Step 4: Summary
    print("\n" + "=" * 80)
    print("UAH-DRIVESET CONVERSION COMPLETE")
    print("=" * 80)
    print(f"  Total Trips Converted      : {total_saved}")
    print(f"  Total 10 Hz Samples        : {total_samples:,}")
    print(f"  Total Driving Duration     : {total_duration / 60.0:.1f} minutes")
    print(f"  Output Directory           : {OUTPUT_DIR}")
    print(f"  Output Format              : accel_x,accel_y,accel_z,gyr_x,gyr_y,gyr_z,speed_mps")

    if total_saved > 0:
        print(f"\n  [✓] Ready for TCN training! Add '{OUTPUT_DIR}' to your train.py data paths.")
        print(f"  [!] Note: Gyro channels are synthesized from Euler angle derivatives.")
        print(f"      They capture yaw/pitch/roll rates accurately, but lack the")
        print(f"      high-frequency vibration content of raw MEMS gyroscopes.")
        print(f"      Best used as supplementary data alongside IO-VNBD (which has raw gyro).")
    else:
        print(f"\n  [!] No trips were successfully converted.")
        print(f"      Ensure the UAH-DriveSet is properly extracted in {RAW_DIR}")

    print("=" * 80 + "\n")


if __name__ == "__main__":
    main()
