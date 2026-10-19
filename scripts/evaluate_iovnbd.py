#!/usr/bin/env python3
"""
================================================================================
IDR-Navigator: IO-VNBD Benchmark Evaluation Script
Smart India Hackathon 2026 | Problem Statement: SIH26168 (ISRO)
Team: Inventor | Team ID: 133715
================================================================================
This script evaluates the IDR-NeuroSpeed-TCN model on IO-VNBD test scenarios.

It is a thin wrapper around idr_model_submission/test.py that:
  1. Runs inference on all CSV scenarios in sample_data/
  2. Exports results to results/benchmark_report.json
  3. Optionally generates speed-profile and trajectory plots

Usage:
  python scripts/evaluate_iovnbd.py
  python scripts/evaluate_iovnbd.py --input path/to/custom_scenario.csv
  python scripts/evaluate_iovnbd.py --plot
================================================================================

NOTE: All benchmark figures referenced in the README are sourced directly from
idr_model_submission/results.json, produced by idr_model_submission/test.py.
This script does NOT generate synthetic trajectories or fabricated data.
================================================================================
"""

import os
import sys
import json
import argparse
from pathlib import Path

# Force UTF-8 encoding on Windows terminal stdout
if hasattr(sys.stdout, 'reconfigure'):
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        pass


def run_evaluation(csv_path, model_path, export_metrics=None, export_plot=None):
    """
    Runs the IDR-NeuroSpeed-TCN benchmark evaluation on the given CSV.
    
    This delegates to idr_model_submission/test.py's evaluation logic.
    All numbers produced are from actual ONNX Runtime inference — no synthetic data.
    """
    # Resolve paths relative to repository root
    repo_root = Path(__file__).resolve().parent.parent
    model_submission_dir = repo_root / "idr_model_submission"
    
    # Add model submission dir to path so we can import test.py
    sys.path.insert(0, str(model_submission_dir))
    
    try:
        from test import ModelRunner, evaluate_scenario
    except ImportError as e:
        print(f"[!] Could not import from idr_model_submission/test.py: {e}")
        print("[!] Falling back to reading cached results.json...")
        return _print_cached_results(repo_root)
    
    # Resolve model path
    model_file = Path(model_path)
    if not model_file.is_absolute():
        model_file = repo_root / model_file
    
    stats_file = model_submission_dir / "normalize_stats.json"
    
    if not model_file.exists():
        print(f"[!] Model file not found: {model_file}")
        print("[!] Falling back to cached results.json...")
        return _print_cached_results(repo_root)
    
    if not stats_file.exists():
        print(f"[!] Normalization stats not found: {stats_file}")
        return _print_cached_results(repo_root)
    
    # Initialize model runner
    print("=" * 80)
    print("  IDR-Navigator: IO-VNBD Benchmark Evaluation")
    print("  Smart India Hackathon 2026 | SIH26168 (ISRO)")
    print("=" * 80)
    print(f"  Model : {model_file.name}")
    print(f"  Engine: ONNX Runtime")
    print(f"  Mode  : Production (ZUPT + EMA)")
    print("=" * 80)
    
    try:
        runner = ModelRunner(model_file, stats_file, engine="onnx")
    except Exception as e:
        print(f"[!] Model initialization failed: {e}")
        return _print_cached_results(repo_root)
    
    # Collect CSV files
    csv_input = Path(csv_path)
    if not csv_input.is_absolute():
        csv_input = repo_root / csv_input
    
    if csv_input.is_file():
        csv_files = [csv_input]
    elif csv_input.is_dir():
        csv_files = sorted(list(csv_input.glob("*.csv")))
    else:
        # Try sample_data directory
        sample_dir = model_submission_dir / "sample_data"
        if sample_dir.exists():
            csv_files = sorted(list(sample_dir.glob("*.csv")))
        else:
            print(f"[!] No CSV files found. Path: {csv_input}")
            return _print_cached_results(repo_root)
    
    if not csv_files:
        print("[!] No CSV scenario files found.")
        return _print_cached_results(repo_root)
    
    # Run evaluation on each scenario
    import numpy as np
    
    results = []
    print(f"\n{'SCENARIO':<42} | {'DIST':>7} | {'DRIFT':>9} | {'MAE':>8} | VERDICT")
    print("-" * 85)
    
    for csv_file in csv_files:
        try:
            res = evaluate_scenario(runner, str(csv_file), mode="production")
            if res is None:
                continue
            results.append(res)
            status = "PASS" if res["passed"] else "FAIL"
            fname = res["file"][:40]
            print(f"  {fname:<40} | {res['true_dist_m']:6.1f}m | {res['drift_pct']:7.2f}% | {res['mae_mps']:.2f} m/s | [{status}]")
        except Exception as e:
            print(f"  {csv_file.name:<40} | ERROR: {e}")
    
    if not results:
        print("[!] No scenarios evaluated successfully.")
        return _print_cached_results(repo_root)
    
    # Compute aggregate stats
    passed_count = sum(1 for r in results if r["passed"])
    total_count = len(results)
    pass_pct = (passed_count / total_count) * 100.0
    mean_drift = float(np.mean([r["drift_pct"] for r in results]))
    mean_mae = float(np.mean([r["mae_mps"] for r in results]))
    mean_latency = float(np.mean([r["latency_per_step_ms"] for r in results]))
    total_dist = float(np.sum([r["true_dist_m"] for r in results]))
    
    print("=" * 85)
    print(f"  Pass Rate          : {passed_count}/{total_count} ({pass_pct:.1f}%)")
    print(f"  Mean Drift         : {mean_drift:.4f}%")
    print(f"  Mean Speed MAE     : {mean_mae:.4f} m/s ({mean_mae * 3.6:.2f} km/h)")
    print(f"  Total Distance     : {total_dist:.1f} m")
    print(f"  Mean Latency       : {mean_latency:.2f} ms/step")
    print(f"  ISRO Requirement   : Drift < 10.0%")
    print(f"  Verdict            : {'ALL PASSED' if pass_pct >= 100.0 else f'{passed_count}/{total_count} PASSED'}")
    print("=" * 85)
    
    # Export metrics
    summary = {
        "model": str(model_file.name),
        "engine": "onnx",
        "mode": "production",
        "pass_rate_pct": pass_pct,
        "mean_drift_pct": mean_drift,
        "mean_mae_mps": mean_mae,
        "scenarios": [
            {k: v for k, v in r.items() if k not in ("true_speeds", "pred_speeds")}
            for r in results
        ]
    }
    
    if export_metrics:
        os.makedirs(os.path.dirname(export_metrics) if os.path.dirname(export_metrics) else ".", exist_ok=True)
        with open(export_metrics, "w") as f:
            json.dump(summary, f, indent=2)
        print(f"[+] Metrics exported to: {export_metrics}")
    
    # Export plots
    if export_plot:
        try:
            import matplotlib
            matplotlib.use('Agg')
            import matplotlib.pyplot as plt
            
            os.makedirs(os.path.dirname(export_plot) if os.path.dirname(export_plot) else ".", exist_ok=True)
            
            for r in results:
                if "true_speeds" not in r or "pred_speeds" not in r:
                    continue
                    
                fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 6), sharex=True)
                t_axis = np.arange(len(r["true_speeds"])) * 0.1
                
                ax1.plot(t_axis, r["true_speeds"] * 3.6, 'k--', label="Ground Truth (GPS/CAN)", alpha=0.8)
                ax1.plot(t_axis, r["pred_speeds"] * 3.6, 'r-', label="IDR-NeuroSpeed-TCN", alpha=0.9)
                ax1.set_ylabel("Speed (km/h)")
                ax1.set_title(f"Scenario: {r['file']} | Drift: {r['drift_pct']:.2f}% (MAE: {r['mae_mps']:.2f} m/s)")
                ax1.grid(True, linestyle="--", alpha=0.5)
                ax1.legend(loc="upper right")
                
                cum_true = np.cumsum(r["true_speeds"] * 0.1)
                cum_pred = np.cumsum(r["pred_speeds"] * 0.1)
                ax2.plot(t_axis, cum_true, 'k--', label="True Distance (m)")
                ax2.plot(t_axis, cum_pred, 'b-', label="Dead Reckoning (m)")
                ax2.set_xlabel("Time (seconds)")
                ax2.set_ylabel("Distance (m)")
                ax2.grid(True, linestyle="--", alpha=0.5)
                ax2.legend(loc="upper left")
                
                plt.tight_layout()
                plot_file = Path(export_plot).parent / f"{Path(r['file']).stem}_evaluation.png"
                fig.savefig(str(plot_file), dpi=150)
                plt.close(fig)
                print(f"[+] Plot saved: {plot_file}")
                
        except ImportError:
            print("[*] matplotlib not installed; skipping plot generation.")
        except Exception as e:
            print(f"[-] Plot generation failed: {e}")
    
    return summary


def _print_cached_results(repo_root):
    """
    Falls back to printing cached results from idr_model_submission/results.json
    when live inference is not possible.
    """
    results_file = repo_root / "idr_model_submission" / "results.json"
    if not results_file.exists():
        print("[!] No cached results.json found.")
        return None
    
    print("\n[*] Displaying cached benchmark results from idr_model_submission/results.json:")
    print("=" * 80)
    
    with open(results_file, 'r') as f:
        data = json.load(f)
    
    print(f"  Model        : {data.get('model', 'N/A')}")
    print(f"  Engine       : {data.get('engine', 'N/A')}")
    print(f"  Mode         : {data.get('mode', 'N/A')}")
    print(f"  Pass Rate    : {data.get('pass_rate_pct', 'N/A')}%")
    print(f"  Mean Drift   : {data.get('mean_drift_pct', 'N/A')}%")
    print(f"  Mean MAE     : {data.get('mean_mae_mps', 'N/A')} m/s")
    print()
    
    scenarios = data.get('scenarios', [])
    print(f"  {'SCENARIO':<42} | {'DRIFT':>9} | {'MAE':>8} | VERDICT")
    print("  " + "-" * 75)
    for s in scenarios:
        status = "PASS" if s.get("passed", False) else "FAIL"
        print(f"  {s['file']:<42} | {s['drift_pct']:7.2f}% | {s['mae_mps']:.2f} m/s | [{status}]")
    
    print("=" * 80)
    return data


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="IDR-Navigator IO-VNBD Benchmark Evaluation (SIH26168 - ISRO)")
    parser.add_argument("--input", type=str,
                        default="idr_model_submission/sample_data",
                        help="Path to input test CSV file or directory")
    parser.add_argument("--model", type=str,
                        default="idr_model_submission/idr_neurospeed_tcn.onnx",
                        help="Path to ONNX model")
    parser.add_argument("--export-metrics", type=str,
                        default="results/benchmark_report.json",
                        help="Path to save benchmark report JSON")
    parser.add_argument("--export-plot", type=str, default=None,
                        help="Path to save evaluation plots")
    parser.add_argument("--plot", action="store_true",
                        help="Enable plot generation to results/")

    args = parser.parse_args()
    
    export_plot = args.export_plot
    if args.plot and not export_plot:
        export_plot = "results/plots/"
    
    os.makedirs("results", exist_ok=True)
    
    run_evaluation(
        csv_path=args.input,
        model_path=args.model,
        export_metrics=args.export_metrics,
        export_plot=export_plot
    )
