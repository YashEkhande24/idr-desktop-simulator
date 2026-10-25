import os
import sys
from opus_section_consultant import query_opus

PROMPT = """
We are building the genuine physics simulation for the ISRO SIH Dead Reckoning interactive web simulator.
Canvas dimensions: 960x480 px.
Physical scale: 1 meter = 1.5 pixels (track perimeter ~ 2400 px = 1600 m).
Simulation frequency: 100 Hz (dt = 0.01s).

We need you to provide the complete, mathematically rigorous, and production-tested JavaScript implementation for the core physics engine:

1. `ContinuousCircuit` class completion:
   - Evaluates periodic uniform cubic B-spline (C2 continuous curvature and heading).
   - Arc-length parameterization lookup `sample(p)`: maps p in [0, 1) to `{pos: Vec3, heading: number, curvature: number, inTunnel: boolean}`.
   - Fast projection `project(pos)`: snaps arbitrary canvas pos to nearest spline point with sub-pixel precision.
   - `wrapDelta(p1, p0)`: shortest signed distance along loop in (-0.5, 0.5].

2. Realistic MEMS IMU Generator (Bosch BMI270 specifications):
   - Computes ground truth body kinematics: forward acceleration, centripetal accel (v^2 * kappa), true yaw rate (v * kappa).
   - Corrupts with realistic automotive MEMS bias: acc lateral bias b_ay = 0.12 m/s^2, gyro bias b_gz = 0.016 rad/s (approx 0.9 deg/s), white Gaussian noise (acc: 120 ug/sqrt(Hz), gyro: 0.007 dps/sqrt(Hz)).
   - Supports pothole shock impulse (4.5g spike on z and y axis).

3. The Two Solvers:
   A. Classical Strapdown INS (Baseline):
      - Integrates raw gyro into yaw (uncompensated bias).
      - Rotates body acceleration to world frame and subtracts gravity.
      - Double integrates to update velocity and position in pixels.
      - Displays genuine quadratic divergence.
   B. IDR-Navigator 5-Stage Cascade (Proposed System):
      - Stage 1: Attitude observer with gyro bias tracking.
      - Stage 2: Spectral Vibration Gating (detects shock impulse when Var(a) > 1.2g^2 and freezes velocity update).
      - Stage 3: Neural TCN Speed Prior (forward velocity v_tcn from neural network).
      - Stage 4: Non-Holonomic Constraints (NHC: v_lateral = 0, v_vertical = 0) and ZUPT lock (v = 0 when standstill).
      - Stage 5: Soft Map-Snapping Vector Projection onto circuit.

4. Off-Screen Radar Beacon:
   - Function `drawOffscreenRadar(ctx, carX, carY, carHeading, label, canvasW, canvasH)`:
     When classical car diverges off the visible canvas, draws a sleek pulsing radar indicator at the exact boundary intersection point, showing a directed chevron and distance text in meters (e.g. "CLASSICAL INS: +142m [OFF-SCREEN]").

5. Outage Trial Lifecycle:
   - Starts when GNSS is denied (button or tunnel ingress).
   - Tracks outage elapsed time and distance traveled.
   - When GNSS is restored (or trial reaches 35s), logs an official trial score card (IDR Error vs Classical Error) and provides an option / auto-resync for the classical car back to ground truth so it doesn't wander infinitely.

Please output the clean, well-documented JavaScript classes and functions ready for direct drop-in integration into `simulator.js`.
"""

if __name__ == "__main__":
    print("Executing Opus 5.5 consultation with mandatory thinking...")
    result = query_opus(
        "Full Simulator Physics & Solvers",
        PROMPT,
        "scripts/opus_full_sim_solution.md",
        max_tokens=3200
    )
    if result:
        print("\nSuccess! Opus 5.5 provided solution.")
    else:
        print("\nFailed to get Opus 5.5 response.")
