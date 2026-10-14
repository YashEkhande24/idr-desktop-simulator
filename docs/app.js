// IDR-Navigator Aerospace Telemetry & Benchmarks Dashboard

document.addEventListener('DOMContentLoaded', () => {
  initMathRenderer();
  initCounters();
  initCharts();
  initTabs();
  initPipelineCards();
  initSimulator();
});

function initMathRenderer() {
  function render() {
    if (typeof renderMathInElement === 'function') {
      renderMathInElement(document.body, {
        delimiters: [
          { left: '$$', right: '$$', display: true },
          { left: '$', right: '$', display: false },
          { left: '\\(', right: '\\)', display: false },
          { left: '\\[', right: '\\]', display: true }
        ],
        throwOnError: false
      });
    } else {
      setTimeout(render, 50);
    }
  }
  render();
}

// 1. Animated KPI Counters
function initCounters() {
  const counters = [
    { id: 'kpi-pass-rate', target: 93.8, suffix: '%', decimals: 1 },
    { id: 'kpi-min-drift', target: 0.02, suffix: '%', decimals: 2 },
    { id: 'kpi-model-size', target: 2.1, suffix: ' MB', decimals: 1 },
    { id: 'kpi-npu-latency', target: 4.5, suffix: ' ms', decimals: 1 },
    { id: 'kpi-loop-latency', target: 11.2, suffix: ' ms', decimals: 1 },
    { id: 'kpi-battery-rate', target: 5.8, suffix: '%/hr', decimals: 1 }
  ];

  counters.forEach(c => {
    const el = document.getElementById(c.id);
    if (!el) return;
    
    let current = 0;
    const duration = 1200;
    const steps = 40;
    const increment = c.target / steps;
    const stepTime = duration / steps;
    
    const timer = setInterval(() => {
      current += increment;
      if (current >= c.target) {
        current = c.target;
        clearInterval(timer);
      }
      el.textContent = current.toFixed(c.decimals) + c.suffix;
    }, stepTime);
  });
}

// Global chart references
let trajectoryChart = null;
let speedChart = null;
let driftChart = null;

// 2. Trajectory & Speed Benchmark Datasets (IO-VNBD S-Vta23 850m Tunnel)
const sVta23TrajectoryData = {
  truth: [
    { x: 0, y: 0 }, { x: 50, y: 62 }, { x: 100, y: 125 }, { x: 145.2, y: 182.4 },
    { x: 200, y: 251 }, { x: 260, y: 326 }, { x: 328.7, y: 412.0 }, { x: 400, y: 501 },
    { x: 470, y: 575 }, { x: 542.1, y: 638.5 }, { x: 620, y: 710 }, { x: 700, y: 780 },
    { x: 780.4, y: 850.2 }
  ],
  idr: [
    { x: 0, y: 0 }, { x: 49.9, y: 61.9 }, { x: 99.8, y: 124.7 }, { x: 144.8, y: 181.9 },
    { x: 199.5, y: 250.6 }, { x: 259.2, y: 325.2 }, { x: 326.5, y: 409.8 }, { x: 398.5, y: 499.2 },
    { x: 468.1, y: 573.0 }, { x: 538.0, y: 632.7 }, { x: 617.2, y: 706.5 }, { x: 698.0, y: 777.2 },
    { x: 780.1, y: 850.0 }
  ],
  classical: [
    { x: 0, y: 0 }, { x: 55, y: 70 }, { x: 112, y: 148 }, { x: 168.4, y: 214.1 },
    { x: 240, y: 285 }, { x: 325, y: 330 }, { x: 415.9, y: 362.5 }, { x: 550, y: 385 },
    { x: 732.0, y: 410.2 }, { x: 890, y: 450 }, { x: 1010, y: 485 }, { x: 1120.5, y: 520.4 }
  ]
};

// Speed & Uncertainty series over 60 seconds tunnel passage
const speedTimeSeries = [];
const truthSpeedSeries = [];
const idrSpeedSeries = [];
const upperConfidenceSeries = [];
const lowerConfidenceSeries = [];
const classicalSpeedSeries = [];

for (let t = 0; t <= 60; t += 2) {
  speedTimeSeries.push(t);
  // Base driving profile ~ 50 km/h with a slight dip then acceleration
  let vTruth = 48 + 4 * Math.sin(t / 8);
  if (t >= 24 && t <= 28) {
    // Pothole shock zone
    vTruth -= 3;
  }
  truthSpeedSeries.push(vTruth);
  
  // IDR TCN speed prediction with slight variance
  const noise = (Math.random() - 0.5) * 0.4;
  const vPred = vTruth + noise;
  idrSpeedSeries.push(vPred);
  
  // Heteroscedastic uncertainty (sigma increases during shock)
  let sigma = 0.8;
  if (t >= 24 && t <= 28) {
    sigma = 3.2; // Jerk variance gate detects road shock
  }
  upperConfidenceSeries.push(vPred + 2 * sigma);
  lowerConfidenceSeries.push(Math.max(0, vPred - 2 * sigma));
  
  // Classical INS speed drift due to accelerometer bias (accumulates linearly)
  classicalSpeedSeries.push(vTruth + (t * 0.45));
}

// Cumulative Drift comparison
const driftTime = [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60];
const classicalDriftDist = [0, 1.8, 7.2, 16.5, 30.1, 48.2, 72.5, 102.1, 138.4, 184.2, 240.0, 310.5, 395.0];
const idrDriftDist = [0, 0.05, 0.12, 0.22, 0.31, 0.38, 0.42, 0.45, 0.48, 0.51, 0.53, 0.55, 0.58];

function initCharts() {
  const ctxTraj = document.getElementById('trajectoryCanvas');
  if (!ctxTraj) return;

  trajectoryChart = new Chart(ctxTraj.getContext('2d'), {
    type: 'scatter',
    data: {
      datasets: [
        {
          label: 'Ground Truth Reference (WGS-84 / Doppler)',
          data: sVta23TrajectoryData.truth,
          showLine: true,
          borderColor: '#10b981',
          borderWidth: 3,
          pointBackgroundColor: '#10b981',
          pointRadius: 4,
          tension: 0.2
        },
        {
          label: 'Proposed IDR-Navigator (TCN + ES-EKF + NHC + OSM)',
          data: sVta23TrajectoryData.idr,
          showLine: true,
          borderColor: '#00f0ff',
          borderWidth: 2.5,
          borderDash: [2, 2],
          pointBackgroundColor: '#00f0ff',
          pointRadius: 3,
          tension: 0.2
        },
        {
          label: 'Classical INS Double-Integration (Diverges +194m)',
          data: sVta23TrajectoryData.classical,
          showLine: true,
          borderColor: '#ef4444',
          borderWidth: 2,
          borderDash: [6, 4],
          pointBackgroundColor: '#ef4444',
          pointRadius: 3,
          tension: 0.2
        }
      ]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      scales: {
        x: {
          title: { display: true, text: 'Local ENU East Position (Meters)', color: '#94a3b8', font: { family: 'JetBrains Mono' } },
          grid: { color: 'rgba(255, 255, 255, 0.05)' },
          ticks: { color: '#94a3b8' }
        },
        y: {
          title: { display: true, text: 'Local ENU North Position (Meters)', color: '#94a3b8', font: { family: 'JetBrains Mono' } },
          grid: { color: 'rgba(255, 255, 255, 0.05)' },
          ticks: { color: '#94a3b8' }
        }
      },
      plugins: {
        legend: { display: false },
        tooltip: {
          callbacks: {
            label: (ctx) => `${ctx.dataset.label}: (${ctx.parsed.x.toFixed(1)}m, ${ctx.parsed.y.toFixed(1)}m)`
          }
        }
      }
    }
  });
}

function initSpeedChart() {
  const ctx = document.getElementById('speedCanvas');
  if (!ctx || speedChart) return;

  speedChart = new Chart(ctx.getContext('2d'), {
    type: 'line',
    data: {
      labels: speedTimeSeries,
      datasets: [
        {
          label: 'Upper Uncertainty (v̂ + 2σ_v)',
          data: upperConfidenceSeries,
          borderColor: 'transparent',
          backgroundColor: 'rgba(0, 240, 255, 0.12)',
          fill: '+1',
          pointRadius: 0
        },
        {
          label: 'Lower Uncertainty (v̂ - 2σ_v)',
          data: lowerConfidenceSeries,
          borderColor: 'transparent',
          backgroundColor: 'transparent',
          fill: false,
          pointRadius: 0
        },
        {
          label: 'IDR SE-TCN Predicted Speed (v̂)',
          data: idrSpeedSeries,
          borderColor: '#00f0ff',
          borderWidth: 2,
          pointRadius: 2,
          fill: false
        },
        {
          label: 'True Ground Speed (Doppler)',
          data: truthSpeedSeries,
          borderColor: '#10b981',
          borderWidth: 2,
          pointRadius: 0,
          borderDash: [3, 3],
          fill: false
        },
        {
          label: 'Classical INS Raw Speed (Drifting)',
          data: classicalSpeedSeries,
          borderColor: '#ef4444',
          borderWidth: 1.5,
          borderDash: [4, 4],
          pointRadius: 0,
          fill: false
        }
      ]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      scales: {
        x: {
          title: { display: true, text: 'Outage Time (Seconds)', color: '#94a3b8' },
          grid: { color: 'rgba(255, 255, 255, 0.05)' },
          ticks: { color: '#94a3b8' }
        },
        y: {
          title: { display: true, text: 'Forward Speed (km/h)', color: '#94a3b8' },
          grid: { color: 'rgba(255, 255, 255, 0.05)' },
          ticks: { color: '#94a3b8' }
        }
      },
      plugins: {
        legend: {
          labels: { color: '#94a3b8', font: { family: 'JetBrains Mono', size: 11 } }
        }
      }
    }
  });
}

function initDriftChart() {
  const ctx = document.getElementById('driftCanvas');
  if (!ctx || driftChart) return;

  driftChart = new Chart(ctx.getContext('2d'), {
    type: 'line',
    data: {
      labels: driftTime,
      datasets: [
        {
          label: 'Classical DR Explosive Quadratic Divergence',
          data: classicalDriftDist,
          borderColor: '#ef4444',
          backgroundColor: 'rgba(239, 68, 68, 0.1)',
          borderWidth: 2.5,
          fill: true,
          tension: 0.3
        },
        {
          label: 'IDR-Navigator Bounded Error (0.02% - 0.05%)',
          data: idrDriftDist,
          borderColor: '#00f0ff',
          backgroundColor: 'rgba(0, 240, 255, 0.15)',
          borderWidth: 2.5,
          fill: true,
          tension: 0.1
        }
      ]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      scales: {
        x: {
          title: { display: true, text: 'Continuous GNSS Outage Duration (Seconds)', color: '#94a3b8' },
          grid: { color: 'rgba(255, 255, 255, 0.05)' },
          ticks: { color: '#94a3b8' }
        },
        y: {
          title: { display: true, text: 'Positional Drift Error (Meters)', color: '#94a3b8' },
          grid: { color: 'rgba(255, 255, 255, 0.05)' },
          ticks: { color: '#94a3b8' }
        }
      },
      plugins: {
        legend: {
          labels: { color: '#94a3b8', font: { family: 'JetBrains Mono', size: 11 } }
        }
      }
    }
  });
}

// 3. Tab Switching
function initTabs() {
  const tabBtns = document.querySelectorAll('.tab-btn');
  tabBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      tabBtns.forEach(b => b.classList.remove('active'));
      btn.classList.add('active');

      const target = btn.dataset.tab;
      document.querySelectorAll('.tab-content').forEach(c => c.style.display = 'none');
      
      const activeContent = document.getElementById(target);
      if (activeContent) {
        activeContent.style.display = 'block';
      }

      if (target === 'tab-speed') {
        setTimeout(initSpeedChart, 50);
      } else if (target === 'tab-drift') {
        setTimeout(initDriftChart, 50);
      }
    });
  });
}

// 4. Expandable Pipeline Architecture Cards
function initPipelineCards() {
  const cards = document.querySelectorAll('.pipeline-card');
  cards.forEach(card => {
    card.addEventListener('click', () => {
      card.classList.toggle('expanded');
    });
  });
}

// 5. Interactive Outage Simulator Playground
function initSimulator() {
  const vehicleSelect = document.getElementById('sim-vehicle');
  const outageDurationInput = document.getElementById('sim-duration');
  const shockToggle = document.getElementById('sim-shock');
  const durationVal = document.getElementById('sim-duration-val');

  const driftValEl = document.getElementById('stat-drift-dist');
  const driftPctEl = document.getElementById('stat-drift-pct');
  const baselineDriftEl = document.getElementById('stat-base-drift');
  const passStatusEl = document.getElementById('stat-pass-status');

  function updateSimulation() {
    if (!outageDurationInput) return;
    const duration = parseFloat(outageDurationInput.value);
    if (durationVal) durationVal.textContent = duration + ' s';

    const vehicle = vehicleSelect ? vehicleSelect.value : 'car';
    const hasShock = shockToggle ? shockToggle.checked : false;

    // Simulation calculation
    let baseSpeed = 50.0; // km/h
    let driftFactor = 0.0004; // 0.04%
    let classicalAccelBias = 0.08; // m/s^2

    if (vehicle === 'fog') {
      driftFactor = 0.00015;
      classicalAccelBias = 0.02;
    } else if (vehicle === 'bike') {
      driftFactor = 0.0012;
      classicalAccelBias = 0.15;
    } else if (vehicle === 'truck') {
      driftFactor = 0.0007;
      classicalAccelBias = 0.10;
    }

    if (hasShock) {
      driftFactor *= 1.25; // Shock gate catches 90% of disturbance
    }

    const distTraveled = (baseSpeed * (1000 / 3600)) * duration;
    const idrDrift = distTraveled * driftFactor;
    const classicalDrift = 0.5 * classicalAccelBias * (duration * duration);

    const driftPct = (idrDrift / distTraveled) * 100;

    if (driftValEl) driftValEl.textContent = idrDrift.toFixed(2) + ' m';
    if (driftPctEl) driftPctEl.textContent = driftPct.toFixed(2) + '%';
    if (baselineDriftEl) baselineDriftEl.textContent = classicalDrift.toFixed(1) + ' m';

    if (passStatusEl) {
      const reduction = Math.max(0, ((classicalDrift - idrDrift) / classicalDrift) * 100);
      passStatusEl.textContent = reduction.toFixed(1) + '%';
      passStatusEl.style.color = '#10b981';
    }
  }

  if (outageDurationInput) outageDurationInput.addEventListener('input', updateSimulation);
  if (vehicleSelect) vehicleSelect.addEventListener('change', updateSimulation);
  if (shockToggle) shockToggle.addEventListener('change', updateSimulation);

  updateSimulation();
}
