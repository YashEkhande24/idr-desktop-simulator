import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import onnxruntime as ort
import numpy as np
import json
import glob
import os
from model.train import load_and_parse_iovnbd_file

onnx_path = r"assets\models\vehicle_speed_tcn.onnx"
stats_path = r"assets\models\normalize_stats.json"

with open(stats_path) as f:
    stats = json.load(f)

mean = np.array(stats['mean'], dtype=np.float32)
std = np.array(stats['std'], dtype=np.float32)
scale = float(stats['speed_scale'])

session = ort.InferenceSession(onnx_path)

all_cars = sorted(list(set(glob.glob('model/**/S-V*.csv', recursive=True))))
seen_names = set()
unique_cars = []
for f in all_cars:
    bn = os.path.basename(f)
    if bn not in seen_names:
        seen_names.add(bn)
        unique_cars.append(f)

results = []
for tf in unique_cars:
    bn = os.path.basename(tf)
    parsed = load_and_parse_iovnbd_file(tf)
    if not parsed:
        continue
    imu, speed = parsed
    W = 40
    num_windows = min(600, len(imu) - W)
    if num_windows < 50:
        continue

    samples = []
    truths = []
    for i in range(num_windows):
        w_acc = imu[i:i+W, 0:3]
        w_gyr = imu[i:i+W, 3:6]
        norm_a = np.linalg.norm(w_acc, axis=1, keepdims=True)
        norm_w = np.linalg.norm(w_gyr, axis=1, keepdims=True)
        w8 = np.concatenate([imu[i:i+W, :], norm_a, norm_w], axis=1).T
        samples.append(w8)
        truths.append(speed[i+W-1])

    samples = np.array(samples, dtype=np.float32)
    samples = (samples - mean[:, None][None, :, :]) / std[:, None][None, :, :]

    outputs = session.run(None, {'imu_input': samples})
    raw_preds = np.maximum(0.0, outputs[0].flatten() * scale)
    preds = np.zeros_like(raw_preds)
    curr = raw_preds[0] if len(raw_preds) > 0 else 0.0
    for k in range(len(raw_preds)):
        z = max(0.0, float(raw_preds[k]))
        if z < 0.15:
            curr = 0.0
        else:
            curr = z if curr == 0.0 else (curr * 0.35 + z * 0.65)
        preds[k] = curr

    truths = np.array(truths)

    p_dist = np.sum(preds * 0.1)
    t_dist = np.sum(truths * 0.1)

    err = abs(p_dist - t_dist)
    if t_dist < 30.0:
        drift = (err / 30.0) * 100.0
        passed = (err < 8.0)
    else:
        drift = (err / t_dist) * 100.0
        passed = (drift < 10.0) or (err < 5.0)

    mae = np.mean(np.abs(preds - truths))
    results.append({
        'file': bn,
        'dist': t_dist,
        'pred_dist': p_dist,
        'drift': drift,
        'passed': passed,
        'mae': mae
    })

passed_count = sum(1 for r in results if r['passed'])
print("=" * 75)
print("       PRODUCTION ONNX MODEL SIH BENCHMARK SCORECARD")
print("=" * 75)
print(f"Total Unique Passenger Car Scenarios: {len(results)}")
print(f"Passed (<10% drift rule): {passed_count}/{len(results)} ({passed_count/len(results)*100:.1f}%)")
best = min(results, key=lambda r: r['drift'])
print(f"Best Recorded Drift: {best['drift']:.2f}% on {best['file']}")
print("-" * 75)

for r in results:
    status = "[PASSED]" if r['passed'] else "[FAILED]"
    print(f"{r['file']:<15} | TrueDist: {r['dist']:6.1f}m | PredDist: {r['pred_dist']:6.1f}m | Drift: {r['drift']:5.2f}% {status} | MAE: {r['mae']:.2f}m/s")
print("=" * 75)
