"""Headless benchmark: run the full route and print drift statistics.

    python -m idr_simulation.benchmark
    python -m idr_simulation.benchmark --ablate --seeds 3
"""

from __future__ import annotations

import argparse

import numpy as np

from .pipeline import IDRPipeline, PipelineOptions


def run_once(options: PipelineOptions, max_seconds: float = 400.0) -> dict:
    pipe = IDRPipeline(options)
    limit = int(max_seconds / pipe.dt)
    for _ in range(limit):
        pipe.step()
        if pipe.finished:
            break
    out = pipe.summary()
    out["duration_s"] = pipe.last.get("t", 0.0)
    return out


def _fmt(tag: str, s: dict) -> str:
    return (f"{tag:<22} IDR rmse {s['idr_rmse_m']:7.2f} m | max {s['idr_max_m']:7.2f} m | "
            f"final {s['idr_final_m']:7.2f} m || Classic rmse {s['classic_rmse_m']:9.1f} m | "
            f"max {s['classic_max_m']:9.1f} m")


def main() -> None:
    ap = argparse.ArgumentParser(description="IDR headless benchmark")
    ap.add_argument("--seeds", type=int, default=1)
    ap.add_argument("--ablate", action="store_true", help="disable modules one at a time")
    ap.add_argument("--backend", default=None, choices=["torch", "onnx", "numpy", "heuristic"])
    args = ap.parse_args()

    base_seeds = [20260905 + 101 * i for i in range(args.seeds)]
    runs = [run_once(PipelineOptions(seed=s, backend_preference=args.backend))
            for s in base_seeds]

    print(f"speed backend: {runs[0]['speed_backend']}   route: {runs[0]['duration_s']:.0f} s")
    print("-" * 108)
    for seed, r in zip(base_seeds, runs):
        print(_fmt(f"seed {seed}", r))
    if len(runs) > 1:
        agg = {k: float(np.mean([r[k] for r in runs])) for k in
               ("idr_rmse_m", "idr_max_m", "idr_final_m", "classic_rmse_m", "classic_max_m")}
        print("-" * 108)
        print(_fmt("MEAN", {**agg, "idr_final_m": agg["idr_final_m"]}))

    r0 = runs[0]
    print("-" * 108)
    print(f"tunnel-only IDR rmse {r0['tunnel_idr_rmse_m']:.2f} m  max {r0['tunnel_idr_max_m']:.2f} m  "
          f"(classic max {r0['tunnel_classic_max_m']:.1f} m)")
    print(f"TCN speed rmse {r0['speed_rmse_mps']:.2f} m/s | shock events {r0['shock_events']} | "
          f"GNSS accepted {r0['gnss_accepts']} rejected {r0['gnss_rejects']}")

    if args.ablate:
        print("\nablation (seed %d)" % base_seeds[0])
        print("-" * 108)
        variants = {
            "full": {},
            "no vibration gate": {"enable_vibration_gate": False},
            "no NHC": {"enable_nhc": False},
            "no map snapping": {"enable_map_snapping": False},
            "no barometer": {"enable_baro": False},
            "no TCN (heuristic)": {"enable_tcn": False},
        }
        for name, kw in variants.items():
            s = run_once(PipelineOptions(seed=base_seeds[0],
                                        backend_preference=args.backend, **kw))
            print(_fmt(name, s))


if __name__ == "__main__":
    main()
