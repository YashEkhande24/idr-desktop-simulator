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
   4. Bespoke Cinema Telemetry Video Player & Chapter Controller (SIH26168)
   -------------------------------------------------------------------------- */
function initVideoControls() {
  const video = document.getElementById('demoVideo');
  if (!video) return;

  const player = document.getElementById('customMediaPlayer');

  // Prevent duplicate native caption rendering since subtitles are burned into HUD recording
  const disableTracks = () => {
    if (video.textTracks) {
      for (let i = 0; i < video.textTracks.length; i++) {
        video.textTracks[i].mode = 'disabled';
      }
    }
  };
  disableTracks();
  video.addEventListener('loadedmetadata', disableTracks);

  // Chapter Timeline Definitions
  const CHAPTERS = [
    { time: 0, title: "Phase 1: Baseline Lock" },
    { time: 7, title: "Phase 2: Intentional GNSS Severing" },
    { time: 26, title: "Phase 1b: Dual-Feed Orientation" },
    { time: 44, title: "Phase 3: Outage Banner & Neural Takeover" },
    { time: 68, title: "Phase 4: Highway Traversal & Lane Clamping" },
    { time: 96, title: "Phase 5: Road Bumps & Jerk Gating" },
    { time: 120, title: "Phase 6: Standstill ZUPT Detection" },
    { time: 185, title: "Phase 7: Sustained Outage Tracking" },
    { time: 211, title: "Phase 8: Trial 02 Sangamner Bypass Start" },
    { time: 232, title: "Phase 9: High-Speed Curvature & Banking" },
    { time: 275, title: "Phase 10: Zero External Wires Inspection" },
    { time: 315, title: "Phase 11: Long-Distance Blackout Stability" },
    { time: 345, title: "Phase 12: Terminus & Summary" }
  ];

  // Helper: Format MM:SS
  const formatTime = (seconds) => {
    if (isNaN(seconds) || seconds < 0) return "00:00";
    const m = Math.floor(seconds / 60);
    const s = Math.floor(seconds % 60);
    return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
  };

  // Helper: Format MM:SS.ss (timecode ticker)
  const formatTimecode = (seconds) => {
    if (isNaN(seconds) || seconds < 0) return "00:00.00";
    const m = Math.floor(seconds / 60);
    const s = Math.floor(seconds % 60);
    const ms = Math.floor((seconds % 1) * 100);
    return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}.${String(ms).padStart(2, '0')}`;
  };

  // GA4 Telemetry Tracking
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

  video.addEventListener('ended', () => {
    if (typeof gtag === 'function') {
      gtag('event', 'video_complete', {
        video_title: 'Synchronized Dual-Feed HUD Field Demonstration',
        video_duration: Math.round(video.duration || 359)
      });
    }
  });

  // If bespoke media player DOM exists, wire all custom UI components
  if (player) {
    const stage = document.getElementById('playerStage');
    const bigPlayOverlay = document.getElementById('playerBigPlayOverlay');
    const playPauseBtn = document.getElementById('ctrlPlayPauseBtn');
    const rewindBtn = document.getElementById('ctrlRewindBtn');
    const forwardBtn = document.getElementById('ctrlForwardBtn');
    const volumeBtn = document.getElementById('ctrlVolumeBtn');
    const volumeContainer = document.getElementById('volumeContainer');
    const volumeSlider = document.getElementById('volumeSlider');
    const currentTimeEl = document.getElementById('currentTime');
    const totalDurationEl = document.getElementById('totalDuration');
    const currentChapterNameEl = document.getElementById('currentChapterName');
    const liveTimecodeEl = document.getElementById('playerLiveTimecode');
    const speedBadgeEl = document.getElementById('playerSpeedBadge');
    const audioBadgeEl = document.getElementById('playerAudioBadge');
    const speedBtn = document.getElementById('ctrlSpeedBtn');
    const speedMenu = document.getElementById('speedMenu');
    const captionsBtn = document.getElementById('ctrlCaptionsBtn');
    const pipBtn = document.getElementById('ctrlPipBtn');
    const theatreBtn = document.getElementById('ctrlTheatreBtn');
    const theatreSection = document.getElementById('theatreSection');
    const fullscreenBtn = document.getElementById('ctrlFullscreenBtn');
    const controlsContainer = document.getElementById('playerControls');
    const scrubberWrapper = document.getElementById('scrubberWrapper');
    const scrubberProgress = document.getElementById('scrubberProgress');
    const scrubberBuffered = document.getElementById('scrubberBuffered');
    const scrubberMarkers = document.getElementById('scrubberMarkers');
    const scrubberTooltip = document.getElementById('scrubberTooltip');
    const actionSplash = document.getElementById('playerActionSplash');
    const actionSplashIcon = document.getElementById('actionSplashIcon');
    const chapterOsd = document.getElementById('playerChapterOsd');
    const osdText = document.getElementById('playerOsdText');
    const loader = document.getElementById('playerLoader');

    let isScrubbing = false;
    let autohideTimer = null;
    let osdTimer = null;
    const TOTAL_ESTIMATED_DURATION = 359;

    const getDuration = () => video.duration && !isNaN(video.duration) ? video.duration : TOTAL_ESTIMATED_DURATION;

    // Build chapter ticks on scrubber
    if (scrubberMarkers) {
      scrubberMarkers.innerHTML = '';
      CHAPTERS.forEach(ch => {
        const tick = document.createElement('div');
        tick.className = 'scrubber-tick';
        const pct = (ch.time / TOTAL_ESTIMATED_DURATION) * 100;
        tick.style.left = `${pct}%`;
        tick.title = `${formatTime(ch.time)} • ${ch.title}`;
        scrubberMarkers.appendChild(tick);
      });
    }

    // Flash Action Splash Icon (Play / Pause / Seek)
    const flashActionSplash = (iconType) => {
      if (!actionSplashIcon) return;
      if (iconType === 'play') {
        actionSplashIcon.innerHTML = '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>';
      } else if (iconType === 'pause') {
        actionSplashIcon.innerHTML = '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z"/></svg>';
      } else if (iconType === 'rewind') {
        actionSplashIcon.innerHTML = '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M11 17l-5-5 5-5M18 17l-5-5 5-5"/></svg>';
      } else if (iconType === 'forward') {
        actionSplashIcon.innerHTML = '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M13 17l5-5-5-5M6 17l5-5-5-5"/></svg>';
      }
      actionSplashIcon.classList.add('active');
      setTimeout(() => {
        actionSplashIcon.classList.remove('active');
      }, 400);
    };

    // Show Chapter OSD Toast
    const showChapterOsd = (title) => {
      if (!chapterOsd || !osdText) return;
      osdText.textContent = title;
      chapterOsd.classList.add('visible');
      clearTimeout(osdTimer);
      osdTimer = setTimeout(() => {
        chapterOsd.classList.remove('visible');
      }, 2500);
    };

    // Play / Pause Toggle
    const togglePlay = () => {
      if (video.paused || video.ended) {
        video.play().catch(() => {});
        flashActionSplash('play');
      } else {
        video.pause();
        flashActionSplash('pause');
      }
    };

    // Play / Pause UI States
    video.addEventListener('play', () => {
      player.classList.add('playing');
      if (bigPlayOverlay) bigPlayOverlay.classList.add('hidden');
      resetAutohideTimer();
    });

    video.addEventListener('pause', () => {
      player.classList.remove('playing');
      if (bigPlayOverlay) bigPlayOverlay.classList.remove('hidden');
      showControls();
    });

    video.addEventListener('waiting', () => {
      if (loader) loader.classList.add('visible');
    });

    video.addEventListener('playing', () => {
      if (loader) loader.classList.remove('visible');
    });

    video.addEventListener('canplay', () => {
      if (loader) loader.classList.remove('visible');
    });

    // Time & Progress Updates
    video.addEventListener('timeupdate', () => {
      const dur = getDuration();
      const cur = video.currentTime;
      const pct = Math.min(100, Math.max(0, (cur / dur) * 100));

      if (scrubberProgress && !isScrubbing) {
        scrubberProgress.style.width = `${pct}%`;
      }
      if (currentTimeEl) currentTimeEl.textContent = formatTime(cur);
      if (totalDurationEl) totalDurationEl.textContent = formatTime(dur);
      if (liveTimecodeEl) liveTimecodeEl.textContent = `${formatTimecode(cur)} / ${formatTimecode(dur)}`;

      // Active Chapter Detection
      let activeChapter = CHAPTERS[0];
      for (let i = 0; i < CHAPTERS.length; i++) {
        if (cur >= CHAPTERS[i].time - 0.5) {
          activeChapter = CHAPTERS[i];
        }
      }

      if (currentChapterNameEl && currentChapterNameEl.textContent !== activeChapter.title) {
        currentChapterNameEl.textContent = activeChapter.title;
      }

      // Synchronize Chapter Pills below video
      const chapterPills = document.querySelectorAll('.trial-pill[data-jump-time]');
      chapterPills.forEach(pill => {
        const jumpTime = parseFloat(pill.getAttribute('data-jump-time'));
        if (jumpTime === activeChapter.time) {
          pill.classList.add('active-chapter');
        } else {
          pill.classList.remove('active-chapter');
        }
      });

      // GA4 Progress Milestones
      const progressInt = Math.floor(pct);
      [25, 50, 75, 100].forEach(m => {
        if (progressInt >= m && !milestones[m]) {
          milestones[m] = true;
          if (typeof gtag === 'function') {
            gtag('event', 'video_progress', {
              video_title: 'Synchronized Dual-Feed HUD Field Demonstration',
              video_percent: m,
              video_current_time: Math.round(cur)
            });
          }
        }
      });
    });

    // Buffer progress
    video.addEventListener('progress', () => {
      const dur = getDuration();
      if (video.buffered.length > 0) {
        const bufferedEnd = video.buffered.end(video.buffered.length - 1);
        const bufPct = Math.min(100, Math.max(0, (bufferedEnd / dur) * 100));
        if (scrubberBuffered) scrubberBuffered.style.width = `${bufPct}%`;
      }
    });

    // Volume & Mute Updates
    const updateVolumeUI = () => {
      const vol = video.volume;
      const isMuted = video.muted || vol === 0;
      if (volumeSlider) volumeSlider.value = isMuted ? 0 : vol;

      if (volumeContainer) {
        volumeContainer.classList.remove('muted', 'low');
        if (isMuted) {
          volumeContainer.classList.add('muted');
        } else if (vol < 0.5) {
          volumeContainer.classList.add('low');
        }
      }

      if (audioBadgeEl) {
        audioBadgeEl.textContent = isMuted ? "MUTED" : "STEREO AUDIO";
        audioBadgeEl.style.color = isMuted ? "#F87171" : "#94A3B8";
      }
    };

    video.addEventListener('volumechange', updateVolumeUI);

    if (volumeBtn) {
      volumeBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        video.muted = !video.muted;
        if (!video.muted && video.volume === 0) {
          video.volume = 0.8;
        }
      });
    }

    if (volumeSlider) {
      volumeSlider.addEventListener('input', (e) => {
        e.stopPropagation();
        const val = parseFloat(e.target.value);
        video.volume = val;
        video.muted = (val === 0);
      });
    }

    // Playback Speed Selector
    if (speedBtn && speedMenu) {
      speedBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        speedMenu.classList.toggle('open');
      });

      const speedOptions = speedMenu.querySelectorAll('.speed-opt');
      speedOptions.forEach(opt => {
        opt.addEventListener('click', (e) => {
          e.stopPropagation();
          const speed = parseFloat(opt.getAttribute('data-speed'));
          video.playbackRate = speed;
          speedBtn.textContent = `${speed}x`;
          if (speedBadgeEl) speedBadgeEl.textContent = `SPEED: ${speed}x`;
          speedOptions.forEach(o => o.classList.remove('active'));
          opt.classList.add('active');
          speedMenu.classList.remove('open');
        });
      });

      document.addEventListener('click', () => {
        speedMenu.classList.remove('open');
      });
    }

    // Fullscreen Toggle
    const toggleFullscreen = () => {
      if (!document.fullscreenElement && !document.webkitFullscreenElement) {
        if (player.requestFullscreen) {
          player.requestFullscreen().catch(() => {});
        } else if (player.webkitRequestFullscreen) {
          player.webkitRequestFullscreen();
        }
      } else {
        if (document.exitFullscreen) {
          document.exitFullscreen().catch(() => {});
        } else if (document.webkitExitFullscreen) {
          document.webkitExitFullscreen();
        }
      }
    };

    const handleFullscreenChange = () => {
      const isFs = !!(document.fullscreenElement || document.webkitFullscreenElement);
      player.classList.toggle('fullscreen', isFs);
    };

    document.addEventListener('fullscreenchange', handleFullscreenChange);
    document.addEventListener('webkitfullscreenchange', handleFullscreenChange);

    if (fullscreenBtn) {
      fullscreenBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        toggleFullscreen();
      });
    }

    // Picture-in-Picture
    if (pipBtn) {
      if ('pictureInPictureEnabled' in document) {
        pipBtn.addEventListener('click', async (e) => {
          e.stopPropagation();
          try {
            if (document.pictureInPictureElement) {
              await document.exitPictureInPicture();
            } else {
              await video.requestPictureInPicture();
            }
          } catch (err) {}
        });
      } else {
        pipBtn.style.display = 'none';
      }
    }

    // Captions Button Toggle Info
    if (captionsBtn) {
      captionsBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        showChapterOsd("Subtitles: Burned-in HD English CC Active");
      });
    }

    // YouTube Theatre Mode Toggle
    const toggleTheatre = () => {
      if (!theatreSection) return;
      theatreSection.classList.toggle('standard-mode');
      const isStandard = theatreSection.classList.contains('standard-mode');
      if (theatreBtn) {
        theatreBtn.setAttribute('title', isStandard ? 'Theatre mode (T)' : 'Default view (T)');
        theatreBtn.setAttribute('aria-label', isStandard ? 'Theatre mode (T)' : 'Default view (T)');
      }
      showChapterOsd(isStandard ? 'Standard View' : 'YouTube Theatre Mode');
    };

    if (theatreBtn) {
      theatreBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        toggleTheatre();
      });
    }

    // Skip Buttons
    if (rewindBtn) {
      rewindBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        video.currentTime = Math.max(0, video.currentTime - 10);
        flashActionSplash('rewind');
      });
    }

    if (forwardBtn) {
      forwardBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        video.currentTime = Math.min(getDuration(), video.currentTime + 10);
        flashActionSplash('forward');
      });
    }

    if (playPauseBtn) {
      playPauseBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        togglePlay();
      });
    }

    // Big Center Overlay & Stage Clicks
    if (bigPlayOverlay) {
      bigPlayOverlay.addEventListener('click', (e) => {
        e.stopPropagation();
        video.play().catch(() => {});
      });
    }

    if (stage) {
      stage.addEventListener('click', (e) => {
        // Prevent toggle if clicking inside controls bar
        if (e.target.closest('#playerControls') || e.target.closest('#playerBigPlayOverlay')) return;
        togglePlay();
      });

      stage.addEventListener('dblclick', (e) => {
        if (e.target.closest('#playerControls')) return;
        toggleFullscreen();
      });
    }

    // Scrubber Scrubbing & Hover Tooltip
    if (scrubberWrapper) {
      const seekFromEvent = (e) => {
        const rect = scrubberWrapper.getBoundingClientRect();
        const clientX = e.clientX || (e.touches && e.touches[0] ? e.touches[0].clientX : 0);
        const pos = Math.min(1, Math.max(0, (clientX - rect.left) / rect.width));
        const dur = getDuration();
        video.currentTime = pos * dur;
        if (scrubberProgress) scrubberProgress.style.width = `${pos * 100}%`;
      };

      scrubberWrapper.addEventListener('click', (e) => {
        e.stopPropagation();
        seekFromEvent(e);
      });

      scrubberWrapper.addEventListener('mousedown', (e) => {
        isScrubbing = true;
        scrubberWrapper.classList.add('scrubbing');
        seekFromEvent(e);

        const onMouseMove = (ev) => {
          if (isScrubbing) seekFromEvent(ev);
        };
        const onMouseUp = () => {
          isScrubbing = false;
          scrubberWrapper.classList.remove('scrubbing');
          window.removeEventListener('mousemove', onMouseMove);
          window.removeEventListener('mouseup', onMouseUp);
        };
        window.addEventListener('mousemove', onMouseMove);
        window.addEventListener('mouseup', onMouseUp);
      });

      // Hover Tooltip on Scrubber
      scrubberWrapper.addEventListener('mousemove', (e) => {
        if (!scrubberTooltip) return;
        const rect = scrubberWrapper.getBoundingClientRect();
        const pos = Math.min(1, Math.max(0, (e.clientX - rect.left) / rect.width));
        const hoverTime = pos * getDuration();

        let chapterLabel = "Baseline";
        for (let i = 0; i < CHAPTERS.length; i++) {
          if (hoverTime >= CHAPTERS[i].time - 0.5) {
            chapterLabel = CHAPTERS[i].title;
          }
        }

        scrubberTooltip.textContent = `${formatTime(hoverTime)} • ${chapterLabel}`;
        scrubberTooltip.style.left = `${pos * 100}%`;
      });
    }

    // Autohide Controls on Inactivity during Playback
    function showControls() {
      if (controlsContainer) controlsContainer.classList.remove('autohide');
      if (stage) stage.classList.remove('cursor-hidden');
    }

    function resetAutohideTimer() {
      showControls();
      clearTimeout(autohideTimer);
      if (!video.paused && !video.ended) {
        autohideTimer = setTimeout(() => {
          if (!video.paused && !video.ended) {
            if (controlsContainer) controlsContainer.classList.add('autohide');
            if (stage) stage.classList.add('cursor-hidden');
          }
        }, 2500);
      }
    }

    player.addEventListener('mousemove', resetAutohideTimer);
    player.addEventListener('mouseenter', showControls);
    player.addEventListener('mouseleave', () => {
      if (!video.paused) {
        if (controlsContainer) controlsContainer.classList.add('autohide');
        if (stage) stage.classList.add('cursor-hidden');
      }
    });

    // Keyboard Shortcuts
    window.addEventListener('keydown', (e) => {
      // Do not capture if user is typing in form field
      const tag = document.activeElement ? document.activeElement.tagName.toLowerCase() : '';
      if (tag === 'input' || tag === 'textarea' || tag === 'select') return;

      const key = e.key;
      if (key === ' ' || key === 'k' || key === 'K') {
        e.preventDefault();
        togglePlay();
      } else if (key === 'ArrowLeft' || key === 'j' || key === 'J') {
        e.preventDefault();
        video.currentTime = Math.max(0, video.currentTime - 10);
        flashActionSplash('rewind');
      } else if (key === 'ArrowRight' || key === 'l' || key === 'L') {
        e.preventDefault();
        video.currentTime = Math.min(getDuration(), video.currentTime + 10);
        flashActionSplash('forward');
      } else if (key === 'ArrowUp') {
        e.preventDefault();
        video.volume = Math.min(1, video.volume + 0.1);
        video.muted = false;
      } else if (key === 'ArrowDown') {
        e.preventDefault();
        video.volume = Math.max(0, video.volume - 0.1);
      } else if (key === 'm' || key === 'M') {
        e.preventDefault();
        video.muted = !video.muted;
      } else if (key === 't' || key === 'T') {
        e.preventDefault();
        toggleTheatre();
      } else if (key === 'f' || key === 'F') {
        e.preventDefault();
        toggleFullscreen();
      }
    });

    // Wire Interactive Chapter Badges below video
    const jumpButtons = document.querySelectorAll('[data-jump-time]');
    jumpButtons.forEach(btn => {
      btn.addEventListener('click', () => {
        const time = parseFloat(btn.getAttribute('data-jump-time'));
        const chapterLabel = btn.innerText.replace(/^▶\s*/, '').trim();
        if (!isNaN(time)) {
          video.currentTime = time;
          video.play().catch(() => {});
          showChapterOsd(chapterLabel);
          flashActionSplash('forward');

          if (typeof gtag === 'function') {
            gtag('event', 'video_chapter_jump', {
              chapter_name: chapterLabel,
              jump_time_sec: time
            });
          }
        }
      });
    });
  } else {
    // Fallback for simple video players on other pages
    const jumpButtons = document.querySelectorAll('[data-jump-time]');
    jumpButtons.forEach(btn => {
      btn.addEventListener('click', () => {
        const time = parseFloat(btn.getAttribute('data-jump-time'));
        const chapterLabel = btn.innerText.trim();
        if (!isNaN(time)) {
          video.currentTime = time;
          video.play().catch(() => {});
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
}
