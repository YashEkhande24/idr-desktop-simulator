import os
import sys
import json
import requests
import time

try:
    sys.stdout.reconfigure(encoding='utf-8')
except Exception:
    pass

API_KEY = os.environ.get("SILVR_API_KEY", "sk-silvr-7b3d7fea700d2f9fe30d837408a2a2592b828dd26db4d1665ec990122d6600d4")
URL = "https://api.silvrai.net/v1/chat/completions"
MODEL = "claude-opus-5-5"

SYSTEM_PROMPT = """You are Claude Opus 5.5 in high-thinking mode, an elite Principal Systems Architect and specialist in Inertial Navigation Systems (INS/GNSS dead-reckoning), 3D Extended Kalman Filters (EKF), Quaternion kinematics, and high-performance cross-platform software.

Conduct a rigorous, deep-thinking review of the provided subsystem codebase.
Think step-by-step with deep mathematical rigor before answering.
Focus on finding concrete errors, subtle bugs, edge cases, numerical instabilities, and inconsistencies:
1. Mathematics & Physics:
   - Coordinate frame transformations (Body, Cabin, Navigation ENU, ECEF)
   - Quaternion propagation, normalization, and gimbal lock/singularity avoidance
   - Gravity extraction, centrifugal/Coriolis compensations, accelerometer integration
   - Covariance matrix symmetry and positive semi-definiteness, Joseph form updates
   - Bias drift modeling (gyro and accel biases) and ZUPT / ZARU constraints
2. Edge cases, logic bugs, memory/pointer management:
   - Zero or negative time steps (dt <= 0), division by zero, NaN/Inf checks
   - Matrix inversions without conditioning/regularization
   - Buffer overflows, memory leaks, uninitialized variables, thread-safety
3. Discrepancies and contract mismatches:
   - Units (rad vs deg, m/s vs km/h, g vs m/s^2)
   - API signatures and struct alignments

Structure your review:
- Summary of Section Health
- Prioritized Findings (Critical / Major / Minor): For each finding, provide:
  * Issue & File/Line
  * Exact Root Cause
  * Concrete Code Fix (provide the exact corrected code block or diff)
- Recommended Next Steps

Be concise, mathematically rigorous, and concrete."""

def call_opus_review(subsystem_name, files_list, max_tokens=8192):
    print(f"\n{'='*70}")
    print(f"Bundling subsystem: {subsystem_name}")
    print(f"{'='*70}")
    
    bundled_code = ""
    included_files = []
    for fpath in files_list:
        if not os.path.exists(fpath):
            print(f"Warning: File {fpath} not found.")
            continue
        with open(fpath, "r", encoding="utf-8", errors="replace") as f:
            content = f.read()
        bundled_code += f"\n\n// ==================== FILE: {fpath} ====================\n"
        bundled_code += content
        included_files.append(fpath)

    char_count = len(bundled_code)
    est_tokens = char_count // 4
    print(f"Subsystem '{subsystem_name}': {len(included_files)} files, {char_count:,} chars, ~{est_tokens:,} est input tokens.")

    user_prompt = f"""### SUBSYSTEM REVIEW REQUEST: {subsystem_name}

Please review the following complete codebase for this subsystem:

{bundled_code}

Identify all bugs, numerical instability, logical flaws, memory issues, and mathematical discrepancies.
For each issue, specify the exact file, exact problematic code, root cause explanation, and provide the EXACT corrected code replacement."""

    payload = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_prompt}
        ],
        "max_tokens": max_tokens
    }

    headers = {
        "Authorization": f"Bearer {API_KEY}",
        "Content-Type": "application/json"
    }

    print(f"Calling SilvR AI ({MODEL}) (max_tokens={max_tokens})...")
    t0 = time.time()
    try:
        r = requests.post(URL, headers=headers, json=payload, timeout=300)
    except Exception as e:
        print(f"Request failed: {e}")
        return None

    elapsed = time.time() - t0
    if not r.ok:
        print(f"API Error {r.status_code}: {r.text}")
        return None

    res = r.json()
    choices = res.get("choices", [])
    if not choices:
        print("No choices returned in response:", res)
        return None

    msg = choices[0].get("message", {})
    reply = msg.get("content", "")
    finish_reason = choices[0].get("finish_reason", "unknown")
    usage = res.get("usage", {})
    prompt_tokens = usage.get("prompt_tokens", 0)
    completion_tokens = usage.get("completion_tokens", 0)
    cost = (prompt_tokens * 4.0 / 1e6) + (completion_tokens * 20.0 / 1e6)

    print(f"Received review in {elapsed:.1f}s! Finish reason: {finish_reason}")
    print(f"Usage: {prompt_tokens:,} prompt tokens | {completion_tokens:,} completion tokens")
    print(f"Estimated Cost: ${cost:.4f}")

    if not reply.strip():
        print("WARNING: Reply content is empty! Dumping choice message:")
        print(json.dumps(msg, indent=2))

    # Save review to results
    os.makedirs("results/opus_reviews", exist_ok=True)
    out_filename = f"results/opus_reviews/{subsystem_name.lower().replace(' ', '_')}_review.md"
    with open(out_filename, "w", encoding="utf-8") as out_f:
        out_f.write(f"# Claude Opus 5.5 Review: {subsystem_name}\n\n")
        out_f.write(f"**Date:** {time.strftime('%Y-%m-%d %H:%M:%S')}\n")
        out_f.write(f"**Model:** {MODEL}\n")
        out_f.write(f"**Finish Reason:** {finish_reason}\n")
        out_f.write(f"**Tokens:** {prompt_tokens:,} in, {completion_tokens:,} out | **Cost:** ${cost:.4f}\n\n")
        out_f.write(reply)
    print(f"Saved review to: {out_filename}")
    return reply

SUBSYSTEMS = {
    "cpp_ekf": (
        "CPP_Core_EKF_Math",
        [
            "cpp_mobile_app/core/include/idr/ekf_3d.hpp",
            "cpp_mobile_app/core/src/ekf_3d.cpp",
            "cpp_mobile_app/core/include/idr/common.hpp",
            "cpp_mobile_app/core/src/common.cpp"
        ]
    ),
    "cpp_motion": (
        "CPP_Motion_Gating_Pipeline",
        [
            "cpp_mobile_app/core/include/idr/types.hpp",
            "cpp_mobile_app/core/include/idr/cabin_aligner.hpp",
            "cpp_mobile_app/core/src/cabin_aligner.cpp",
            "cpp_mobile_app/core/include/idr/vibration_gate.hpp",
            "cpp_mobile_app/core/src/vibration_gate.cpp",
            "cpp_mobile_app/core/include/idr/tcn_speed_engine.hpp",
            "cpp_mobile_app/core/src/tcn_speed_engine.cpp",
            "cpp_mobile_app/core/include/idr/baseline_dr.hpp",
            "cpp_mobile_app/core/src/baseline_dr.cpp",
            "cpp_mobile_app/core/include/idr/pipeline.hpp",
            "cpp_mobile_app/core/src/pipeline.cpp",
            "cpp_mobile_app/core/include/idr/c_api.h",
            "cpp_mobile_app/core/src/c_api.cpp"
        ]
    ),
    "sim_models": (
        "Simulation_and_Models",
        [
            "idr_simulation/pipeline.py",
            "idr_simulation/common.py",
            "idr_simulation/fusion/ekf_3d.py",
            "idr_simulation/fusion/classic_dr.py",
            "idr_simulation/fusion/map_snapper.py",
            "idr_simulation/models/tcn_speed_engine.py",
            "idr_simulation/models/vibration_gate.py",
            "idr_simulation/sensors/cabin_alignment.py",
            "idr_simulation/sensors/generator.py",
            "model/eval_production.py"
        ]
    ),
    "flutter_engine": (
        "Flutter_DeadReckoning_Engine",
        [
            "lib/core/math_utils.dart",
            "lib/models/ekf_state.dart",
            "lib/models/nav_solution.dart",
            "lib/services/ekf_3d.dart",
            "lib/services/idr_pipeline.dart",
            "lib/services/tcn_speed_engine.dart",
            "lib/services/cabin_alignment.dart",
            "lib/services/vibration_gate.dart",
            "lib/services/native_bridge.dart",
            "lib/services/map_snapper.dart",
            "lib/services/turn_detector.dart",
            "lib/services/sensor_service.dart"
        ]
    )
}

if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "cpp_ekf"
    if target in SUBSYSTEMS:
        name, flist = SUBSYSTEMS[target]
        call_opus_review(name, flist, max_tokens=8192)
    elif target == "all":
        for k in ["cpp_ekf", "cpp_motion", "sim_models", "flutter_engine"]:
            name, flist = SUBSYSTEMS[k]
            call_opus_review(name, flist, max_tokens=8192)
    else:
        print(f"Unknown target '{target}'. Available: {list(SUBSYSTEMS.keys())}")
