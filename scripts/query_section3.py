import requests
import json

API_KEY = "sk-silvr-7b3d7fea700d2f9fe30d837408a2a2592b828dd26db4d1665ec990122d6600d4"

prompt = """
We are building Section 3 of our ISRO SIH Dead-Reckoning simulator:
"Dual Solvers (Classical INS Divergence vs IDR 5-Stage Cascade) and Off-Screen Radar Beacon".

Context:
- Canvas: canvasW = 960, canvasH = 480.
- Scale: PX_PER_METER = 1.5.
- Simulation step: dt = 0.01s (100 Hz).
- Gravity: G0 = 9.80665 m/s^2.
- Ground truth vehicle pos is in pixels.

Requirements for Section 3:
Provide production-grade JavaScript implementations of:

1. `class ClassicDeadReckoning`:
   - Tracks pos (Vec3, in pixels), vel (Vec3, in m/s), yaw (radians).
   - init(posPx, v0_ms, yaw): initializes state.
   - update(acc_body, gyro_body, dt):
     * integrates yaw: yaw += gyro_body.z * dt
     * body to world rotation:
       acc_world_x = Math.cos(yaw) * acc_body.x - Math.sin(yaw) * acc_body.y
       acc_world_y = Math.sin(yaw) * acc_body.x + Math.cos(yaw) * acc_body.y
     * velocity update (m/s): vel.x += acc_world_x * dt, vel.y += acc_world_y * dt
     * position update (pixels): pos.x += vel.x * PX_PER_METER * dt, pos.y += vel.y * PX_PER_METER * dt
   - resync(posPx, v0_ms, yaw): cleanly resets state to ground truth with a flag `justResynced = true` for visual animation.

2. `class IDRNavigatorEstimator`:
   - Tracks pos (Vec3, in pixels), vel (Vec3, in m/s), yaw (radians), P_cov, v_tcn, lastInnovation.
   - update(acc_body, gyro_body, v_neural, isShock, isOutage, gnssPosPx, isZupt, circuit, dt):
     * Stage 1: Attitude observer with gyro bias damping (yaw += (gyro_body.z - b_est) * dt).
     * Stage 2: Spectral Vibration Gating: if isShock or Var(acc) > 1.2g^2, hold previous velocity and reject shock.
     * Stage 3 & 4: Neural TCN Speed Prior + Non-Holonomic Constraints (NHC):
       Vehicle velocity strictly aligned with yaw: vel = [cos(yaw)*v_tcn, sin(yaw)*v_tcn].
       If isZupt: vel = 0, P_cov = 0.001.
     * Stage 5: Soft Map-Snapping Vector Projection onto circuit:
       snapped = circuit.project(pos)
       pos += (snapped.pos - pos) * 0.05
     * Covariance P_cov handling: GNSS active -> 0.035, Outage -> slowly rises up to 0.085 m^2.

3. `function drawOffscreenRadar(ctx, carX, carY, carHeading, label, canvasW, canvasH, color)`:
   - If car is inside [0, canvasW] x [0, canvasH], does nothing.
   - If car is outside, clamps to border margin (e.g. 24px from edge) along the ray from canvas center (or nearest border intersection).
   - Calculates distance in meters from canvas boundary = distance_px / PX_PER_METER.
   - Draws a pulsing neon chevron/arrow pointing toward the off-screen car and a clean badge:
     `${label}: +${distM.toFixed(0)}m [OFF-SCREEN]`.

Keep it clean, concise, and return just the production JavaScript code.
"""

r = requests.post(
    "https://api.silvrai.net/v1/chat/completions",
    headers={"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"},
    json={"model": "claude-opus-5-5", "messages": [{"role": "user", "content": prompt}], "max_tokens": 3200},
    timeout=60
)
d = r.json()
msg = d["choices"][0]["message"]
content = msg.get("content", "")
print("Usage:", d.get("usage"))
print("Finish reason:", d["choices"][0].get("finish_reason"))
with open("scripts/section3_solvers.js", "w", encoding="utf-8") as f:
    f.write(content)
print("Saved to scripts/section3_solvers.js")
