import requests
import json

API_KEY = "sk-silvr-7b3d7fea700d2f9fe30d837408a2a2592b828dd26db4d1665ec990122d6600d4"

prompt = """
We are building Section 4 of our ISRO SIH Dead-Reckoning simulator:
\"Outage Trial Lifecycle, Scorecard & Resynchronization Controller\".

Context:
- Real-time simulation running at 100 Hz.
- Canvas: 960x480.
- Truth car, Classic car, IDR car.
- PX_PER_METER = 1.5.

Requirements for Section 4:
Provide a clean JavaScript `OutageTrialManager` class or controller that manages:
1. `startTrial(reason)`:
   - Called when GNSS is denied (user clicked CUT GNSS or tunnel ingress at p=0.28).
   - Resets trial metrics: elapsed time = 0, distance = 0, peakClassicErr = 0, peakIdrErr = 0.
   - Sets state `trialActive = true`.
2. `update(dt, speedMs, truthPos, classicPos, idrPos)`:
   - Advances elapsed time and distance traveled.
   - Computes real errors in meters:
     classicErr = hypot(classicPos.x - truthPos.x, classicPos.y - truthPos.y) / PX_PER_METER
     idrErr = hypot(idrPos.x - truthPos.x, idrPos.y - truthPos.y) / PX_PER_METER
   - Tracks peak errors and current drift percentage = (err / max(1, dist)) * 100.
   - Auto-completes trial if elapsed >= 30 seconds (or tunnel egress reached).
3. `completeTrial(classicSolver, truth)`:
   - Generates trial scorecard: `{ duration, distance, idrFinalErr, idrPct, classicFinalErr, classicPct, verdict }`.
   - Displays animated on-screen HUD scorecard / toast.
   - Automatically resyncs classical solver back to ground truth with flash effect so the simulation can seamlessly continue!
4. `drawTrialOverlay(ctx, canvasW, canvasH)`:
   - If trial is active, draws a sleek top-center timer pill: e.g. \"TUNNEL OUTAGE TRIAL: 18.4s / 30.0s | DIST: 320m\".
   - If trial recently completed, draws the scorecard banner for 5 seconds.

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
with open("scripts/section4_trial.js", "w", encoding="utf-8") as f:
    f.write(content)
print("Saved to scripts/section4_trial.js")
