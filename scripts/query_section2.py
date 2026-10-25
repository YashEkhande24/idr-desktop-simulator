import requests
import json

API_KEY = "sk-silvr-7b3d7fea700d2f9fe30d837408a2a2592b828dd26db4d1665ec990122d6600d4"

prompt = """
We are building Section 2 of our ISRO SIH Dead-Reckoning simulator:
IMU Kinematics & Bosch BMI270 Sensor Noise / Bias Drift Model.

Context:
- Screen canvas: 960x480 px.
- Track perimeter: 2400 px = 1600 meters (scale: 1.5 px/meter).
- Vehicle speed: speedKmh (e.g. 40 to 100 km/h) -> v_ms = speedKmh / 3.6.
- Spline sample gives: truth.curvature (in 1/px -> convert to 1/meter: kappa_m = truth.curvature * 1.5).
- Frequency: 100 Hz (dt = 0.01s).

Requirements for Section 2:
Provide a clean JavaScript class or function `generateIMU(truth, speedMs, accelForwardMs2, shockActive, dt)` that:
1. Calculates true kinematics:
   - true yaw rate omega_z = speedMs * kappa_m
   - true centripetal acceleration a_y = speedMs * omega_z = speedMs^2 * kappa_m
   - true forward acceleration a_x = accelForwardMs2
   - true gravity vector [0, 0, 9.80665] m/s^2
2. Uses standard Box-Muller transform for true zero-mean Gaussian noise (accel sigma = 0.025 m/s^2, gyro sigma = 0.0015 rad/s).
3. Adds calibrated Bosch BMI270 MEMS biases:
   - acc bias: b_ax = 0.04 m/s^2, b_ay = 0.12 m/s^2, b_az = 0.02 m/s^2
   - gyro bias: b_gz = 0.016 rad/s (approx 0.9 deg/s drift)
   - slowly drifting bias walk (Gauss-Markov or random walk)
4. Shock impulse injection: if shockActive is true, injects 4.5g (44.1 m/s^2) vertical shock and 1.2g lateral impulse.
5. Returns `{ acc_body: Vec3, gyro_body: Vec3, truthKinematics: { omega_z, a_y, a_x, kappa_m } }`.

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
with open("scripts/section2_imu.js", "w", encoding="utf-8") as f:
    f.write(content)
print("Saved to scripts/section2_imu.js")
