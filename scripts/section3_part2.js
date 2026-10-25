```javascript
update(acc_body, gyro_body, v_neural, isShock, isOutage, gnssPosPx, isZupt, circuit, dt) {
  // Stage 1: Attitude update
  const gyroCorrected = gyro_body.z - this.b_est;
  this.yaw = wrapAngle(this.yaw + gyroCorrected * dt);
  if (isZupt) this.b_est += this.K.BIAS_ZUPT * gyro_body.z;
  else this.b_est *= this.K.BIAS_DECAY;

  // Stage 2: Spectral Vibration Gate
  const varAcc = this._accVariance(acc_body);
  this.shockRejected = isShock || (varAcc > this.K.VAR_GATE);

  // Stage 3 & 4: Neural Speed Prior + NHC + ZUPT
  if (isZupt) {
    this.v_tcn = 0;
    this.vel.x = 0;
    this.vel.y = 0;
    this.P_cov = this.K.P_ZUPT;
  } else if (!this.shockRejected) {
    this.v_tcn += this.K.TCN_ALPHA * (v_neural - this.v_tcn);
    this.vel.x = Math.cos(this.yaw) * this.v_tcn;
    this.vel.y = Math.sin(this.yaw) * this.v_tcn;
  }
  this.pos.x += this.vel.x * PX_PER_METER * dt;
  this.pos.y += this.vel.y * PX_PER_METER * dt;

  // Stage 5: Map Snapping & GNSS Fusion
  if (!isOutage && gnssPosPx) {
    this.lastInnovation.x = gnssPosPx.x - this.pos.x;
    this.lastInnovation.y = gnssPosPx.y - this.pos.y;
    this.pos.x += this.lastInnovation.x * this.K.GNSS_GAIN;
    this.pos.y += this.lastInnovation.y * this.K.GNSS_GAIN;
    this.P_cov = this.K.P_GNSS;
  } else {
    if (circuit) {
      const snap = circuit.project(this.pos);
      this.pos.x += (snap.pos.x - this.pos.x) * this.K.SNAP_GAIN;
      this.pos.y += (snap.pos.y - this.pos.y) * this.K.SNAP_GAIN;
    }
    this.P_cov = Math.min(this.K.P_MAX, this.P_cov + this.K.P_RATE * dt);
  }
}
```

```javascript
function drawOffscreenRadar(ctx, carX, carY, carHeading, label, canvasW, canvasH, color = '#ff1744') {
  const margin = 28;
  if (carX >= margin && carX <= canvasW - margin &&
      carY >= margin && carY <= canvasH - margin) return false;

  // Ray from canvas center to car, clipped to inset border rectangle
  const cx = canvasW / 2, cy = canvasH / 2;
  const dx = carX - cx, dy = carY - cy;
  const halfW = cx - margin, halfH = cy - margin;
  const tx = dx !== 0 ? halfW / Math.abs(dx) : Infinity;
  const ty = dy !== 0 ? halfH / Math.abs(dy) : Infinity;
  const t = Math.min(tx, ty, 1);
  const clampedX = cx + dx * t;
  const clampedY = cy + dy * t;

  const distM = Math.hypot(carX - clampedX, carY - clampedY) / PX_PER_METER;
  const angle = Math.atan2(carY - clampedY, carX - clampedX);
  const pulse = 0.5 + 0.5 * Math.sin(performance.now() * 0.008);

  ctx.save();

  // Glowing halo
  const haloR = 14 + pulse * 6;
  const grad = ctx.createRadialGradient(clampedX, clampedY, 2, clampedX, clampedY, haloR);
  grad.addColorStop(0, color);
  grad.addColorStop(1, 'rgba(0,0,0,0)');
  ctx.globalAlpha = 0.35 + 0.35 * pulse;
  ctx.fillStyle = grad;
  ctx.beginPath();
  ctx.arc(clampedX, clampedY, haloR, 0, Math.PI * 2);
  ctx.fill();

  // Radar chevron pointing toward the car
  ctx.globalAlpha = 1;
  ctx.translate(clampedX, clampedY);
  ctx.rotate(angle);
  ctx.shadowColor = color;
  ctx.shadowBlur = 10 + pulse * 10;
  ctx.fillStyle = color;
  ctx.beginPath();
  ctx.moveTo(12, 0);
  ctx.lineTo(-8, -9);
  ctx.lineTo(-3, 0);
  ctx.lineTo(-8, 9);
  ctx.closePath();
  ctx.fill();

  // Car heading tick
  ctx.rotate(carHeading - angle);
  ctx.shadowBlur = 0;
  ctx.strokeStyle = '#ffffff';
  ctx.lineWidth = 1.5;
  ctx.beginPath();
  ctx.moveTo(0, 0);
  ctx.lineTo(8, 0);
  ctx.stroke();
  ctx.setTransform(1, 0, 0, 1, 0, 0);

  // HUD badge, offset inward from the edge
  const text = `${label}: +${distM.toFixed(0)}m [OFF-SCREEN]`;
  ctx.font = '600 11px "JetBrains Mono", "Consolas", monospace';
  const padX = 7, boxH = 18;
  const boxW = ctx.measureText(text).width + padX * 2;
  const inward = 26;
  let bx = clampedX - Math.cos(angle) * inward - boxW / 2;
  let by = clampedY - Math.sin(angle) * inward - boxH / 2;
  bx = Math.max(4, Math.min(canvasW - boxW - 4, bx));
  by = Math.max(4, Math.min(canvasH - boxH - 4, by));

  ctx.fillStyle = 'rgba(8, 12, 20, 0.85)';
  ctx.strokeStyle = color;
  ctx.lineWidth = 1;
  ctx.shadowColor = color;
  ctx.shadowBlur = 6 + pulse * 6;
  ctx.beginPath();
  if (ctx.roundRect) ctx.roundRect(bx, by, boxW, boxH, 4);
  else ctx.rect(bx, by, boxW, boxH);
  ctx.fill();
  ctx.stroke();

  ctx.shadowBlur = 0;
  ctx.fillStyle = color;
  ctx.fillRect(bx, by + 3, 2, boxH - 6);
  ctx.fillStyle = '#e8f1ff';
  ctx.textAlign = 'left';
  ctx.textBaseline = 'middle';
  ctx.fillText(text, bx + padX, by + boxH / 2 + 0.5);

  ctx.restore();
  return true;
}
```