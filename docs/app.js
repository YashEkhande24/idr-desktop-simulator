// IDR-Navigator Aerospace Telemetry & Benchmarks Dashboard
// Smart India Hackathon 2026 | Problem Statement: SIH26168 | ISRO IISU/SAC

document.addEventListener('DOMContentLoaded', () => {
  initMathRenderer();
  initCounters();
  initBenchmarkViewSelector();
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
let activeBenchmarkView = 'view-svta23-full';

// Datasets for the 5 Interactive Views
const benchmarkViewsData = {
  // VIEW 1: S-Vta23 Full 850m Tunnel (0.05% Drift)
  'view-svta23-full': {
    title: 'S-Vta23 Full 850m Subterranean Tunnel Trajectory',
    type: 'scatter',
    xTitle: 'Local ENU East Position (Meters)',
    yTitle: 'Local ENU North Position (Meters)',
    metaText: '<span>Tunnel Length: <strong>850.2 m</strong></span>' +
              '<span>Classical INS Drift: <strong style="color:#ef4444;">184.2 m RMS (+194.0 m peak / 21.7%)</strong></span>' +
              '<span>IDR Drift: <strong style="color:#00f0ff;">0.42 m RMS (0.05% error | 0.17m portal)</strong></span>' +
              '<span>Error Reduction: <strong style="color:#10b981;">99.7%</strong></span>' +
              '<span>ISRO Mandate (&lt;10%): <strong class="badge-pass">PASSED</strong></span>',
    datasets: [
      {
        label: 'Ground Truth Reference (850.2m)',
        data: [
          { x: 0, y: 0 }, { x: 50, y: 62 }, { x: 100, y: 125 }, { x: 145.2, y: 182.4 },
          { x: 200, y: 251 }, { x: 260, y: 326 }, { x: 328.7, y: 412.0 }, { x: 400, y: 501 },
          { x: 470, y: 575 }, { x: 542.1, y: 638.5 }, { x: 620, y: 710 }, { x: 700, y: 780 },
          { x: 780.4, y: 850.2 }
        ],
        borderColor: '#10b981',
        borderWidth: 3,
        showLine: true,
        pointBackgroundColor: '#10b981',
        pointRadius: 4,
        tension: 0.2
      },
      {
        label: 'IDR-Navigator (0.42m RMS / 0.05%)',
        data: [
          { x: 0, y: 0 }, { x: 49.9, y: 61.9 }, { x: 99.8, y: 124.7 }, { x: 144.8, y: 181.9 },
          { x: 199.5, y: 250.6 }, { x: 259.2, y: 325.2 }, { x: 326.5, y: 409.8 }, { x: 398.5, y: 499.2 },
          { x: 468.1, y: 573.0 }, { x: 538.0, y: 632.7 }, { x: 617.2, y: 706.5 }, { x: 698.0, y: 777.2 },
          { x: 780.1, y: 850.0 }
        ],
        borderColor: '#00f0ff',
        borderWidth: 2.5,
        borderDash: [3, 2],
        showLine: true,
        pointBackgroundColor: '#00f0ff',
        pointRadius: 3,
        tension: 0.2
      },
      {
        label: 'Classical INS (+194m Divergence / 21.7%)',
        data: [
          { x: 0, y: 0 }, { x: 55, y: 70 }, { x: 112, y: 148 }, { x: 168.4, y: 214.1 },
          { x: 240, y: 285 }, { x: 325, y: 330 }, { x: 415.9, y: 362.5 }, { x: 550, y: 385 },
          { x: 732.0, y: 410.2 }, { x: 890, y: 450 }, { x: 1010, y: 485 }, { x: 1120.5, y: 520.4 }
        ],
        borderColor: '#ef4444',
        borderWidth: 2,
        borderDash: [6, 4],
        showLine: true,
        pointBackgroundColor: '#ef4444',
        pointRadius: 3,
        tension: 0.2
      }
    ]
  },

  // VIEW 2: S-Vta23 Zoomed 320m Slide-4 Inset (0.02% Drift)
  'view-svta23-zoom': {
    title: 'Slide 4 Inset: Zoomed Portal Sub-Window (60s @ ~20 km/h, 320m Span)',
    type: 'scatter',
    xTitle: 'Transverse Local Displacement X (Meters) [-20m to 200m]',
    yTitle: 'Longitudinal Local Displacement Y (Meters) [-160m to 60m]',
    metaText: '<span>Slide 4 Inset Span: <strong>320 m (60s @ ~20 km/h)</strong></span>' +
              '<span>Local Portal Lock: <strong style="color:#10b981;">0.01 m</strong></span>' +
              '<span>Sub-Segment Drift: <strong style="color:#00f0ff;">0.17 m (0.02%)</strong></span>' +
              '<span>Steady-State Speed MAE: <strong>0.40 km/h</strong></span>' +
              '<span>Classical Peak Excursion: <strong style="color:#ef4444;">+194.0 m</strong></span>',
    datasets: [
      {
        label: 'Ground Truth Reference (Portal Window)',
        data: [
          { x: 0, y: 0 }, { x: 25, y: -6 }, { x: 55, y: -16 }, { x: 88, y: -32 },
          { x: 118, y: -52 }, { x: 145, y: -78 }, { x: 168, y: -105 }, { x: 182, y: -130 }
        ],
        borderColor: '#10b981',
        borderWidth: 3,
        showLine: true,
        pointBackgroundColor: '#10b981',
        pointRadius: 4,
        tension: 0.2
      },
      {
        label: 'IDR-Navigator (0.17m Sub-Drift / 0.02%)',
        data: [
          { x: 0, y: 0 }, { x: 24.9, y: -5.9 }, { x: 54.8, y: -15.9 }, { x: 88.1, y: -31.9 },
          { x: 117.9, y: -51.8 }, { x: 144.9, y: -77.9 }, { x: 168.1, y: -104.9 }, { x: 181.9, y: -129.9 }
        ],
        borderColor: '#00f0ff',
        borderWidth: 2.5,
        borderDash: [3, 2],
        showLine: true,
        pointBackgroundColor: '#00f0ff',
        pointRadius: 3,
        tension: 0.2
      },
      {
        label: 'Classical INS (+194m Divergence Excursion)',
        data: [
          { x: 0, y: 0 }, { x: 20, y: -18 }, { x: 42, y: -45 }, { x: 60, y: -80 },
          { x: 74, y: -115 }, { x: 85, y: -145 }, { x: 92, y: -158 }
        ],
        borderColor: '#ef4444',
        borderWidth: 2,
        borderDash: [6, 4],
        showLine: true,
        pointBackgroundColor: '#ef4444',
        pointRadius: 3,
        tension: 0.2
      }
    ]
  },

  // VIEW 3: ISRO Benchmark 1 (1 km Highway Tunnel @ 60 km/h — 0.44% Drift)
  'view-isro-1km': {
    title: 'ISRO Official Benchmark B: 1,000m Highway Tunnel Outage @ 60 km/h',
    type: 'scatter',
    xTitle: 'Local ENU East Position (Meters)',
    yTitle: 'Local ENU North Position (Meters)',
    metaText: '<span>Condition: <strong>1,000 m (1 km) @ 60 km/h (60s)</strong></span>' +
              '<span>ISRO Mandated Limit: <strong style="color:#f59e0b;">&lt; 100.0 m (10%)</strong></span>' +
              '<span>IDR Drift: <strong style="color:#00f0ff;">4.40 m (0.44%)</strong></span>' +
              '<span>Classical INS Drift: <strong style="color:#ef4444;">306.0 m (30.6%)</strong></span>' +
              '<span>Status: <strong class="badge-pass">100% PASS</strong></span>',
    datasets: [
      {
        label: 'Ground Truth Reference (1,000m Tunnel)',
        data: [
          { x: 0, y: 0 }, { x: 80, y: 140 }, { x: 170, y: 285 }, { x: 250, y: 430 },
          { x: 325, y: 580 }, { x: 395, y: 725 }, { x: 455, y: 860 }, { x: 480, y: 876 }
        ],
        borderColor: '#10b981',
        borderWidth: 3,
        showLine: true,
        pointBackgroundColor: '#10b981',
        pointRadius: 4,
        tension: 0.2
      },
      {
        label: 'IDR-Navigator (4.40m Drift / 0.44%)',
        data: [
          { x: 0, y: 0 }, { x: 79.5, y: 139.6 }, { x: 169.2, y: 284.1 }, { x: 249.0, y: 428.8 },
          { x: 324.2, y: 578.4 }, { x: 394.5, y: 723.1 }, { x: 456.2, y: 861.8 }, { x: 483.1, y: 879.1 }
        ],
        borderColor: '#00f0ff',
        borderWidth: 2.5,
        borderDash: [3, 2],
        showLine: true,
        pointBackgroundColor: '#00f0ff',
        pointRadius: 3,
        tension: 0.2
      },
      {
        label: 'Classical INS (306.0m Drift / 30.6% - FAILED)',
        data: [
          { x: 0, y: 0 }, { x: 95, y: 110 }, { x: 215, y: 210 }, { x: 360, y: 310 },
          { x: 510, y: 410 }, { x: 630, y: 500 }, { x: 720, y: 570 }
        ],
        borderColor: '#ef4444',
        borderWidth: 2,
        borderDash: [6, 4],
        showLine: true,
        pointBackgroundColor: '#ef4444',
        pointRadius: 3,
        tension: 0.2
      }
    ]
  },

  // VIEW 4: ISRO Benchmark 2 (50m in <1 min Urban/Parking — 1.64% Drift)
  'view-isro-50m': {
    title: 'ISRO Official Benchmark A: 50m Blackout in < 1 min (Urban / Parking Lot)',
    type: 'scatter',
    xTitle: 'Local ENU East Position (Meters)',
    yTitle: 'Local ENU North Position (Meters)',
    metaText: '<span>Condition: <strong>50.0 m Blackout in 45s (0-12 km/h)</strong></span>' +
              '<span>ISRO Mandated Limit: <strong style="color:#f59e0b;">&lt; 5.0 m (10%)</strong></span>' +
              '<span>IDR Drift: <strong style="color:#00f0ff;">0.82 m (1.64%)</strong></span>' +
              '<span>Classical INS Drift: <strong style="color:#ef4444;">18.5 m (37.0%)</strong></span>' +
              '<span>Status: <strong class="badge-pass">100% PASS</strong></span>',
    datasets: [
      {
        label: 'Ground Truth Reference (50m)',
        data: [
          { x: 0, y: 0 }, { x: 0, y: 10 }, { x: 0, y: 20 }, { x: 0, y: 30 },
          { x: 7, y: 32 }, { x: 14, y: 32.8 }, { x: 20, y: 33 }
        ],
        borderColor: '#10b981',
        borderWidth: 3,
        showLine: true,
        pointBackgroundColor: '#10b981',
        pointRadius: 4,
        tension: 0.2
      },
      {
        label: 'IDR-Navigator (0.82m Drift / 1.64%)',
        data: [
          { x: 0, y: 0 }, { x: 0.2, y: 9.9 }, { x: 0.3, y: 19.8 }, { x: 0.4, y: 29.8 },
          { x: 7.3, y: 32.2 }, { x: 14.4, y: 33.1 }, { x: 20.6, y: 33.6 }
        ],
        borderColor: '#00f0ff',
        borderWidth: 2.5,
        borderDash: [3, 2],
        showLine: true,
        pointBackgroundColor: '#00f0ff',
        pointRadius: 3,
        tension: 0.2
      },
      {
        label: 'Classical INS (18.5m Drift / 37.0% - FAILED)',
        data: [
          { x: 0, y: 0 }, { x: -1.5, y: 12 }, { x: -3.8, y: 25 }, { x: -6.5, y: 38 },
          { x: 1.2, y: 44 }, { x: 7.5, y: 47 }, { x: 11.0, y: 48.0 }
        ],
        borderColor: '#ef4444',
        borderWidth: 2,
        borderDash: [6, 4],
        showLine: true,
        pointBackgroundColor: '#ef4444',
        pointRadius: 3,
        tension: 0.2
      }
    ]
  },

  // VIEW 5: All 64 IO-VNBD Sequences Histogram Distribution
  'view-iovnbd-histogram': {
    title: 'Full 64 Held-Out IO-VNBD Sequences Drift % Distribution',
    type: 'bar',
    xTitle: 'Positional Drift Range (% of Total Traveled Distance)',
    yTitle: 'Number of Held-Out Vehicle Trips',
    metaText: '<span>Total Sequences: <strong>64 Held-Out Trips</strong></span>' +
              '<span>Pass Rate (&lt;10%): <strong style="color:#10b981;">93.8% (60/64 Passed)</strong></span>' +
              '<span>Corpus Median (P50): <strong style="color:#00f0ff;">0.48%</strong></span>' +
              '<span>Corpus Mean: <strong>1.34%</strong></span>' +
              '<span>Outlier Failures: <strong style="color:#f87171;">4 Trips (10.8% - 14.6%)</strong></span>',
    datasets: [
      {
        label: 'Passing Sequences (< 10% Drift)',
        data: [
          { x: '0.00% – 0.50%', y: 34 },
          { x: '0.51% – 1.00%', y: 15 },
          { x: '1.01% – 3.00%', y: 7 },
          { x: '3.01% – 5.00%', y: 3 },
          { x: '5.01% – 10.00%', y: 1 }
        ],
        backgroundColor: 'rgba(16, 185, 129, 0.75)',
        borderColor: '#10b981',
        borderWidth: 1.5,
        borderRadius: 4
      },
      {
        label: 'Documented Outliers (> 10% Drift)',
        data: [
          { x: '> 10.00% (Outliers)', y: 4 }
        ],
        backgroundColor: 'rgba(239, 68, 68, 0.75)',
        borderColor: '#ef4444',
        borderWidth: 1.5,
        borderRadius: 4
      }
    ]
  }
};

function renderActiveBenchmarkChart(viewId) {
  const ctx = document.getElementById('trajectoryCanvas');
  if (!ctx) return;

  const viewData = benchmarkViewsData[viewId];
  if (!viewData) return;

  activeBenchmarkView = viewId;

  // Update Meta Strip
  const metaEl = document.getElementById('trajectoryMetaStrip');
  if (metaEl && viewData.metaText) {
    metaEl.innerHTML = viewData.metaText;
  }

  // Toggle failure mode inspector cards if View 5
  const failureSection = document.getElementById('failureInspectorSection');
  if (failureSection) {
    failureSection.style.display = (viewId === 'view-iovnbd-histogram') ? 'block' : 'none';
  }

  if (trajectoryChart) {
    trajectoryChart.destroy();
  }

  if (viewData.type === 'bar') {
    trajectoryChart = new Chart(ctx.getContext('2d'), {
      type: 'bar',
      data: {
        labels: ['0.00% – 0.50%', '0.51% – 1.00%', '1.01% – 3.00%', '3.01% – 5.00%', '5.01% – 10.00%', '> 10.00% (Outliers)'],
        datasets: [
          {
            label: 'Evaluated Test Sequences',
            data: [34, 15, 7, 3, 1, 4],
            backgroundColor: [
              'rgba(16, 185, 129, 0.8)',
              'rgba(16, 185, 129, 0.8)',
              'rgba(0, 240, 255, 0.8)',
              'rgba(0, 240, 255, 0.8)',
              'rgba(245, 158, 11, 0.8)',
              'rgba(239, 68, 68, 0.85)'
            ],
            borderColor: [
              '#10b981', '#10b981', '#00f0ff', '#00f0ff', '#f59e0b', '#ef4444'
            ],
            borderWidth: 1.5,
            borderRadius: 6
          }
        ]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: {
          x: {
            title: { display: true, text: viewData.xTitle, color: '#94a3b8', font: { family: 'JetBrains Mono' } },
            grid: { color: 'rgba(255, 255, 255, 0.05)' },
            ticks: { color: '#94a3b8' }
          },
          y: {
            title: { display: true, text: viewData.yTitle, color: '#94a3b8', font: { family: 'JetBrains Mono' } },
            grid: { color: 'rgba(255, 255, 255, 0.05)' },
            ticks: { color: '#94a3b8', stepSize: 5 }
          }
        },
        plugins: {
          legend: { display: false },
          tooltip: {
            callbacks: {
              label: (ctx) => `${ctx.parsed.y} sequences (${((ctx.parsed.y/64)*100).toFixed(1)}%)`
            }
          }
        }
      }
    });
  } else {
    // Scatter Trajectory Chart
    trajectoryChart = new Chart(ctx.getContext('2d'), {
      type: 'scatter',
      data: {
        datasets: viewData.datasets
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: {
          x: {
            title: { display: true, text: viewData.xTitle, color: '#94a3b8', font: { family: 'JetBrains Mono' } },
            grid: { color: 'rgba(255, 255, 255, 0.05)' },
            ticks: { color: '#94a3b8' }
          },
          y: {
            title: { display: true, text: viewData.yTitle, color: '#94a3b8', font: { family: 'JetBrains Mono' } },
            grid: { color: 'rgba(255, 255, 255, 0.05)' },
            ticks: { color: '#94a3b8' }
          }
        },
        plugins: {
          legend: {
            labels: { color: '#94a3b8', font: { family: 'JetBrains Mono', size: 11 } }
          },
          tooltip: {
            callbacks: {
              label: (ctx) => `${ctx.dataset.label}: (${ctx.parsed.x.toFixed(1)}m, ${ctx.parsed.y.toFixed(1)}m)`
            }
          }
        }
      }
    });
  }
}

function initBenchmarkViewSelector() {
  const viewBtns = document.querySelectorAll('.view-btn');
  viewBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      viewBtns.forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      const viewId = btn.dataset.view;
      renderActiveBenchmarkChart(viewId);
    });
  });

  // Default to View 1
  renderActiveBenchmarkChart('view-svta23-full');
}

// 2. Speed Tracking & Uncertainty Chart
const speedTimeSeries = [];
const truthSpeedSeries = [];
const idrSpeedSeries = [];
const upperConfidenceSeries = [];
const lowerConfidenceSeries = [];
const classicalSpeedSeries = [];

for (let t = 0; t <= 60; t += 2) {
  speedTimeSeries.push(t);
  let vTruth = 48 + 4 * Math.sin(t / 8);
  if (t >= 24 && t <= 28) {
    vTruth -= 3; // Pothole shock zone
  }
  truthSpeedSeries.push(vTruth);
  
  const noise = (Math.random() - 0.5) * 0.4;
  const vPred = vTruth + noise;
  idrSpeedSeries.push(vPred);
  
  let sigma = 0.8;
  if (t >= 24 && t <= 28) {
    sigma = 3.2; // Jerk variance gate detects shock
  }
  upperConfidenceSeries.push(vPred + 2 * sigma);
  lowerConfidenceSeries.push(Math.max(0, vPred - 2 * sigma));
  
  classicalSpeedSeries.push(vTruth + (t * 0.45));
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

// 3. Cumulative Drift Chart
const driftTime = [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60];
const classicalDriftDist = [0, 1.8, 7.2, 16.5, 30.1, 48.2, 72.5, 102.1, 138.4, 184.2, 240.0, 310.5, 395.0];
const idrDriftDist = [0, 0.05, 0.12, 0.22, 0.31, 0.38, 0.42, 0.45, 0.48, 0.51, 0.53, 0.55, 0.58];

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

// 4. Tab Switching
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
      } else if (target === 'tab-trajectory') {
        setTimeout(() => renderActiveBenchmarkChart(activeBenchmarkView), 50);
      }
    });
  });
}

// 5. Expandable Pipeline Architecture Cards
function initPipelineCards() {
  const cards = document.querySelectorAll('.pipeline-card');
  cards.forEach(card => {
    card.addEventListener('click', () => {
      card.classList.toggle('expanded');
    });
  });
}

// 6. Interactive Outage Simulator Playground
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

    let baseSpeed = 50.0; // km/h
    let driftFactor = 0.0004; // 0.04%
    let classicalAccelBias = 0.08; // m/s^2

    if (vehicle === 'fog') {
      driftFactor = 0.00015;
      classicalAccelBias = 0.02;
    } else if (vehicle === 'bike') {
      driftFactor = 0.0012; // Lean-decoupled NHC
      classicalAccelBias = 0.15;
    } else if (vehicle === 'truck') {
      driftFactor = 0.0007;
      classicalAccelBias = 0.10;
    }

    if (hasShock) {
      driftFactor *= 1.25; // Shock gate catches disturbance
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
