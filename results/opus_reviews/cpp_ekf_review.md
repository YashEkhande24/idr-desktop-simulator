# EKF3D Review: Critical Bugs and Fixes (Ranked by Severity)

## P0: Filter-breaking bugs

| # | Location | Bug | Consequence |
|---|---|---|---|
| 1 | `predict` | `x_(4) = vForward` overwrites a *state* that has covariance. `F(4,4)=1` keeps propagating `P(4,·)` as if `v` were integrated. | `updateTcnSpeed` is discarded on the next predict. `P` describes a different system than the one integrated, so the filter is inconsistent. |
| 2 | `updateCourse`, `updateCompass`, `updateMapHeading` | These are scalar updates that change only `x(3)` and `P(3,3)`. Cross-covariances `P(3,j)` are left untouched. | `P` loses positive semi-definiteness. Yaw corrections never move position. This leads to slow divergence or NaNs. |
| 3 | `updateCompass` | `R = P33·(1/w − 1)` derives R from the state covariance. The gain is then always `w`, and `P33 ← (1−w)·P33` on every call. | `P33` collapses geometrically to the 1e-6 floor, making yaw extremely overconfident. Every other heading source is then ignored. The 0.02 rad deadband also adds a bias of up to 1.1°. |
| 4 | `updateGnss` | `H` ignores the lever arm's dependence on yaw: `∂(R(ψ)·r)/∂ψ = [−a_y, a_x, 0]`. | A 1.25 m arm produces about 1 m of model error per 45° heading error. Yaw also never becomes observable from GNSS position. |
| 5 | `updateGnss` | The Mahalanobis gate uses only diagonal terms and is active only when `rFactor > 5`. The snap triggers on any single jump over 15 m with `hdop ≤ 4`. | A single multipath fix with a good HDOP teleports the filter. The gate rejects nothing when HDOP is good. |
| 6 | `applyStandstill`, `applyZaru` | These shrink `P` (position, and yaw at 0.98 per call) with no measurement. `P(4,4)=1e-4` is hard-set while its cross-terms remain. | Fabricated information makes the filter overconfident. Hard-setting the diagonal also breaks positive semi-definiteness. |
| 7 | `applyNhc` | Forces `v_z → 0`. On a slope the true value is `v_z = v·sinθ`. | The filter fights the baro climb rate on every hill and biases altitude. |
| 8 | `updateMapMatchingIterated` | Applies the same measurement twice with fabricated values. Because `H` is linear, a true IEKF is identical to a single EKF update. | Information is double-counted, so cross-track covariance becomes overconfident. |

## P1: Physics and robustness issues

- **Standstill accel bias:** `applyStandstill` learns `accelBiasX_` from raw accel with no `g·sinθ` compensation. `applyZacu` does compensate, so the two are inconsistent, and the bias absorbs road grade.
- **Course bootstrap:** it re-fires whenever `P33 ≥ 0.008`, which happens after about 4 s of GNSS outage. It then hard-snaps yaw without gating and without handling reverse driving (where course is offset by 180°). It also does not zero `P(3,·)`.
- **`velocity()` getter:** returns `v·cosψ` and ignores `cosθ`.
- **Missing guards:** there is no guard on `dt`, and `P` is never symmetrized.
- **Unused inputs:** `accelBiasX_` and `latitudeDeg_` are never used. No magnetic declination is applied.

---

## Fixes

### Header additions (`private:`)

```cpp
using RowVector6d = Eigen::Matrix<double, 1, 6>;
bool scalarUpdate(const RowVector6d& H, double innov, double R, double nisGate = -1.0);
void conditionCovariance();
static double wrapPi(double a) { return std::remainder(a, 2.0 * PI); }

bool posInit_ = false;
bool yawInit_ = false;
int  gnssRejects_ = 0;
```

Also fix the getter:

```cpp
Vec3 velocity() const {
    double vH = x_(4) * std::cos(pitch_);
    return {vH * std::cos(x_(3)), vH * std::sin(x_(3)), x_(5)};
}
```

In `reset()`, add: `posInit_ = false; yawInit_ = false; gnssRejects_ = 0;`.

### Shared Joseph update and conditioning (fixes #2, #6)

Every scalar update below routes through this helper, so the full `P` row and column are always updated.

```cpp
bool Ekf3D::scalarUpdate(const RowVector6d& H, double innov, double R, double nisGate) {
    const Vector6d PHt = P_ * H.transpose();
    const double S = (H * PHt)(0) + R;
    if (!(S > 1e-12) || !std::isfinite(innov)) return false;
    if (nisGate > 0.0 && innov * innov / S > nisGate) return false;
    const Vector6d K = PHt / S;
    x_ += K * innov;
    const Matrix6d IKH = Matrix6d::Identity() - K * H;
    P_ = IKH * P_ * IKH.transpose() + R * (K * K.transpose());
    conditionCovariance();
    return true;
}

void Ekf3D::conditionCovariance() {
    x_(3) = wrapPi(x_(3));
    P_ = 