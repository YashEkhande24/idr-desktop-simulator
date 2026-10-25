**Critique**

- **Root cause:** The track is open, but the solvers integrate unbounded progress. Ground truth wraps from 1 to 0 while the dead-reckoning estimates keep growing (p > 1), so the two diverge by a full lap. A closed loop and wrapped progress (`p = ((p % 1) + 1) % 1`) together fix this.
- **Smoothness:** Catmull-Rom splines and stitched arcs are only C1, so curvature jumps at the knots and creates spurious spikes in yaw-rate and IMU models. A periodic uniform cubic B-spline is C2, so position, heading and curvature are all continuous, including across the wrap.
- **Constant speed:** Raw spline parameters do not advance at constant speed. Mapping p through an arc-length table makes `p += v*dt/length` physically consistent. For errors, use `wrapDelta()` rather than `p1 - p0`, or every lap boundary will look like a huge jump.

```javascript
class ContinuousCircuit {
  constructor({ points, tunnel = [0.3, 0.7], samples = 4096 } = {}) {
    // Control polygon (clockwise on screen). B-spline lies inside its hull: x∈[50,910], y∈[70,410]
    this.ctrl = points || [
      [180, 70], [330, 70], [480, 70], [630, 70], [780, 70],   // top straightaway
      [890, 110], [910, 240], [890, 370],                      // right bend
      [780, 410], [660, 410], [580, 330], [480, 300],          // S-curve chicane
      [380, 330], [300, 410], [180, 410],
      [70, 370], [50, 240], [70, 110]                          // left bend
    ];
    this.tunnel = tunnel;
    this.S = samples;
    this._buildTable();
  }

  // Uniform periodic cubic B-spline: value, 1st and 2nd derivative wrt u
  _eval(u) {
    const c = this.ctrl, n = c.length;
    u = ((u % n) + n) % n;
    const i = Math.floor(u), t = u - i, t2 = t * t, t3 = t2 * t, m = 1 - t;
    const P = [c[(i - 1 + n) % n], c[i], c[(i + 1) % n], c[(i + 2) % n]];
    const b  = [m * m * m / 6, (3 * t3 - 6 * t2 + 4) / 6, (-3 * t3 + 3 * t2 + 3 * t + 1) / 6, t3 / 6];
    const d1 = [-m * m / 2, (3 * t2 - 4 * t) / 2, (-3 * t2 + 2 * t + 1) / 2, t2 / 2];
    const d2 = [m, 3 * t - 2, 1 - 3 * t, t];
    const r = { x: 0, y: 0, dx: 0, dy: 0, ddx: 0, ddy: 0 };
    for (let k = 0; k < 4; k++) {
      r.x += b[k] * P[k][0];   r.y += b[k] * P[k][1];
      r.dx += d1[k] * P[k][0]; r.dy += d1[k] * P[k][1];
      r.ddx += d2[k] * P[k][0]; r.ddy += d2[k] * P[k][1];
    }
    return r;
  }

  _buildTable() {
    const n = this.ctrl.length, S = this.S;
    this.U = new Float64Array(S + 1);
    this.L = new Float64Array(S + 1);
    this.X = new Float64Array(S + 1);
    this.Y = new Float64Array(S + 1);
    let prev = this._eval(0);
    this.X[0] = prev.x; this.Y[0] = prev.y;
    for (let k = 1; k <= S; k++) {
      const u = (k / S) * n, q = this._eval(u);
      this.U[k] = u;
      this.L[k] = this.L[k - 1] + Math.hypot(q.x - prev.x, q.y - prev.y);
      this.X[k] = q.x; this.Y[k] = q.y;
      prev = q;
    }
    this.length = this.L[S];
  }

  static wrap(p) { return ((p % 1) + 1) % 1; }

  // Shortest signed progress difference p1 - p0, in (-0.5, 0.5]
  static wrapDelta(p1, p0) { let d = ContinuousCircuit.wrap(p1 - p0); return d > 0.5 ? d