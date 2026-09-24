"""
Generates visual benchmark plots for comprehensive automotive scenario testing.
Saves PNG charts to the artifact directory.
"""

import os
import sys
import json
import glob
from pathlib import Path
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from model.eval_comprehensive_scenarios import ScenarioEvaluator, find_candidate_files
from model.train import load_and_parse_iovnbd_file

ARTIFACT_DIR = Path(r"C:\Users\yashe\.gemini\antigravity-ide\brain\5503a5ba-b889-4c6d-92d5-3e2278671d2e")

def generate_scenario_plots():
    results_path = REPO_ROOT / "model" / "comprehensive_scenario_results.json"
    if not results_path.exists():
        print("Results JSON not found, skipping.")
        return

    with open(results_path) as f:
        results = json.load(f)

    # 1. Category Bar Chart: Pass Rate and Drift by Category
    categories = sorted(list(set(r['type'] for r in results)))
    cat_drift = []
    cat_pass = []
    cat_names = []
    for c in categories:
        items = [r for r in results if r['type'] == c]
        cat_names.append(c.replace(" ", "\n"))
        cat_drift.append(np.mean([i['pipe_drift_pct'] for i in items]))
        cat_pass.append(sum(1 for i in items if i['passed']) / len(items) * 100.0)

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 6))
    fig.patch.set_facecolor('#0f172a')
    ax1.set_facecolor('#1e293b')
    ax2.set_facecolor('#1e293b')

    # Pass Rate
    bars1 = ax1.bar(cat_names, cat_pass, color='#10b981', edgecolor='#059669', width=0.55)
    ax1.set_title("Pass Rate by Scenario Category (Criteria: <10% Drift)", color='white', fontsize=12, fontweight='bold', pad=12)
    ax1.set_ylabel("Pass Rate (%)", color='white', fontsize=11)
    ax1.set_ylim(0, 110)
    ax1.axhline(90, color='#f59e0b', linestyle='--', alpha=0.7, label='90% Target')
    ax1.tick_params(colors='white', labelsize=9)
    for spine in ax1.spines.values():
        spine.set_color('#334155')
    for bar in bars1:
        yval = bar.get_height()
        ax1.text(bar.get_x() + bar.get_width()/2.0, yval + 2, f"{yval:.0f}%", ha='center', va='bottom', color='#34d399', fontweight='bold', fontsize=10)
    ax1.legend(facecolor='#1e293b', edgecolor='#334155', labelcolor='white')

    # Drift %
    bars2 = ax2.bar(cat_names, cat_drift, color='#38bdf8', edgecolor='#0284c7', width=0.55)
    ax2.set_title("Average Drift % by Scenario Category (Lower is Better)", color='white', fontsize=12, fontweight='bold', pad=12)
    ax2.set_ylabel("Average Drift (%)", color='white', fontsize=11)
    ax2.axhline(10.0, color='#ef4444', linestyle='--', alpha=0.8, label='10% SIH Failure Threshold')
    ax2.tick_params(colors='white', labelsize=9)
    for spine in ax2.spines.values():
        spine.set_color('#334155')
    for bar in bars2:
        yval = bar.get_height()
        ax2.text(bar.get_x() + bar.get_width()/2.0, yval + 0.3, f"{yval:.2f}%", ha='center', va='bottom', color='#7dd3fc', fontweight='bold', fontsize=10)
    ax2.legend(facecolor='#1e293b', edgecolor='#334155', labelcolor='white')

    plt.tight_layout()
    chart_path = ARTIFACT_DIR / "scenario_category_performance.png"
    plt.savefig(chart_path, dpi=200, facecolor=fig.get_facecolor())
    plt.close()
    print(f"Saved category performance chart to: {chart_path}")

    # 2. Detailed Scenario Profiles: Stop-and-Go vs Tunnel Outage
    evaluator = ScenarioEvaluator()
    file_map = find_candidate_files()
    
    fig, axes = plt.subplots(2, 2, figsize=(16, 10))
    fig.patch.set_facecolor('#0f172a')
    for ax_row in axes:
        for ax in ax_row:
            ax.set_facecolor('#1e293b')
            ax.tick_params(colors='white', labelsize=9)
            for s in ax.spines.values():
                s.set_color('#334155')

    # Profile 1: Stop-and-Go Congestion (S-Vta1a.csv)
    if 'S-Vta1a.csv' in file_map:
        imu, speed = load_and_parse_iovnbd_file(file_map['S-Vta1a.csv'])
        W = 40
        N = 1000 # 100 seconds
        raw, _ = evaluator.run_inference(imu[:N+W], W=W)
        evaluator.pipeline_sim.reset()
        pipe = np.array([evaluator.pipeline_sim.step(raw[k], imu[k:k+W]) for k in range(len(raw))])
        truth = speed[W-1:W-1+len(raw)]
        t_sec = np.arange(len(raw)) * 0.1

        axes[0, 0].plot(t_sec, truth * 3.6, color='#94a3b8', linewidth=2.0, label='Ground Truth Speed')
        axes[0, 0].plot(t_sec, pipe * 3.6, color='#38bdf8', linewidth=1.8, label='App Pipeline Speed')
        axes[0, 0].set_title("Scenario: Urban Stop-and-Go Cycles (S-Vta1a)", color='white', fontweight='bold', fontsize=11)
        axes[0, 0].set_ylabel("Speed (km/h)", color='white')
        axes[0, 0].set_xlabel("Time (s)", color='white')
        axes[0, 0].legend(facecolor='#1e293b', edgecolor='#334155', labelcolor='white')

        axes[0, 1].plot(t_sec, np.cumsum(truth * 0.1), color='#94a3b8', linewidth=2.0, label='True Distance')
        axes[0, 1].plot(t_sec, np.cumsum(pipe * 0.1), color='#10b981', linewidth=1.8, linestyle='--', label='Estimated Distance')
        axes[0, 1].set_title("Cumulative Distance Tracking: Stop-and-Go", color='white', fontweight='bold', fontsize=11)
        axes[0, 1].set_ylabel("Distance (m)", color='white')
        axes[0, 1].set_xlabel("Time (s)", color='white')
        axes[0, 1].legend(facecolor='#1e293b', edgecolor='#334155', labelcolor='white')

    # Profile 2: Simulated GNSS Highway Tunnel Outage (S-Vtb1.csv 120s)
    if 'S-Vtb1.csv' in file_map:
        imu, speed = load_and_parse_iovnbd_file(file_map['S-Vtb1.csv'])
        start = 1200
        N = 1200 # 120s tunnel
        W = 40
        raw, _ = evaluator.run_inference(imu[start:start+N+W], W=W)
        evaluator.pipeline_sim.reset()
        pipe = np.array([evaluator.pipeline_sim.step(raw[k], imu[start+k:start+k+W]) for k in range(len(raw))])
        truth = speed[start+W-1:start+W-1+len(raw)]
        t_sec = np.arange(len(raw)) * 0.1

        axes[1, 0].plot(t_sec, truth * 3.6, color='#94a3b8', linewidth=2.0, label='Ground Truth Speed')
        axes[1, 0].plot(t_sec, pipe * 3.6, color='#f59e0b', linewidth=1.8, label='Dead-Reckoning In-Tunnel Speed')
        axes[1, 0].set_title("Scenario: 120s Highway Tunnel Outage @ 90 km/h", color='white', fontweight='bold', fontsize=11)
        axes[1, 0].set_ylabel("Speed (km/h)", color='white')
        axes[1, 0].set_xlabel("Time Inside Tunnel (s)", color='white')
        axes[1, 0].legend(facecolor='#1e293b', edgecolor='#334155', labelcolor='white')

        axes[1, 1].plot(t_sec, np.cumsum(truth * 0.1), color='#94a3b8', linewidth=2.0, label='True Distance')
        axes[1, 1].plot(t_sec, np.cumsum(pipe * 0.1), color='#a855f7', linewidth=1.8, linestyle='--', label='DR Distance')
        drift_end = abs(np.sum(pipe*0.1) - np.sum(truth*0.1)) / np.sum(truth*0.1) * 100.0
        axes[1, 1].set_title(f"Cumulative Tunnel Distance (End Drift: {drift_end:.2f}%)", color='white', fontweight='bold', fontsize=11)
        axes[1, 1].set_ylabel("Distance (m)", color='white')
        axes[1, 1].set_xlabel("Time Inside Tunnel (s)", color='white')
        axes[1, 1].legend(facecolor='#1e293b', edgecolor='#334155', labelcolor='white')

    plt.tight_layout()
    detail_path = ARTIFACT_DIR / "scenario_dynamic_profiles.png"
    plt.savefig(detail_path, dpi=200, facecolor=fig.get_facecolor())
    plt.close()
    print(f"Saved dynamic scenario profiles to: {detail_path}")

if __name__ == '__main__':
    generate_scenario_plots()
