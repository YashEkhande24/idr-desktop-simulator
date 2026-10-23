/**
 * IDR-NAVIGATOR — UNIFIED FRONTEND APPLICATION
 * Smart India Hackathon 2026 | Team Inventor #133715 | ISRO IISU/SAC
 * Grounded in idr_model_submission/results.json
 */

document.addEventListener('DOMContentLoaded', () => {
  initMobileMenu();
  initScrollSpy();
  initBenchmarkChart();
  initVideoControls();
});

/* --------------------------------------------------------------------------
   1. Mobile Navigation Menu Toggle
   -------------------------------------------------------------------------- */
function initMobileMenu() {
  const toggleBtn = document.getElementById('menuToggle');
  const navLinks = document.getElementById('navLinks');
  if (!toggleBtn || !navLinks) return;

  toggleBtn.addEventListener('click', () => {
    const isVisible = navLinks.style.display === 'flex';
    navLinks.style.display = isVisible ? 'none' : 'flex';
    if (!isVisible) {
      navLinks.style.position = 'absolute';
      navLinks.style.top = '64px';
      navLinks.style.left = '0';
      navLinks.style.right = '0';
      navLinks.style.flexDirection = 'column';
      navLinks.style.background = 'var(--bg-glass)';
      navLinks.style.padding = '1.5rem';
      navLinks.style.borderBottom = '1px solid var(--border-subtle)';
      navLinks.style.gap = '1rem';
    }
  });

  navLinks.querySelectorAll('a').forEach(link => {
    link.addEventListener('click', () => {
      if (window.innerWidth <= 768) {
        navLinks.style.display = 'none';
      }
    });
  });
}

/* --------------------------------------------------------------------------
   2. Active Scroll Spy
   -------------------------------------------------------------------------- */
function initScrollSpy() {
  const sections = document.querySelectorAll('section[id]');
  const navLinks = document.querySelectorAll('.nav-links a[href^="#"]');

  window.addEventListener('scroll', () => {
    let current = '';
    const scrollPos = window.scrollY + 100;

    sections.forEach(section => {
      const top = section.offsetTop;
      const height = section.offsetHeight;
      if (scrollPos >= top && scrollPos < top + height) {
        current = section.getAttribute('id');
      }
    });

    navLinks.forEach(link => {
      link.classList.remove('active');
      if (link.getAttribute('href') === `#${current}`) {
        link.classList.add('active');
      }
    });
  }, { passive: true });
}

/* --------------------------------------------------------------------------
   3. Verified Benchmark Chart (Chart.js)
   -------------------------------------------------------------------------- */
function initBenchmarkChart() {
  const ctx = document.getElementById('benchmarkChart');
  if (!ctx || typeof Chart === 'undefined') return;

  // Real ground truth numbers from idr_model_submission/results.json
  // compared against unconstrained open-loop double integration
  const labels = [
    'Highway Tunnel',
    'Urban Stop & Go',
    'Interstate Cruise',
    'Winding Road',
    'Two-Wheeler Urban'
  ];

  const idrDrift = [0.43, 2.38, 0.80, 4.68, 9.08];
  const classicalDrift = [28.5, 42.1, 24.3, 65.4, 88.7];

  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: labels,
      datasets: [
        {
          label: 'IDR-Navigator (Proposed)',
          data: idrDrift,
          backgroundColor: 'rgba(16, 185, 129, 0.85)',
          borderColor: '#10b981',
          borderWidth: 1,
          borderRadius: 6
        },
        {
          label: 'Classical Double-Integration',
          data: classicalDrift,
          backgroundColor: 'rgba(244, 63, 94, 0.45)',
          borderColor: '#f43f5e',
          borderWidth: 1,
          borderRadius: 6
        }
      ]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      interaction: {
        mode: 'index',
        intersect: false
      },
      plugins: {
        legend: {
          position: 'top',
          labels: {
            color: '#94a3b8',
            font: { family: 'Inter', size: 12 },
            boxWidth: 12,
            padding: 14
          }
        },
        tooltip: {
          backgroundColor: '#0f172a',
          titleColor: '#f8fafc',
          bodyColor: '#cbd5e1',
          borderColor: 'rgba(255,255,255,0.1)',
          borderWidth: 1,
          callbacks: {
            label: function (context) {
              return `${context.dataset.label}: ${context.parsed.y.toFixed(2)}% drift`;
            }
          }
        }
      },
      scales: {
        x: {
          grid: { display: false },
          ticks: {
            color: '#94a3b8',
            font: { family: 'Inter', size: 11 }
          }
        },
        y: {
          title: {
            display: true,
            text: 'Positional Drift (% of distance)',
            color: '#64748b',
            font: { family: 'Inter', size: 11 }
          },
          grid: {
            color: 'rgba(255, 255, 255, 0.05)'
          },
          ticks: {
            color: '#94a3b8',
            font: { family: 'JetBrains Mono', size: 11 },
            callback: value => value + '%'
          },
          suggestedMax: 100
        }
      }
    }
  });
}

/* --------------------------------------------------------------------------
   4. Video Player & Jump Controller with GA4 Telemetry Tracking
   -------------------------------------------------------------------------- */
function initVideoControls() {
  const video = document.getElementById('demoVideo');
  if (!video) return;

  const milestones = { 25: false, 50: false, 75: false, 100: false };

  video.addEventListener('play', () => {
    if (typeof gtag === 'function') {
      gtag('event', 'video_play', {
        video_title: 'Synchronized Dual-Feed HUD Field Demonstration',
        video_current_time: Math.round(video.currentTime),
        video_duration: Math.round(video.duration || 359)
      });
    }
  });

  video.addEventListener('pause', () => {
    if (video.currentTime < (video.duration || 359) - 1) {
      if (typeof gtag === 'function') {
        gtag('event', 'video_pause', {
          video_title: 'Synchronized Dual-Feed HUD Field Demonstration',
          video_current_time: Math.round(video.currentTime)
        });
      }
    }
  });

  video.addEventListener('timeupdate', () => {
    if (!video.duration) return;
    const pct = Math.floor((video.currentTime / video.duration) * 100);
    [25, 50, 75, 100].forEach(m => {
      if (pct >= m && !milestones[m]) {
        milestones[m] = true;
        if (typeof gtag === 'function') {
          gtag('event', 'video_progress', {
            video_title: 'Synchronized Dual-Feed HUD Field Demonstration',
            video_percent: m,
            video_current_time: Math.round(video.currentTime)
          });
        }
      }
    });
  });

  video.addEventListener('ended', () => {
    if (typeof gtag === 'function') {
      gtag('event', 'video_complete', {
        video_title: 'Synchronized Dual-Feed HUD Field Demonstration',
        video_duration: Math.round(video.duration || 359)
      });
    }
  });

  const jumpButtons = document.querySelectorAll('[data-jump-time]');
  jumpButtons.forEach(btn => {
    btn.addEventListener('click', () => {
      const time = parseFloat(btn.getAttribute('data-jump-time'));
      const chapterLabel = btn.innerText.trim();
      if (!isNaN(time)) {
        video.currentTime = time;
        video.play();
        if (typeof gtag === 'function') {
          gtag('event', 'video_chapter_jump', {
            chapter_name: chapterLabel,
            jump_time_sec: time
          });
        }
      }
    });
  });
}
