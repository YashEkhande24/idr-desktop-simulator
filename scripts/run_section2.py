import requests
import json

API_KEY = "sk-silvr-7b3d7fea700d2f9fe30d837408a2a2592b828dd26db4d1665ec990122d6600d4"
URL = "https://api.silvrai.net/v1/messages"

prompt = """
We are refining the physics simulation in JavaScript for our ISRO SIH Dead Reckoning simulator.
Canvas size is 960x480 pixels.
We have:
1. ContinuousCircuit periodic cubic B-spline (track length approx 2400 pixels).
2. Ground truth car moving along track at speed_kmh.
3. Realistic MEMS IMU generator:
   - acc_body: forward acceleration + centripetal (v^2*kappa) + gravity (9.81 m/s^2) + bias (0.12 m/s^2) + noise
   - gyro_body: yaw_rate (v*kappa) + bias (0.016 rad/s) + noise
   - Pothole shock: 4.5g impulse spike

We need exact JavaScript implementations for:
1. Scale Factor: How to map physical meters (e.g. 15-25 m/s) to canvas pixels so drift divergence is physically accurate and visible.
2. Classical Dead Reckoning Solver update step: attitude propagation, gravity removal in world frame, double integration.
3. IDR-Navigator 5-Stage Estimator update step: vibration gate check (reject if var > 1.2g^2), forward velocity update from neural speed, Non-Holonomic Constraint (lateral velocity = 0), ZUPT lock if standstill, soft map-snapping projection.
4. Off-Screen Radar Beacon: Function `drawOffscreenRadar(ctx, carX, carY, carHeading, label, canvasW, canvasH)` that draws a pulsing chevron/arrow at the canvas border when the classical car diverges off-screen, displaying its distance.
5. Outage Trial Lifecycle: Starts on GNSS cut; tracks outage distance and time; when trial ends (or restored), records trial report (IDR drift % vs Classical drift %) and resyncs classical car to ground truth so it doesn't stay lost forever.

Provide clean, modular, production JavaScript code with concise explanations.
"""

headers = {
    "x-api-key": API_KEY,
    "anthropic-version": "2023-06-01",
    "content-type": "application/json"
}

payload = {
    "model": "claude-sonnet-5-5",
    "max_tokens": 2000,
    "system": "You are Claude Sonnet 5.5, an expert in inertial navigation, Kalman filtering, and HTML5 canvas physics simulation. Provide clean, production JavaScript code.",
    "messages": [
        {"role": "user", "content": prompt}
    ]
}

print("Calling native Anthropic endpoint for Section 2 & 3...")
r = requests.post(URL, headers=headers, json=payload, timeout=60)
data = r.json()
print("Status:", r.status_code)
text_parts = [c.get("text", "") for c in data.get("content", []) if c.get("type") == "text"]
response_text = "".join(text_parts)
print("Output text length:", len(response_text))

usage = data.get("usage", {})
in_tok = usage.get("input_tokens", 0)
out_tok = usage.get("output_tokens", 0)
cost = (in_tok * 2.0 / 1e6) + (out_tok * 10.0 / 1e6)
print(f"Tokens: in={in_tok}, out={out_tok} | Cost: ${cost:.6f}")

with open("scripts/section2_claude_solution.md", "w", encoding="utf-8") as f:
    f.write(response_text)
print("Saved to scripts/section2_claude_solution.md")
