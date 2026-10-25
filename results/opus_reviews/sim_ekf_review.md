# EKF review: top 5 defects and fixes

Bugs are ranked by impact on filter consistency. Each fix is a drop-in replacement.

---

## 1. Pitch sign convention conflict (kinematic error)

The code uses two opposite pitch conventions:

| Code path | Implied forward axis | Positive pitch |
|---|---|---|
| `update_speed` Jacobian `[-sθcψ, -sθsψ, cθ]` → `forward_axis` = `[cθcψ, cθsψ, +sθ]` | `+sθ` | nose **up** |
| `update_tilt`: `θ = -asin(ax/g)` and standard `R = Rz·Ry·Rx` → `R[:,0]` = `[cθcψ, cθsψ, −sθ]` | `−sθ` | nose **down** |

On any slope, the speed update and the tilt update push pitch in opposite directions. The speed Jacobian `h[0,7]` also has the wrong sign relative to the propagation.

**Fix:** derive the forward axis and its Jacobian from the same `rot_body_to_world` used in propagation. Use central differences for accuracy.

```python
def _axis_and_jac(self, col: int, eps: float = 1e-6):
    """World-frame body axis `col` and d(axis)/d(roll,pitch,yaw), consistent with rot_body_to_world."""
    e = self.x[A_].copy()
    axis = rot_body_to_world(*e)[:, col]
    jac = np.empty((3, 3))
    for i in range(3):
        ep, em = e.copy(), e.copy()
        ep[i] += eps; em[i] -= eps
        jac[:, i] = (rot_body_to_world(*ep)[:, col] - rot_body_to_world(*em)[:, col]) / (2 * eps)
    return axis, jac

def update_speed(self, v_fwd: float, sigma: float = 0.6) -> None:
    f_hat, jf = self._axis_and_jac(0)
    v = self.x[V_]
    h = np.zeros((1, N))
    h[0, V_] = f_hat
    h[0, A_] = v @ jf
    self._update(h, np.array([v_fwd - float(v @ f_hat)]), np.array([[sigma ** 2]]))
```

Add a guard in `__init__` so the convention can never drift again:

```python
assert np.allclose(rot_body_to_world(0.0, 0.1, 0.0) @ [0, 0, 9.81] / 9.81 @ [1, 0, 0],
                   -np.sin(0.1)), "update_tilt pitch formula inconsistent with rot_body_to_world"
```

---

## 2. Missing attitude self-coupling in F (covariance error)

`f[A_, A_]` is left as identity. However, `ė = E(φ,θ)·ω` depends on roll and pitch, so `∂ė/∂(φ,θ)·dt` is missing. During turns on banked or sloped roads, the term `ωz·sinφ/cosθ` couples roll and pitch error into yaw. Without it, yaw covariance is underestimated and the roll→yaw correlation needed by course and NHC updates is lost.

```python
# in predict(), after computing edot
d_edot = np.zeros((3, 3))
for i in range(2):                       # yaw does not enter E(roll, pitch)
    ep, em = [roll, pitch], [roll, pitch]
    ep[i] += eps; em[i] -= eps
    d_edot[:, i] = (euler_rates(*ep, gyro) - euler_rates(*em, gyro)) / (2 * eps)

f[A_, A_] = np.eye(3) + d_edot * dt
```

---

## 3. Gyro z-bias estimated outside the filter (inconsistent estimator)

`gyro_bias_z` is corrected by two ad-hoc integral loops (`update_course` and `standstill`), but it is not part of the state. This causes several problems:

- **Double correction.** The EKF already corrects yaw with `resid`, and then the same pre-update `resid` is integrated into the bias again.
- **Rate-dependent gain.** The gain units are 1/s, but it is applied per call, so loop bandwidth changes with GNSS rate. The standstill loop runs at 100 Hz × 0.01, a 1 s time constant on raw gyro noise.
- **Optimistic covariance.** `P` never sees bias uncertainty, so yaw covariance becomes overconfident during GNSS outages.
- **Course is not yaw.** Doppler measures the velocity heading, which differs from yaw by sideslip. GNSS COG is usually clockwise from north; ENU yaw is counter-clockwise from east, so `ψ = π/2 − COG`.

**Fix:** augment the state to 10 and measure course as `atan2(vy, vx)`.

```python
N = 10
B_ = 9                                     # gyro z bias [rad/s]
# __init__:  self.P = np.diag([4,4,4, 1,1,0.5, 0.02,0.02,0.05, 1e-4]); self.sigma_bias_rw = 1e-4

# predict():
gyro[2] -= self.x[B_]                      # remove self.gyro_bias_z and the standstill loop
j_euler = euler_rate_jacobian(roll, pitch)
f[A_, B_] = -j_euler[:, 2] * dt
q[B_, B_] = self.sigma_bias_rw ** 2 * dt

def update_zero_rate(self, gyro_z_raw: float, sigma: float = 0.003) -> None:
    """Standstill: raw z-rate observes the bias directly."""
    h = np.zeros((1, N)); h[0, B_] = 1.0
    self._update(h, np.array([gyro_z_raw - self.x[B_]]), np.array([[sigma ** 2]]))

def update_course(self, course_enu: float, speed: float, sigma_deg: float = 1.5,
                  sigma_speed: float = 0.15) -> None:
    """course_enu = pi/2 - COG if receiver reports COG clockwise from north."""
    vx, vy = self.x[3], self.x[4]
    vh2 = vx * vx + vy * vy
    if speed < 1.5 or vh2 < 1.0:
        return
    h = np.zeros((1, N))
    h[0, 3], h[0, 4] = -vy / vh2, vx / vh2
    resid = float(wrap_angle(course_enu - np.arctan2(vy, vx)))
    self._update(h, np.array([resid]), np.array([[np.radians(sigma_deg) ** 2]]))
    self.update_speed(speed, sigma=sigma_speed)
```

Yaw and bias are then corrected through the NHC lateral constraint and the P cross-terms, with correct gains.

---

## 4. NHC is not body-frame, and the climb-rate pseudo-measurement is overconfident and correlated

**Lateral constraint ignores roll and pitch.** It uses a yaw-only lateral axis, but on banked roads the body y-axis has a vertical component.

**Climb-rate noise is underestimated by about 13×.** The climb rate comes from differenced baro at 10 Hz:
- Raw variance: `2σ²/dt² = 2·0.45²/0.01 = 40.5`.
- After EMA with α = 0.25, the steady-state variance factor is `α/(2−α) = 0.143`, giving `σ ≈ 2.4 m/s`.
- The code uses `sigma_nhc_vert = 0.18`.

**The climb-rate measurement is correlated with the baro z update.** The same baro samples feed both, so they are effectively double-counted, and the EMA error is time-correlated.

**Fix:** constrain body-frame lateral and vertical velocity to zero. If the baro climb rate is kept, use its honest variance.

```python
def update_nhc(self, sigma_lat: float | None = None, sigma_vert: float | None = None) -> None:
    sigma_lat = self.sigma_nhc_lat if sigma_lat is None else sigma_lat
    sigma_vert = 0.1 if sigma_vert is None else sigma_vert       # body-z slip, not climb rate
    v = self.x[V_]
    h = np.zeros((2, N)); y = np.zeros(2)
    for row, col in enumerate((1, 2)):                           # body y, body z
        axis, jac = self._axis_and_jac(col)
        h[row, V_] = axis
        h[row, A_] = v @ jac
        y[row] = -float(v @ axis)
    self._update(h, y, np.diag([sigma_lat ** 2, sigma_vert ** 2]))

# If the baro climb rate is still used anywhere, derive its variance:
#   a = 0.25; var_cr = a / (2 - a) * 2 * sigma_baro**2 / dt_baro**2   (≈ 5.8 m²/s²)
```

---

## 5. GNSS re-acquisition is ineffective and gating is bypassed

**Recovery is too weak.** After 4 rejects, only `P_pos` gets `+25 m²`. With a 50 m divergence, `d² ≈ 2500/(4+25+8) ≈ 67`, which is still above the gate of 25. Recovery therefore takes many cycles.

**Recovery is incomplete.** Velocity and yaw, which usually caused the divergence, are not inflated, so the filter re-diverges.

**Gating is bypassed at high HDOP.** `lam ≥ 0.98` skips the gate entirely, so gross outliers at high HDOP enter unchecked. They are de-weighted by R ≈ 5000 m², but nothing ever tests them.

**Fix:**

```python
def update_gnss(self, gnss_pos, hdop: float) -> bool