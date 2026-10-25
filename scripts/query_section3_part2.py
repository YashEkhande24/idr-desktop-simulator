import requests
import json

API_KEY = "sk-silvr-7b3d7fea700d2f9fe30d837408a2a2592b828dd26db4d1665ec990122d6600d4"

prompt = """
Continuing Section 3:
We have IDRNavigatorEstimator state defined.
Provide the exact implementations of:
1. `update(acc_body, gyro_body, v_neural, isShock, isOutage, gnssPosPx, isZupt, circuit, dt)`:
   - Stage 1: Attitude update:
     gyro_corrected = gyro_body.z - this.b_est
     this.yaw = wrapAngle(this.yaw + gyro_corrected * dt)
     if (isZupt) this.b_est += this.K.BIAS_ZUPT * gyro_body.z
     else this.b_est *= this.K.BIAS_DECAY
   - Stage 2: Spectral Vibration Gate:
     varAcc = this._accVariance(acc_body)
     this.shockRejected = isShock || (varAcc > this.K.VAR_GATE)
   - Stage 3 & 4: Neural Speed Prior + NHC + ZUPT:
     if (isZupt) {
       this.v_tcn = 0
       this.vel.x = 0; this.vel.y = 0
       this.P_cov = this.K.P_ZUPT
     } else if (!this.shockRejected) {
       this.v_tcn += this.K.TCN_ALPHA * (v_neural - this.v_tcn)
       this.vel.x = Math.cos(this.yaw) * this.v_tcn
       this.vel.y = Math.sin(this.yaw) * this.v_tcn
     }
     this.pos.x += this.vel.x * PX_PER_METER * dt
     this.pos.y += this.vel.y * PX_PER_METER * dt
   - Stage 5: Map Snapping & GNSS Fusion:
     if (!isOutage && gnssPosPx) {
       this.lastInnovation.x = gnssPosPx.x - this.pos.x
       this.lastInnovation.y = gnssPosPx.y - this.pos.y
       this.pos.x += this.lastInnovation.x * this.K.GNSS_GAIN
       this.pos.y += this.lastInnovation.y * this.K.GNSS_GAIN
       this.P_cov = this.K.P_GNSS
     } else {
       if (circuit) {
         const snap = circuit.project(this.pos)
         this.pos.x += (snap.pos.x - this.pos.x) * this.K.SNAP_GAIN
         this.pos.y += (snap.pos.y - this.pos.y) * this.K.SNAP_GAIN
       }
       this.P_cov = Math.min(this.K.P_MAX, this.P_cov + this.K.P_RATE * dt)
     }

2. `function drawOffscreenRadar(ctx, carX, carY, carHeading, label, canvasW, canvasH, color = '#ff1744')`:
   - Checks if car is outside canvas margin (margin = 28px).
   - If car is inside [margin, canvasW - margin] x [margin, canvasH - margin], returns false.
   - Computes ray from center (canvasW/2, canvasH/2) to (carX, carY), intersects with bordered rectangle.
   - Computes Euclidean distance in meters = hypot(carX - clampedX, carY - clampedY) / PX_PER_METER.
   - Draws pulsing radar chevron pointing towards (carX, carY) with glowing halo.
   - Draws futuristic HUD badge: `${label}: +${distM.toFixed(0)}m [OFF-SCREEN]`.
   - Returns true.

Keep it clean, concise, and return just the production JavaScript code.
"""

r = requests.post(
    "https://api.silvrai.net/v1/chat/completions",
    headers={"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"},
    json={"model": "claude-opus-5-5", "messages": [{"role": "user", "content": prompt}], "max_tokens": 3000},
    timeout=60
)
d = r.json()
msg = d["choices"][0]["message"]
content = msg.get("content", "")
print("Usage:", d.get("usage"))
print("Finish reason:", d["choices"][0].get("finish_reason"))
with open("scripts/section3_part2.js", "w", encoding="utf-8") as f:
    f.write(content)
print("Saved to scripts/section3_part2.js")
