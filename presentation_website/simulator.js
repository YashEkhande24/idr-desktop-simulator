/**
 * IDR-NAVIGATOR LIVE IN-BROWSER SIMULATOR
 * Side-by-Side Physics Comparison: IDR Neuro-Kalman vs Classical Open-Loop INS
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
    roadProgress: 0.05, // 0 to 1 along track
    
    // Green Vehicle (IDR)
    idr: {
      x: 0,
      y: 0,
      heading: 0,
      drift: 0.2, // meters
      trail: []
    },

    // Red Vehicle (Classical INS)
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
    // Canvas dimensions: width=900, height=480
    // Track flows from left to right with curves
    const w = canvas.width;
    const h = canvas.height;
    
    // Looping track parameter t in [0, 1]
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

  // Tunnel Region on Track: from p = 0.35 to p = 0.75
  const TUNNEL_START = 0.35;
  const TUNNEL_END = 0.78;

  // DOM Elements
  const stateLabel = document.getElementById('simStateLabel');
  const hdopVal = document.getElementById('simHdopVal');
  const jerkVal = document.getElementById('simJerkVal');
  const speedVal = document.getElementById('simSpeedVal');
  const distVal = document.getElementById('simDistVal');
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
        btnOutage.style.background = 'var(--grad-cyan-green)';
        btnOutage.innerHTML = `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg><span>RESTORE GNSS SIGNALS</span>`;
      }
    } else {
      if (btnOutage) {
        btnOutage.style.background = 'var(--grad-amber-red)';
        btnOutage.innerHTML = `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/></svg><span>CUT GNSS (TUNNEL OUTAGE)</span>`;
      }
      // Zero-jump reacquisition for IDR
      state.idr.drift = 0.2;
    }
  };

  // Trigger Shock
  window.injectSimShock = function () {
    state.shockTimer = 45; // frames of shock active
  };

  // Toggle ZUPT (Red light)
  window.toggleSimZupt = function () {
    state.isZupt = !state.isZupt;
    const btn = document.getElementById('btnSimZupt');
    if (btn) {
      if (state.isZupt) {
        btn.style.background = 'var(--red-drift)';
        btn.style.color = '#fff';
        btn.innerHTML = `<span>STANDSTILL LOCKED (ZUPT ON)</span>`;
      } else {
        btn.style.background = 'rgba(16, 185, 129, 0.15)';
        btn.style.color = 'var(--green-accent)';
        btn.innerHTML = `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="10" y1="15" x2="10" y2="9"/><line x1="14" y1="15" x2="14" y2="9"/></svg><span>TOGGLE RED LIGHT (ZUPT)</span>`;
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
      btnOutage.style.background = 'var(--grad-amber-red)';
      btnOutage.innerHTML = `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/></svg><span>CUT GNSS (TUNNEL OUTAGE)</span>`;
    }
  };

  // Main Physics Update Loop
  function updatePhysics() {
    const dt = 1 / 60; // 60 FPS delta
    state.time += dt;

    // Standstill speed management
    if (state.isZupt) {
      state.speed = Math.max(0, state.speed - 90 * dt);
    } else {
      state.speed = Math.min(state.nominalSpeed, state.speed + 45 * dt);
    }

    const currentSpeedMs = (state.speed * 1000) / 3600;
    state.totalDistance += currentSpeedMs * dt;

    // Advance road progress
    const trackAdvance = (currentSpeedMs * dt) / 520;
    state.roadProgress = (state.roadProgress + trackAdvance) % 1.0;

    // Check if auto-entering tunnel segment on road
    const inTunnelZone = state.roadProgress >= TUNNEL_START && state.roadProgress <= TUNNEL_END;
    const effectiveOutage = state.isOutage || inTunnelZone;

    if (effectiveOutage) {
      state.hdop = Math.min(38.5, state.hdop + 3.5 * dt);
      state.outageDuration += dt;
    } else {
      state.hdop = Math.max(0.8, state.hdop - 8.0 * dt);
      state.outageDuration = Math.max(0, state.outageDuration - 2.0 * dt);
    }

    // Pothole shock simulation
    if (state.shockTimer > 0) {
      state.shockTimer--;
      state.jerkVariance = 520 + Math.random() * 80;
    } else {
      state.jerkVariance = 12 + Math.random() * 4;
    }

    // Calculate Road Centerline reference position
    const roadPt = getRoadPoint(state.roadProgress);

    // Update IDR Vehicle:
    // Follows road centerline with minute realistic sensor uncertainty (< 0.5m)
    // Non-Holonomic Constraint keeps car aligned with heading
    state.idr.x = roadPt.x;
    state.idr.y = roadPt.y;
    state.idr.heading = roadPt.heading;

    if (effectiveOutage) {
      // IDR drift grows at a slow linear rate bounded by map matching (< 0.5%)
      state.idr.drift = Math.min(1.8, 0.2 + (state.outageDuration * 0.08));
    } else {
      state.idr.drift = 0.2;
    }

    // Update Classical INS Vehicle:
    // In Open Sky: aided by GNSS, so tracks along road
    // In Outage: Double integration causes exponential quadratic divergence!
    if (effectiveOutage) {
      // Accelerometer bias + Gyro bias cause heading angle to slowly bend and position to fly away
      state.classic.driftAngle += state.classic.gyroBias * dt * 2.5;
      const divergenceFactor = Math.pow(state.outageDuration * 1.6, 2.2);
      state.classic.drift = divergenceFactor * 4.5;

      // Displace position off tangent
      const perpAngle = roadPt.heading + Math.PI / 2 + state.classic.driftAngle;
      state.classic.x = roadPt.x + Math.cos(perpAngle) * state.classic.drift;
      state.classic.y = roadPt.y + Math.sin(perpAngle) * state.classic.drift;
      state.classic.heading = roadPt.heading + state.classic.driftAngle;
    } else {
      // Slaved to GPS fix with slight lag
      state.classic.x = roadPt.x;
      state.classic.y = roadPt.y;
      state.classic.heading = roadPt.heading;
      state.classic.drift = 0.0;
      state.classic.driftAngle = 0;
    }

    // Record breadcrumb trails
    if (Math.floor(state.time * 60) % 3 === 0) {
      state.idr.trail.push({ x: state.idr.x, y: state.idr.y });
      state.classic.trail.push({ x: state.classic.x, y: state.classic.y });

      if (state.idr.trail.length > 250) state.idr.trail.shift();
      if (state.classic.trail.length > 250) state.classic.trail.shift();
    }

    // Update Telemetry DOM
    updateTelemetryUI(effectiveOutage);
  }

  function updateTelemetryUI(effectiveOutage) {
    if (stateLabel) {
      if (state.shockTimer > 0) {
        stateLabel.className = 'amber-text';
        stateLabel.textContent = 'SHOCK GATE ACTIVE (JERK > 450 m²/s⁶)';
      } else if (effectiveOutage) {
        stateLabel.className = 'red-text';
        stateLabel.textContent = 'TUNNEL OUTAGE (GNSS DENIED - IDR ACTIVE)';
      } else if (state.isZupt) {
        stateLabel.className = 'cyan-text';
        stateLabel.textContent = 'ZUPT STANDSTILL LOCK (VELOCITY = 0.00)';
      } else {
        stateLabel.className = 'green-text';
        stateLabel.textContent = 'OPEN SKY (GNSS NOMINAL - HDOP 0.8)';
      }
    }

    if (hdopVal) {
      hdopVal.textContent = state.hdop.toFixed(1) + (state.hdop > 5 ? ' (BLACKOUT)' : ' (EXCELLENT)');
      hdopVal.style.color = state.hdop > 5 ? 'var(--red-drift)' : 'var(--cyan-primary)';
    }

    if (jerkVal) {
      jerkVal.textContent = state.jerkVariance.toFixed(0) + ' m²/s⁶';
      jerkVal.style.color = state.shockTimer > 0 ? 'var(--amber-alert)' : 'var(--text-main)';
    }

    if (speedVal) {
      speedVal.textContent = state.speed.toFixed(1) + ' km/h';
    }

    if (distVal) {
      distVal.textContent = state.totalDistance.toFixed(0) + ' m';
    }

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

  // Render Canvas
  function draw() {
    ctx.clearRect(0, 0, canvas.width, canvas.height);

    // 1. Draw Background Grid
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.03)';
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

    // 2. Draw Tunnel Section Background
    const tStartPt = getRoadPoint(TUNNEL_START);
    const tEndPt = getRoadPoint(TUNNEL_END);
    const tunnelX = tStartPt.x - 20;
    const tunnelW = (tEndPt.x - tStartPt.x) + 40;

    ctx.fillStyle = 'rgba(10, 16, 28, 0.85)';
    ctx.fillRect(tunnelX, 20, tunnelW, canvas.height - 40);
    ctx.strokeStyle = 'rgba(245, 158, 11, 0.4)';
    ctx.setLineDash([8, 6]);
    ctx.strokeRect(tunnelX, 20, tunnelW, canvas.height - 40);
    ctx.setLineDash([]);

    // Tunnel Label
    ctx.fillStyle = 'rgba(245, 158, 11, 0.8)';
    ctx.font = '700 12px "JetBrains Mono", monospace';
    ctx.fillText('TUNNEL / UNDERPASS SECTION (TOTAL GNSS BLACKOUT)', tunnelX + 18, 42);

    // 3. Draw Highway Road Surface
    // Road border and asphalt
    ctx.beginPath();
    for (let p = 0; p <= 1.0; p += 0.01) {
      const pt = getRoadPoint(p);
      if (p === 0) ctx.moveTo(pt.x, pt.y);
      else ctx.lineTo(pt.x, pt.y);
    }
    ctx.strokeStyle = 'rgba(30, 41, 59, 0.9)';
    ctx.lineWidth = 36;
    ctx.stroke();

    // Road Edge Curbs
    ctx.strokeStyle = 'rgba(71, 85, 105, 0.6)';
    ctx.lineWidth = 38;
    ctx.stroke();

    ctx.strokeStyle = 'rgba(15, 23, 42, 0.95)';
    ctx.lineWidth = 32;
    ctx.stroke();

    // Road Dashed Centerline
    ctx.beginPath();
    for (let p = 0; p <= 1.0; p += 0.01) {
      const pt = getRoadPoint(p);
      if (p === 0) ctx.moveTo(pt.x, pt.y);
      else ctx.lineTo(pt.x, pt.y);
    }
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.35)';
    ctx.setLineDash([12, 10]);
    ctx.lineWidth = 2;
    ctx.stroke();
    ctx.setLineDash([]);

    // 4. Draw Trails
    // Red Classical Trail
    if (state.classic.trail.length > 1) {
      ctx.beginPath();
      ctx.moveTo(state.classic.trail[0].x, state.classic.trail[0].y);
      for (let i = 1; i < state.classic.trail.length; i++) {
        ctx.lineTo(state.classic.trail[i].x, state.classic.trail[i].y);
      }
      ctx.strokeStyle = 'rgba(239, 68, 68, 0.45)';
      ctx.lineWidth = 3;
      ctx.stroke();
    }

    // Green IDR Trail
    if (state.idr.trail.length > 1) {
      ctx.beginPath();
      ctx.moveTo(state.idr.trail[0].x, state.idr.trail[0].y);
      for (let i = 1; i < state.idr.trail.length; i++) {
        ctx.lineTo(state.idr.trail[i].x, state.idr.trail[i].y);
      }
      ctx.strokeStyle = 'rgba(16, 185, 129, 0.7)';
      ctx.lineWidth = 3;
      ctx.shadowColor = 'rgba(16, 185, 129, 0.5)';
      ctx.shadowBlur = 8;
      ctx.stroke();
      ctx.shadowBlur = 0;
    }

    // 5. Draw Vehicles
    drawCar(state.classic.x, state.classic.y, state.classic.heading, '#ef4444', 'CLASSIC INS');
    drawCar(state.idr.x, state.idr.y, state.idr.heading, '#10b981', 'IDR (OURS)');
  }

  function drawCar(x, y, heading, color, label) {
    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(heading);

    // Car Body Shape
    ctx.fillStyle = color;
    ctx.shadowColor = color;
    ctx.shadowBlur = 10;
    ctx.beginPath();
    ctx.roundRect(-14, -7, 28, 14, 4);
    ctx.fill();
    ctx.shadowBlur = 0;

    // Windshield & Roof
    ctx.fillStyle = '#0a0e17';
    ctx.beginPath();
    ctx.roundRect(-4, -5, 12, 10, 2);
    ctx.fill();

    // Headlights
    ctx.fillStyle = '#fff';
    ctx.fillRect(12, -6, 2, 3);
    ctx.fillRect(12, 3, 2, 3);

    // Direction Chevron
    ctx.strokeStyle = '#fff';
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.moveTo(-1, -3);
    ctx.lineTo(3, 0);
    ctx.lineTo(-1, 3);
    ctx.stroke();

    ctx.restore();

    // Label over vehicle
    ctx.fillStyle = color;
    ctx.font = '700 9px "JetBrains Mono", monospace';
    ctx.fillText(label, x - 22, y - 14);
  }

  // Animation Loop
  function loop() {
    updatePhysics();
    draw();
    requestAnimationFrame(loop);
  }

  requestAnimationFrame(loop);
})();
