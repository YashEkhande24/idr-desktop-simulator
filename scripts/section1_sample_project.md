# ContinuousCircuit: `wrapDelta`, `sample`, `project`

I don't have the Section 1 code, so the implementation below relies on these conventions. Adjust them if your class differs:

- **Closed spline.** The curve has `n = this.ctrl.length` segments, and the parameter is `u ∈ [0, n)`.
- **Arc-length table.** `this.L[i]` is the cumulative arc length at `u = i · n / S`. So `L[0] = 0`, `L[S] = this.length`, and `u = n` wraps back to `u = 0`.
- **Evaluator.** `this._eval(u)` returns `{ x, y, dx, dy, ddx, ddy }`, the position and its first and second derivatives with respect to `u`.
- **Tunnel.** `this.tunnel = [p0, p1]` uses normalized progress. If `p0 > p1`, the tunnel crosses the start/finish line.
- **Vec3.** `Vec3` is constructed as `new Vec3(x, y, z)`, with the circuit lying in the x/y plane (`z = 0`). If your track lies in x/z, change the three `new Vec3(...)` calls.

```js
// ─── Progress helpers ────────────────────────────────────────────────────────

/**
 * Shortest signed progress difference p1 - p0, wrapped into (-0.5, 0.5].
 */
wrapDelta(p1, p0) {
  const d = p1 - p0;
  return d - Math.ceil(d - 0.5);
}

/** Spline parameter u ∈ [0, n) → normalized progress p ∈ [0, 1). */
_uToP(u) {
  const L = this.L, S = L.length - 1, n = this.ctrl.length;
  let x = (u / n) * S;
  x -= Math.floor(x / S) * S;                // wrap into [0, S)
  const i = Math.min(x | 0, S - 1);
  return (L[i] + (x - i) * (L[i + 1] - L[i])) / this.length;
}

/** Normalized progress p → spline parameter u ∈ [0, n). */
_pToU(p) {
  const L = this.L, S = L.length - 1;
  p -= Math.floor(p);                        // wrap into [0, 1)
  const s = p * this.length;

  // Largest i in [0, S-1] with L[i] <= s
  let lo = 0, hi = S - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (L[mid] <= s) lo = mid; else hi = mid - 1;
  }

  const seg = L[lo + 1] - L[lo];
  const t = seg > 0 ? (s - L[lo]) / seg : 0;
  return (lo + t) * (this.ctrl.length / S);
}

_inTunnel(p) {
  const t = this.tunnel;
  if (!t) return false;
  const [a, b] = t;
  return a <= b ? (p >= a && p <= b)
                : (p >= a || p <= b);        // tunnel spans the start line
}

// ─── Sampling ────────────────────────────────────────────────────────────────

/**
 * Sample the circuit at normalized progress p ∈ [0, 1). Out-of-range p is wrapped.
 * @returns {{ pos: Vec3, heading: number, kappa: number, inTunnel: boolean, u: number, p: number }}
 */
sample(p) {
  p -=