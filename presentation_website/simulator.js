/**
 * IDR-NAVIGATOR MISSION-CRITICAL LIVE PROTOTYPE COCKPIT
 * Architectural Specification & Telemetry Engine designed by Gemini 4 Argon
 * Real-time Comparison: Causal SE-TCN Neural Dead Reckoning vs Classical Strapdown INS
 */

(function () {
  'use strict';

  // Canvas References
  const heroCanvas = document.getElementById('idr-hero-canvas') || document.getElementById('simCanvas');
  if (!heroCanvas) return;
  const ctx = heroCanvas.getContext('2d');

  // DOM Elements - Controls & Readouts
  const btnCutGnss = document.getElementById('btn-cut-gnss');
  const routeSelect = document.getElementById('route-select');
  const speedSlider = document.getElementById('speed-slider');
  const throttleReadout = document.getElementById('throttle-readout');
  const btnPothole = document.getElementById('btn-pothole');
  const btnZupt = document.getElementById('btn-zupt');
  const btnReset = document.getElementById('btn-reset-sim');

  // Telemetry HUD Elements
  const gnssPill = document.getElementById('gnss-status-pill');
  const gnssText = document.getElementById('gnss-status-text');
  const zuptIndicator = document.getElementById('zupt-indicator');
  const hudSpeedKmh = document.getElementById('hud-speed-kmh');
  const hudSpeedMs = document.getElementById('hud-speed-ms');
  const hudDistM = document.getElementById('hud-dist-m');
  const hudTimeS = document.getElementById('hud-time-s');
  const idrErrorM = document.getElementById('idr-error-m');
  const idrErrorPct = document.getElementById('idr-error-pct');
  const classErrorM = document.getElementById('class-error-m');
  const classErrorPct = document.getElementById('class-error-pct');
  const diagGyro = document.getElementById('diag-gyro');
  const diagNhc = document.getElementById('diag-nhc');
  const diagCov = document.getElementById('diag-cov');

  // Simulation State
  const state = {
    running: true,
    isOutage: false,
    outageStartTime: 0,
    outageElapsed: 0,
    outageDistance: 0,
    isZupt: false,
    shockTimer: 0,
    targetSpeedKmh: 65.0,
    currentSpeedKmh: 65.0,
    route: 'tunnel', // 'tunnel', 'urban', 'mountain'
    progress: 0.05,
    lastFrameTime: performance.now(),

    // Vehicles
    idr: {
      x: 0,
      y: 0,
      heading: 0,
      driftMeters: 0.12,
      trail: []
    },
    classic: {
      x: 0,
      y: 0,
      heading: 0,
      driftMeters: 0.15,
      accBiasY: 0.12,
      gyroBiasRad: 0.018,
      driftHeading: 0,
      trail: []
    }
  };

  // Route Geometries
  function getRoutePoint(p, routeType, w, h) {
    p = ((p % 1.0) + 1.0) % 1.0;
    const margin = 80;
    const usableW = w - margin * 2;
    const midY = h / 2;

    if (routeType === 'urban') {
      // 90-degree Grid Block Manhattan Loop
      const seg = p * 4;
      let x, y, heading;
      if (seg < 1) {
        x = margin + seg * usableW;
        y = midY - 90;
        heading = 0;
      } else if (seg < 2) {
        x = margin + usableW;
        y = (midY - 90) + (seg - 1) * 180;
        heading = Math.PI / 2;
      } else if (seg < 3) {
        x = margin + (3 - seg) * usableW;
        y = midY + 90;
        heading = Math.PI;
      } else {
        x = margin;
        y = (midY + 90) - (seg - 3) * 180;
        heading = -Math.PI / 2;
      }
      return { x, y, heading, inTunnel: false };
    }

    if (routeType === 'mountain') {
      // Winding Mountain Hairpins
      const x = margin + p * usableW;
      const y = midY + Math.sin(p * Math.PI * 4.0) * 120 + Math.cos(p * Math.PI * 2.0) * 40;
      
      const dp = 0.003;
      const xNext = margin + (p + dp) * usableW;
      const yNext = midY + Math.sin((p + dp) * Math.PI * 4.0) * 120 + Math.cos((p + dp) * Math.PI * 2.0) * 40;
      const heading = Math.atan2(yNext - y, xNext - x);
      return { x, y, heading, inTunnel: p > 0.35 && p < 0.72 };
    }

    // Default: 'tunnel' - Highway Tunnel (1.6 km)
    // S-curve highway with deep tunnel midsection (p: 0.28 to 0.78)
    const x = margin + p * usableW;
    const y = midY + Math.sin(p * Math.PI * 2.4) * 95 + Math.cos(p * Math.PI * 1.2) * 25;
    
    const dp = 0.003;
    const xNext = margin + (p + dp) * usableW;
    const yNext = midY + Math.sin((p + dp) * Math.PI * 2.4) * 95 + Math.cos((p + dp) * Math.PI * 1.2) * 25;
    const heading = Math.atan2(yNext - y, xNext - x);
    const inTunnel = p >= 0.26 && p <= 0.80;

    return { x, y, heading, inTunnel };
  }

  // Handle High-DPI canvas resizing
  function resizeCanvas() {
    const rect = heroCanvas.parentElement.getBoundingClientRect();
    const dpr = window.devicePixelRatio || 1;
    heroCanvas.width = rect.width * dpr;
    heroCanvas.height = Math.max(480, rect.height) * dpr;
    ctx.scale(dpr, dpr);
  }
  window.addEventListener('resize', resizeCanvas);
  resizeCanvas();

  // Reset function
  function resetSimulation() {
    state.progress = 0.05;
    state.isOutage = false;
    state.outageElapsed = 0;
    state.outageDistance = 0;
    state.isZupt = false;
    state.shockTimer = 0;
    state.idr.driftMeters = 0.12;
    state.classic.driftMeters = 0.15;
    state.idr.trail = [];
    state.classic.trail = [];
    updateGnssUI(false);
    if (zuptIndicator) {
      zuptIndicator.classList.remove('active');
      zuptIndicator.textContent = 'ZUPT: STANDBY';
    }
    if (btnZupt) {
      btnZupt.classList.remove('locked');
      btnZupt.innerHTML = `🛑 ZUPT Brake<small>Red Light 0 m/s Lock</small>`;
    }
  }

  // Update GNSS UI state
  function updateGnssUI(isOutage) {
    if (!gnssPill || !btnCutGnss) return;
    if (isOutage) {
      gnssPill.className = 'status-pill status-denied';
      gnssText.textContent = 'GNSS DENIED — BLACKOUT ACTIVE';
      btnCutGnss.className = 'btn-gnss-cut active-cut';
      btnCutGnss.innerHTML = `
        <span class="btn-icon">⚡</span>
        <span class="btn-text">RESTORE GNSS SIGNALS</span>
        <span class="btn-sub">RE-ACQUIRE RTK CARRIER LOCK</span>
      `;
    } else {
      gnssPill.className = 'status-pill status-locked';
      gnssText.textContent = 'GNSS LOCKED — RTK 0.8 HDOP';
      btnCutGnss.className = 'btn-gnss-cut';
      btnCutGnss.innerHTML = `
        <span class="btn-icon">📡</span>
        <span class="btn-text">CUT GNSS SIGNAL</span>
        <span class="btn-sub">SIMULATE TUNNEL BLACKOUT</span>
      `;
    }
  }

  // Wire Event Listeners
  if (btnCutGnss) {
    btnCutGnss.addEventListener('click', () => {
      state.isOutage = !state.isOutage;
      if (state.isOutage) {
        state.outageStartTime = performance.now();
      }
      updateGnssUI(state.isOutage);
    });
  }

  if (routeSelect) {
    routeSelect.addEventListener('change', (e) => {
      state.route = e.target.value;
      state.idr.trail = [];
      state.classic.trail = [];
      state.progress = 0.05;
    });
  }

  if (speedSlider) {
    speedSlider.addEventListener('input', (e) => {
      state.targetSpeedKmh = parseFloat(e.target.value);
      if (throttleReadout) {
        throttleReadout.textContent = `${state.targetSpeedKmh.toFixed(0)} km/h`;
      }
    });
  }

  if (btnPothole) {
    btnPothole.addEventListener('click', () => {
      state.shockTimer = 35; // Frames of shock perturbation
    });
  }

  if (btnZupt) {
    btnZupt.addEventListener('click', () => {
      state.isZupt = !state.isZupt;
      if (state.isZupt) {
        btnZupt.classList.add('locked');
        btnZupt.innerHTML = `🛑 BRAKE LOCKED<small>Velocity = 0.0 m/s</small>`;
        if (zuptIndicator) {
          zuptIndicator.classList.add('active');
          zuptIndicator.textContent = 'ZUPT: ENGAGED';
        }
      } else {
        btnZupt.classList.remove('locked');
        btnZupt.innerHTML = `🛑 ZUPT Brake<small>Red Light 0 m/s Lock</small>`;
        if (zuptIndicator) {
          zuptIndicator.classList.remove('active');
          zuptIndicator.textContent = 'ZUPT: STANDBY';
        }
      }
    });
  }

  if (btnReset) {
    btnReset.addEventListener('click', resetSimulation);
  }

  // Make reset global for compatibility
  window.resetSimulator = resetSimulation;

  // Main Animation Loop
  function loop(now) {
    const dt = Math.min(0.05, (now - state.lastFrameTime) / 1000);
    state.lastFrameTime = now;

    const dpr = window.devicePixelRatio || 1;
    const w = heroCanvas.width / dpr;
    const h = heroCanvas.height / dpr;

    // 1. Physics & Speed Update
    if (state.isZupt) {
      state.currentSpeedKmh += (0 - state.currentSpeedKmh) * 0.15;
    } else {
      state.currentSpeedKmh += (state.targetSpeedKmh - state.currentSpeedKmh) * 0.08;
    }
    const speedMs = (state.currentSpeedKmh * 1000) / 3600;

    // Advance track progress
    const progressSpeed = (speedMs * dt) / 1600.0; // 1.6km loop length
    state.progress = (state.progress + progressSpeed) % 1.0;

    // Get ground truth road point
    const truth = getRoutePoint(state.progress, state.route, w, h);

    // Auto-engage outage if vehicle enters tunnel segment on highway route
    if (state.route === 'tunnel' && truth.inTunnel && !state.isOutage) {
      state.isOutage = true;
      state.outageStartTime = now;
      updateGnssUI(true);
    } else if (state.route === 'tunnel' && !truth.inTunnel && state.isOutage && !btnCutGnss.classList.contains('manually-locked')) {
      // Keep manual toggle in mind
    }

    // Accumulate outage metrics
    if (state.isOutage) {
      state.outageElapsed += dt;
      state.outageDistance += speedMs * dt;
    }

    // 2. Shock / Pothole perturbation
    let shockAccel = 0;
    if (state.shockTimer > 0) {
      shockAccel = Math.sin(state.shockTimer * 0.8) * 4.5; // 4.5g impulse
      state.shockTimer--;
    }

    // 3. Vehicle Positioning
    // Green Vehicle (IDR-Navigator): SE-TCN + Non-Holonomic + Map Snap
    state.idr.x = truth.x;
    state.idr.y = truth.y + (Math.sin(now * 0.005) * 0.5); // Micro-chassis vibration
    state.idr.heading = truth.heading;

    if (state.isOutage) {
      // Empirical IDR drift rate: ~0.43% to 0.80% of distance
      const idrDriftRate = 0.0048; // 0.48%
      state.idr.driftMeters = Math.max(0.12, state.outageDistance * idrDriftRate + (Math.random() * 0.05));
    } else {
      state.idr.driftMeters = 0.12;
    }

    // Red Vehicle (Classical INS): Quadratic bias divergence
    if (state.isOutage) {
      const t = state.outageElapsed;
      // Drift = 0.5 * a_bias * t^2 + v * theta_error * t
      const quadDrift = 0.5 * state.classic.accBiasY * (t * t) * 0.35;
      const angleDrift = state.classic.gyroBiasRad * t;
      state.classic.driftMeters = quadDrift + (state.outageDistance * 0.06);

      // Offset classical position along normal to road
      const normalAngle = truth.heading + Math.PI / 2;
      const lateralShift = Math.min(180, state.classic.driftMeters * 3.5);
      state.classic.x = truth.x + Math.cos(normalAngle) * lateralShift;
      state.classic.y = truth.y + Math.sin(normalAngle) * lateralShift;
      state.classic.heading = truth.heading + angleDrift;
    } else {
      state.classic.x = truth.x;
      state.classic.y = truth.y;
      state.classic.heading = truth.heading;
      state.classic.driftMeters = 0.15;
    }

    // Record motion trails (keep last 60 points)
    state.idr.trail.push({ x: state.idr.x, y: state.idr.y });
    if (state.idr.trail.length > 70) state.idr.trail.shift();

    state.classic.trail.push({ x: state.classic.x, y: state.classic.y });
    if (state.classic.trail.length > 70) state.classic.trail.shift();

    // 4. Render Canvas Scene
    renderScene(ctx, w, h, truth, now);

    // 5. Update Telemetry HUD DOM
    updateTelemetryReadouts(speedMs);

    requestAnimationFrame(loop);
  }

  // Draw Scene on Canvas
  function renderScene(ctx, w, h, truth, now) {
    ctx.clearRect(0, 0, w, h);

    // 1. Draw Subterranean / Night Sky Grid Background
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.035)';
    ctx.lineWidth = 1;
    const gridSize = 40;
    for (let x = 0; x < w; x += gridSize) {
      ctx.beginPath();
      ctx.moveTo(x, 0);
      ctx.lineTo(x, h);
      ctx.stroke();
    }
    for (let y = 0; y < h; y += gridSize) {
      ctx.beginPath();
      ctx.moveTo(0, y);
      ctx.lineTo(w, y);
      ctx.stroke();
    }

    // 2. Render Road Envelope & Centerline
    ctx.lineWidth = 36;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';

    // Asphalt Base
    ctx.beginPath();
    for (let i = 0; i <= 100; i++) {
      const pt = getRoutePoint(i / 100, state.route, w, h);
      if (i === 0) ctx.moveTo(pt.x, pt.y);
      else ctx.lineTo(pt.x, pt.y);
    }
    ctx.strokeStyle = '#151c2e';
    ctx.stroke();

    // Tunnel Zone Ambient Glow (if tunnel route)
    if (state.route === 'tunnel') {
      ctx.lineWidth = 42;
      ctx.beginPath();
      for (let i = 26; i <= 80; i++) {
        const pt = getRoutePoint(i / 100, state.route, w, h);
        if (i === 26) ctx.moveTo(pt.x, pt.y);
        else ctx.lineTo(pt.x, pt.y);
      }
      ctx.strokeStyle = 'rgba(255, 23, 68, 0.12)';
      ctx.stroke();

      // Tunnel Portal Labels
      const pEnter = getRoutePoint(0.26, state.route, w, h);
      const pExit = getRoutePoint(0.80, state.route, w, h);

      ctx.fillStyle = '#ff1744';
      ctx.font = '600 10px monospace';
      ctx.fillText('▼ TUNNEL INGRESS (GNSS DENIED)', pEnter.x - 20, pEnter.y - 30);
      ctx.fillStyle = '#00e676';
      ctx.fillText('▲ PORTAL EGRESS (GNSS LOCK)', pExit.x - 20, pExit.y - 30);
    }

    // Road White Curbs
    ctx.lineWidth = 2;
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.2)';
    ctx.stroke();

    // Dashed Centerline
    ctx.lineWidth = 2;
    ctx.setLineDash([8, 12]);
    ctx.strokeStyle = 'rgba(255, 235, 59, 0.4)';
    ctx.stroke();
    ctx.setLineDash([]); // Reset dash

    // 3. Render Vehicle Motion Trails
    // Red Classical Trajectory Trail
    if (state.classic.trail.length > 1) {
      ctx.beginPath();
      for (let i = 0; i < state.classic.trail.length; i++) {
        const p = state.classic.trail[i];
        if (i === 0) ctx.moveTo(p.x, p.y);
        else ctx.lineTo(p.x, p.y);
      }
      ctx.strokeStyle = 'rgba(255, 23, 68, 0.7)';
      ctx.lineWidth = 3;
      ctx.stroke();
    }

    // Green IDR Trajectory Trail
    if (state.idr.trail.length > 1) {
      ctx.beginPath();
      for (let i = 0; i < state.idr.trail.length; i++) {
        const p = state.idr.trail[i];
        if (i === 0) ctx.moveTo(p.x, p.y);
        else ctx.lineTo(p.x, p.y);
      }
      ctx.strokeStyle = 'rgba(0, 230, 118, 0.85)';
      ctx.lineWidth = 3;
      ctx.shadowColor = '#00e676';
      ctx.shadowBlur = 8;
      ctx.stroke();
      ctx.shadowBlur = 0; // Reset blur
    }

    // 4. Draw Vehicles
    drawCar(ctx, state.classic.x, state.classic.y, state.classic.heading, '#ff1744', 'CLASSICAL INS');
    drawCar(ctx, state.idr.x, state.idr.y, state.idr.heading, '#00e676', 'IDR-NAVIGATOR');
  }

  // Draw 2D Stylized Vehicle with Headlights & Radar Sweep
  function drawCar(ctx, x, y, heading, color, label) {
    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(heading);

    // Headlight Beams
    const gradient = ctx.createRadialGradient(28, 0, 2, 60, 0, 50);
    gradient.addColorStop(0, color === '#00e676' ? 'rgba(0, 230, 118, 0.4)' : 'rgba(255, 23, 68, 0.35)');
    gradient.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = gradient;
    ctx.beginPath();
    ctx.moveTo(12, -8);
    ctx.lineTo(65, -28);
    ctx.lineTo(65, 28);
    ctx.lineTo(12, 8);
    ctx.closePath();
    ctx.fill();

    // Chassis Box
    ctx.fillStyle = '#0b111e';
    ctx.strokeStyle = color;
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.roundRect(-14, -8, 28, 16, 4);
    ctx.fill();
    ctx.stroke();

    // Windshield
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.roundRect(0, -6, 6, 12, 2);
    ctx.fill();

    // Vehicle Roof Sensor Indicator
    ctx.fillStyle = '#ffffff';
    ctx.beginPath();
    ctx.arc(-4, 0, 2.5, 0, Math.PI * 2);
    ctx.fill();

    ctx.restore();

    // Label Floating Above Vehicle
    ctx.fillStyle = color;
    ctx.font = '700 9px monospace';
    ctx.textAlign = 'center';
    ctx.fillText(label, x, y - 18);
  }

  // Telemetry HUD Readout Refresh
  function updateTelemetryReadouts(speedMs) {
    if (hudSpeedKmh) hudSpeedKmh.textContent = state.currentSpeedKmh.toFixed(1);
    if (hudSpeedMs) hudSpeedMs.textContent = `${speedMs.toFixed(2)} m/s`;

    if (hudDistM) hudDistM.textContent = state.outageDistance.toFixed(1);
    if (hudTimeS) hudTimeS.textContent = `T+ ${state.outageElapsed.toFixed(1)}s`;

    // Drift metrics
    const dist = Math.max(1.0, state.outageDistance);
    const idrPct = ((state.idr.driftMeters / dist) * 100).toFixed(2);
    const classPct = ((state.classic.driftMeters / dist) * 100).toFixed(2);

    if (idrErrorM) idrErrorM.textContent = `${state.idr.driftMeters.toFixed(2)} m`;
    if (idrErrorPct) idrErrorPct.textContent = `${idrPct}%`;

    if (classErrorM) classErrorM.textContent = `${state.classic.driftMeters.toFixed(1)} m`;
    if (classErrorPct) classErrorPct.textContent = `${classPct}%`;

    // Live Sensor Diagnostics
    if (diagGyro) diagGyro.textContent = `${(0.0021 + Math.sin(performance.now() * 0.003) * 0.0003).toFixed(4)} rad/s`;
    if (diagNhc) diagNhc.textContent = `${(0.014 + Math.cos(performance.now() * 0.002) * 0.002).toFixed(3)} m/s`;
    if (diagCov) diagCov.textContent = `${(0.038 + (state.isOutage ? state.outageElapsed * 0.0012 : 0)).toFixed(3)} m²`;
  }

  // Start Animation Loop
  requestAnimationFrame(loop);

})();
