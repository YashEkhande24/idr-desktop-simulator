```javascript
sample(p) {
  p = ((p % 1) + 1) % 1;
  const u = this._pToU(p);
  const r = this._eval(u);
  const speed = Math.hypot(r.dx, r.dy);
  const kappa = speed > 1e-12 ? (r.dx * r.ddy - r.dy * r.ddx) / (speed * speed * speed) : 0;
  return {
    pos: new Vec3(r.x, r.y, 0),
    heading: Math.atan2(r.dy, r.dx),
    curvature: kappa,
    inTunnel: p >= 0.28 && p <= 0.76,
    p
  };
}

project(pos) {
  const { X, Y, L } = this;
  const S = X.length - 1, n = this.ctrl.length;

  // Coarse scan over the sample table
  let bestI = 0, bestD2 = Infinity;
  for (let i = 0; i < S; i++) {
    const dx = X[i] - pos.x, dy = Y[i] - pos.y, d2 = dx * dx + dy * dy;
    if (d2 < bestD2) { bestD2 = d2; bestI = i; }
  }

  // Golden-section refinement in u around the best sample
  const wrapU = u => ((u % n) + n) % n;
  const dist2 = u => {
    const r = this._eval(wrapU(u));
    const dx = r.x - pos.x, dy = r.y - pos.y;
    return dx * dx + dy * dy;
  };
  const du = n / S, G = 0.6180339887498949;
  let a = bestI * du - du, b = bestI * du + du;
  let c = b - G * (b - a), d = a + G * (b - a);
  let fc = dist2(c), fd = dist2(d);
  for (let k = 0; k < 40 && b - a > 1e-9; k++) {
    if (fc < fd) { b = d; d = c; fd = fc; c = b - G * (b - a); fc = dist2(c); }
    else         { a = c; c = d; fc = fd; d = a + G * (b - a); fd = dist2(d); }
  }
  const u = wrapU((a + b) / 2);
  const r = this._eval(u);

  // Map u -> p by interpolating the cumulative arc-length table
  const t = (u / n) * S, i = Math.min(Math.floor(t), S - 1), f = t - i;
  const p = ((L[i] + (L[i + 1] - L[i]) * f) / this.length) % 1;

  return {
    pos: new Vec3(r.x, r.y, 0),
    p,
    distance: Math.hypot(r.x - pos.x, r.y - pos.y)
  };
}
```