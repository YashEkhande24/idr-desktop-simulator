/**
 * IDR-NAVIGATOR LIVE IN-BROWSER SIMULATOR (LIGHT THEME)
 * Editorial styling designed by Gemini 4 Argon
 * Side-by-Side Physics Comparison: IDR Causal SE-TCN vs Classical Open-Loop INS
 */

(function () {
  const canvas = document.getElementById('simCanvas');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');

  // Simulation State
  const state = {
    running: true,
    isOutage: false,
    outageStartTime: 0,
    outageDuration: 0,
    isZupt: false,
    shockTimer: 0,
    time: 0,
    speed: 54.0, // km/h
    nominalSpeed: 54.0,
    totalDistance: 0,
    hdop: 0.8,
    jerkVariance: 12.0,
    
    // Vehicles
    roadProgress: 0.05,
    
    // Emerald Vehicle (IDR)
    idr: {
      x: 0,
      y: 0,
      heading: 0,
      drift: 0.2, // meters
      trail: []
    },

    // Rust Vehicle (Classical INS)
    classic: {
      x: 0,
      y: 0,
      heading: 0,
      drift: 0.0, // meters
      accBiasY: 0.08,
      gyroBias: 0.015,
      driftAngle: 0,
      trail: []
    }
  };

  // Define S-curve Highway Waypoints
  function getRoadPoint(t) {
    const w = canvas.width;
    const h = canvas.height;
    
    const p = t % 1.0;
    const x = 50 + p * (w - 100);
    
    // Smooth S-curve equation
    const y = (h / 2) + Math.sin(p * Math.PI * 2.8) * 110 + Math.cos(p * Math.PI * 1.4) * 35;
    
    // Derivative for tangent heading
    const dt = 0.002;
    const pNext = (t + dt) % 1.0;
    const xNext = 50 + pNext * (w - 100);
    const yNext = (h / 2) + Math.sin(pNext * Math.PI * 2.8) * 110 + Math.cos(pNext * Math.PI * 1.4) * 35;
    const heading = Math.atan2(yNext - y, xNext - x);

    return { x, y, heading };
  }

  // Tunnel Region on Track: from p = 0.35 to p = 0.78
  const TUNNEL_START = 0.35;
  const TUNNEL_END = 0.78;

  // DOM Elements
  const speedVal = document.getElementById('simSpeedVal');
  const outageTimeVal = document.getElementById('simOutageTimeVal');
  const classicDriftVal = document.getElementById('simClassicDriftVal');
  const idrDriftVal = document.getElementById('simIdrDriftVal');
  const btnOutage = document.getElementById('btnSimOutage');

  // Trigger Outage
  window.toggleSimOutage = function () {
    state.isOutage = !state.isOutage;
    if (state.isOutage) {
      state.outageStartTime = performance.now();
      if (btnOutage) {
        btnOutage.style.backgroundColor = 'var(--accent-emerald)';
        btnOutage.style.borderColor = 'var(--accent-emerald)';
        btnOutage.innerHTML = `<span>RESTORE GNSS SIGNALS</span>`;
      }
    } else {
      if (btnOutage) {
        btnOutage.style.backgroundColor = 'var(--accent-rust)';
        btnOutage.style.borderColor = 'var(--accent-rust)';
        btnOutage.innerHTML = `<span>CUT GNSS SIGNAL (TUNNEL OUTAGE)</span>`;
      }
      state.idr.drift = 0.2;
    }
  };

  // Trigger Shock
  window.injectSimShock = function () {
    state.shockTimer = 45;
  };

  // Toggle ZUPT (Red light)
  window.toggleSimZupt = function () {
    state.isZupt = !state.isZupt;
    const btn = document.getElementById('btnSimZupt');
    if (btn) {
      if (state.isZupt) {
        btn.style.backgroundColor = 'var(--accent-rust)';
        btn.style.borderColor = 'var(--accent-rust)';
        btn.style.color = '#fff';
        btn.innerHTML = `<span>STANDSTILL LOCKED (ZUPT ON)</span>`;
      } else {
        btn.style.backgroundColor = 'var(--bg-surface)';
        btn.style.borderColor = 'var(--border-strong)';
        btn.style.color = 'var(--text-secondary)';
        btn.innerHTML = `<span>RED LIGHT (ZUPT)</span>`;
      }
    }
  };

  // Reset Simulator
  window.resetSimulator = function () {
    state.isOutage = false;
    state.isZupt = false;
    state.roadProgress = 0.05;
    state.totalDistance = 0;
    state.outageDuration = 0;
    state.idr.trail = [];
    state.classic.trail = [];
    state.idr.drift = 0.2;
    state.classic.drift = 0.0;
    state.classic.driftAngle = 0;
    state.shockTimer = 0;

    if (btnOutage) {
      btnOutage.style.backgroundColor = 'var(--accent-rust)';
      btnOutage.style.borderColor = 'var(--accent-rust)';
      btnOutage.innerHTML = `<span>CUT GNSS SIGNAL (TUNNEL OUTAGE)</span>`;
    }
  };

  // Main Physics Update Loop
  function updatePhysics() {
    const dt = 1 / 60;
    state.time += dt;

    if (state.isZupt) {
      state.speed = Math.max(0, state.speed - 90 * dt);
    } else {
      state.speed = Math.min(state.nominalSpeed, state.speed + 45 * dt);
    }

    const currentSpeedMs = (state.speed * 1000) / 3600;
    state.totalDistance += currentSpeedMs * dt;

    const trackAdvance = (currentSpeedMs * dt) / 520;
    state.roadProgress = (state.roadProgress + trackAdvance) % 1.0;

    const inTunnelZone = state.roadProgress >= TUNNEL_START && state.roadProgress <= TUNNEL_END;
    const effectiveOutage = state.isOutage || inTunnelZone;

    if (effectiveOutage) {
      state.hdop = Math.min(38.5, state.hdop + 3.5 * dt);
      state.outageDuration += dt;
    } else {
      state.hdop = Math.max(0.8, state.hdop - 8.0 * dt);
      state.outageDuration = Math.max(0, state.outageDuration - 2.0 * dt);
    }

    if (state.shockTimer > 0) {
      state.shockTimer--;
      state.jerkVariance = 520 + Math.random() * 80;
    } else {
      state.jerkVariance = 12 + Math.random() * 4;
    }

    const roadPt = getRoadPoint(state.roadProgress);

    // IDR Vehicle: Follows road centerline with bounded error
    state.idr.x = roadPt.x;
    state.idr.y = roadPt.y;
    state.idr.heading = roadPt.heading;

    if (effectiveOutage) {
      state.idr.drift = Math.min(1.8, 0.2 + (state.outageDuration * 0.08));
    } else {
      state.idr.drift = 0.2;
    }

    // Classical INS Vehicle: Diverges quadratically in outage!
    if (effectiveOutage) {
      state.classic.driftAngle += state.classic.gyroBias * dt * 2.5;
      const divergenceFactor = Math.pow(state.outageDuration * 1.6, 2.2);
      state.classic.drift = divergenceFactor * 4.5;

      const perpAngle = roadPt.heading + Math.PI / 2 + state.classic.driftAngle;
      state.classic.x = roadPt.x + Math.cos(perpAngle) * state.classic.drift;
      state.classic.y = roadPt.y + Math.sin(perpAngle) * state.classic.drift;
      state.classic.heading = roadPt.heading + state.classic.driftAngle;
    } else {
      state.classic.x = roadPt.x;
      state.classic.y = roadPt.y;
      state.classic.heading = roadPt.heading;
      state.classic.drift = 0.0;
      state.classic.driftAngle = 0;
    }

    // Record breadcrumbs
    if (Math.floor(state.time * 60) % 3 === 0) {
      state.idr.trail.push({ x: state.idr.x, y: state.idr.y });
      state.classic.trail.push({ x: state.classic.x, y: state.classic.y });

      if (state.idr.trail.length > 250) state.idr.trail.shift();
      if (state.classic.trail.length > 250) state.classic.trail.shift();
    }

    // Update Telemetry UI
    if (speedVal) speedVal.textContent = state.speed.toFixed(1) + ' km/h';

    if (outageTimeVal) {
      const mins = Math.floor(state.outageDuration / 60).toString().padStart(2, '0');
      const secs = Math.floor(state.outageDuration % 60).toString().padStart(2, '0');
      outageTimeVal.textContent = `${mins}:${secs}`;
    }

    if (classicDriftVal) {
      const pct = state.totalDistance > 0 ? ((state.classic.drift / state.totalDistance) * 100).toFixed(1) : '0';
      classicDriftVal.textContent = `${state.classic.drift.toFixed(1)} m (${pct}%)`;
    }

    if (idrDriftVal) {
      const pct = state.totalDistance > 0 ? ((state.idr.drift / state.totalDistance) * 100).toFixed(2) : '0';
      idrDriftVal.textContent = `${state.idr.drift.toFixed(2)} m (${pct}%)`;
    }
  }

  // Render Canvas in Editorial Light Theme
  function draw() {
    ctx.clearRect(0, 0, canvas.width, canvas.height);

    // 1. Background Paper
    ctx.fillStyle = '#FAF8F5';
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    // Fine Paper Grid
    ctx.strokeStyle = 'rgba(0, 0, 0, 0.04)';
    ctx.lineWidth = 1;
    for (let x = 0; x < canvas.width; x += 40) {
      ctx.beginPath();
      ctx.moveTo(x, 0);
      ctx.lineTo(x, canvas.height);
      ctx.stroke();
    }
    for (let y = 0; y < canvas.height; y += 40) {
      ctx.beginPath();
      ctx.moveTo(0, y);
      ctx.lineTo(canvas.width, y);
      ctx.stroke();
    }

    // 2. Tunnel Section (Warm Terracotta / Rust Shading)
    const tStartPt = getRoadPoint(TUNNEL_START);
    const tEndPt = getRoadPoint(TUNNEL_END);
    const tunnelX = tStartPt.x - 20;
    const tunnelW = (tEndPt.x - tStartPt.x) + 40;

    ctx.fillStyle = 'rgba(200, 75, 49, 0.06)';
    ctx.fillRect(tunnelX, 20, tunnelW, canvas.height - 40);
    ctx.strokeStyle = 'rgba(200, 75, 49, 0.4)';
    ctx.setLineDash([8, 6]);
    ctx.strokeRect(tunnelX, 20, tunnelW, canvas.height - 40);
    ctx.setLineDash([]);

    ctx.fillStyle = 'rgba(200, 75, 49, 0.9)';
    ctx.font = '600 11px "JetBrains Mono", monospace';
    ctx.fillText('TUNNEL OUTAGE SECTION (ZERO GNSS CARRIER LOCK)', tunnelX + 18, 42);

    // 3. Highway Asphalt Surface
    ctx.beginPath();
    for (let p = 0; p <= 1.0; p += 0.01) {
      const pt = getRoadPoint(p);
      if (p === 0) ctx.moveTo(pt.x, pt.y);
      else ctx.lineTo(pt.x, pt.y);
    }
    ctx.strokeStyle = '#D1D5DB';
    ctx.lineWidth = 38;
    ctx.stroke();

    ctx.strokeStyle = '#1F2937';
    ctx.lineWidth = 32;
    ctx.stroke();

    // Centerline Dashes
    ctx.beginPath();
    for (let p = 0; p <= 1.0; p += 0.01) {
      const pt = getRoadPoint(p);
      if (p === 0) ctx.moveTo(pt.x, pt.y);
      else ctx.lineTo(pt.x, pt.y);
    }
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.7)';
    ctx.setLineDash([12, 10]);
    ctx.lineWidth = 2;
    ctx.stroke();
    ctx.setLineDash([]);

    // 4. Trails
    // Red Classical Trail
    if (state.classic.trail.length > 1) {
      ctx.beginPath();
      ctx.moveTo(state.classic.trail[0].x, state.classic.trail[0].y);
      for (let i = 1; i < state.classic.trail.length; i++) {
        ctx.lineTo(state.classic.trail[i].x, state.classic.trail[i].y);
      }
      ctx.strokeStyle = 'rgba(200, 75, 49, 0.55)';
      ctx.lineWidth = 2.5;
      ctx.stroke();
    }

    // Emerald IDR Trail
    if (state.idr.trail.length > 1) {
      ctx.beginPath();
      ctx.moveTo(state.idr.trail[0].x, state.idr.trail[0].y);
      for (let i = 1; i < state.idr.trail.length; i++) {
        ctx.lineTo(state.idr.trail[i].x, state.idr.trail[i].y);
      }
      ctx.strokeStyle = 'rgba(27, 107, 90, 0.9)';
      ctx.lineWidth = 2.5;
      ctx.stroke();
    }

    // 5. Draw Vehicles
    drawCar(state.classic.x, state.classic.y, state.classic.heading, '#C84B31', 'CLASSICAL INS');
    drawCar(state.idr.x, state.idr.y, state.idr.heading, '#1B6B5A', 'IDR-NAVIGATOR');
  }

  function drawCar(x, y, heading, color, label) {
    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(heading);

    // Car Body
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.roundRect(-14, -7, 28, 14, 3);
    ctx.fill();

    // Roof
    ctx.fillStyle = '#111827';
    ctx.beginPath();
    ctx.roundRect(-4, -5, 12, 10, 2);
    ctx.fill();

    // Direction Chevron
    ctx.strokeStyle = '#ffffff';
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.moveTo(-1, -3);
    ctx.lineTo(3, 0);
    ctx.lineTo(-1, 3);
    ctx.stroke();

    ctx.restore();

    // Label
    ctx.fillStyle = color;
    ctx.font = '600 10px "JetBrains Mono", monospace';
    ctx.fillText(label, x - 28, y - 13);
  }

  // Animation Loop
  function loop() {
    updatePhysics();
    draw();
    requestAnimationFrame(loop);
  }

  requestAnimationFrame(loop);
})();
