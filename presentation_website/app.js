/**
 * IDR-NAVIGATOR PRESENTATION WEBSITE INTERACTIVE APPLICATION ENGINE
 * Handles: Video Player, Custom Video Uploader, APK Uploader, Dynamic QR Generator, 6-Slide Deck
 */

document.addEventListener('DOMContentLoaded', () => {
  initNavigation();
  initVideoPlayer();
  initCustomVideoUploader();
  initApkHub();
  initPitchDeck();
  renderDynamicQrCode();
});

/* ==========================================================================
   1. Navigation & Active Scroll Tracking
   ========================================================================== */
function initNavigation() {
  const navLinks = document.querySelectorAll('.nav-item-link');
  const sections = document.querySelectorAll('section[id]');
  const isSubpage = window.location.pathname.includes('video.html') || window.location.pathname.includes('model.html');

  if (isSubpage || sections.length === 0) {
    return;
  }

  window.addEventListener('scroll', () => {
    let current = '';
    const scrollPos = window.scrollY + 140;

    sections.forEach(section => {
      const top = section.offsetTop;
      const height = section.offsetHeight;
      if (scrollPos >= top && scrollPos < top + height) {
        current = section.getAttribute('id');
      }
    });

    if (current) {
      navLinks.forEach(link => {
        const href = link.getAttribute('href');
        if (href && href.startsWith('#')) {
          if (href === `#${current}`) {
            link.classList.add('active');
          } else {
            link.classList.remove('active');
          }
        }
      });
    }
  });
}

/* ==========================================================================
   2. Video Player & Chapter Controller
   ========================================================================== */
const videoPlayer = document.getElementById('demoVideoPlayer');
const durationChip = document.getElementById('videoDurationChip');
const timeDisplay = document.getElementById('videoCurrentTimeDisplay');
const chapterBtns = document.querySelectorAll('.chapter-btn');
const defaultVideoSrc = 'assets/videos/demo_recording.mp4';

function initVideoPlayer() {
  if (!videoPlayer) return;

  videoPlayer.addEventListener('loadedmetadata', () => {
    if (durationChip) {
      durationChip.textContent = formatTime(videoPlayer.duration);
    }
  });

  videoPlayer.addEventListener('timeupdate', () => {
    if (timeDisplay) {
      timeDisplay.textContent = `${formatTime(videoPlayer.currentTime)} / ${formatTime(videoPlayer.duration || 0)}`;
    }
    updateActiveChapterHighlight(videoPlayer.currentTime);
  });
}

function formatTime(seconds) {
  if (isNaN(seconds)) return '00:00';
  const m = Math.floor(seconds / 60).toString().padStart(2, '0');
  const s = Math.floor(seconds % 60).toString().padStart(2, '0');
  return `${m}:${s}`;
}

window.seekVideo = function (seconds) {
  if (!videoPlayer) return;
  videoPlayer.currentTime = seconds;
  videoPlayer.play();
};

window.setVideoSpeed = function (speed) {
  if (!videoPlayer) return;
  videoPlayer.playbackRate = speed;
  const speedChips = document.querySelectorAll('.video-controls-bar .meta-chip');
  speedChips.forEach(chip => {
    if (chip.textContent.includes(`${speed}x`)) {
      chip.classList.add('active-chip');
    } else if (chip.textContent.includes('x')) {
      chip.classList.remove('active-chip');
    }
  });
};

function updateActiveChapterHighlight(time) {
  const markers = [
    { start: 0, end: 15 },
    { start: 15, end: 35 },
    { start: 35, end: 50 },
    { start: 50, end: 65 },
    { start: 65, end: 999 }
  ];

  chapterBtns.forEach((btn, idx) => {
    const m = markers[idx];
    if (m && time >= m.start && time < m.end) {
      btn.classList.add('active-chapter');
    } else {
      btn.classList.remove('active-chapter');
    }
  });
}

/* ==========================================================================
   3. Custom Demo Video Drag & Drop Uploader
   ========================================================================== */
function initCustomVideoUploader() {
  const dropZone = document.getElementById('videoDropZone');
  const fileInput = document.getElementById('customVideoInput');
  const resetBtn = document.getElementById('resetVideoBtn');
  const notify = document.getElementById('videoUploadNotification');
  const sourceLabel = document.getElementById('videoSourceLabel');

  if (!dropZone || !fileInput) return;

  ['dragenter', 'dragover'].forEach(eventName => {
    dropZone.addEventListener(eventName, (e) => {
      e.preventDefault();
      dropZone.classList.add('drag-over');
    });
  });

  ['dragleave', 'drop'].forEach(eventName => {
    dropZone.addEventListener(eventName, (e) => {
      e.preventDefault();
      dropZone.classList.remove('drag-over');
    });
  });

  dropZone.addEventListener('drop', (e) => {
    const files = e.dataTransfer.files;
    if (files.length > 0) {
      handleCustomVideoFile(files[0]);
    }
  });

  fileInput.addEventListener('change', () => {
    if (fileInput.files.length > 0) {
      handleCustomVideoFile(fileInput.files[0]);
    }
  });

  function handleCustomVideoFile(file) {
    if (!file.type.startsWith('video/') && !file.name.endsWith('.mkv')) {
      alert('Please upload a valid video file (.mp4, .webm, .mov, .mkv)');
      return;
    }

    const player = document.getElementById('demoVideoPlayer');
    if (!player) return;

    const objectUrl = URL.createObjectURL(file);
    player.src = objectUrl;
    player.play();

    const sizeMb = (file.size / (1024 * 1024)).toFixed(2);
    if (sourceLabel) {
      sourceLabel.textContent = `Custom: ${file.name} (${sizeMb} MB)`;
    }
    if (notify) {
      notify.textContent = `✔ Custom video loaded successfully: ${file.name} (${sizeMb} MB). Playing in video player above!`;
    }
    if (resetBtn) resetBtn.style.display = 'inline-flex';

    // Update Subpage Metadata elements if present
    const metaName = document.getElementById('metaFileName');
    const metaSize = document.getElementById('metaFileSize');
    const metaType = document.getElementById('metaFileType');
    const specsBox = document.getElementById('uploadedVideoSpecsBox');
    const statusBadge = document.getElementById('statusSourceBadge');
    const activeLabel = document.getElementById('activeRecordingLabel');

    if (metaName) metaName.textContent = file.name;
    if (metaSize) metaSize.textContent = `${sizeMb} MB`;
    if (metaType) metaType.textContent = file.type || 'video/mp4';
    if (specsBox) specsBox.style.display = 'block';
    if (statusBadge) statusBadge.textContent = file.name;
    if (activeLabel) activeLabel.textContent = `CUSTOM USER TEST: ${file.name.toUpperCase()} (${sizeMb} MB)`;
  }

  window.resetToDefaultVideo = function () {
    const player = document.getElementById('demoVideoPlayer');
    if (!player) return;
    player.src = defaultVideoSrc;
    player.play();
    if (sourceLabel) {
      sourceLabel.textContent = 'assets/videos/demo_recording.mp4 (6.87 MB)';
    }
    if (notify) {
      notify.textContent = 'Restored official SIH recorded field test video.';
    }
    if (resetBtn) resetBtn.style.display = 'none';

    const specsBox = document.getElementById('uploadedVideoSpecsBox');
    const statusBadge = document.getElementById('statusSourceBadge');
    const activeLabel = document.getElementById('activeRecordingLabel');
    if (specsBox) specsBox.style.display = 'none';
    if (statusBadge) statusBadge.textContent = 'demo_recording.mp4';
    if (activeLabel) activeLabel.textContent = 'OFFICIAL TEST: MUMBAI-PUNE TUNNEL SIMULATED OUTAGE';
  };
}

/* ==========================================================================
   4. APK Hub & Custom APK Uploader
   ========================================================================== */
function initApkHub() {
  const apkDropZone = document.getElementById('apkDropZone');
  const apkInput = document.getElementById('customApkInput');
  const newApkContainer = document.getElementById('newApkContainer');

  if (!apkDropZone || !apkInput) return;

  ['dragenter', 'dragover'].forEach(eventName => {
    apkDropZone.addEventListener(eventName, (e) => {
      e.preventDefault();
      apkDropZone.classList.add('drag-over');
    });
  });

  ['dragleave', 'drop'].forEach(eventName => {
    apkDropZone.addEventListener(eventName, (e) => {
      e.preventDefault();
      apkDropZone.classList.remove('drag-over');
    });
  });

  apkDropZone.addEventListener('drop', (e) => {
    const files = e.dataTransfer.files;
    if (files.length > 0) {
      handleNewApkFile(files[0]);
    }
  });

  apkInput.addEventListener('change', () => {
    if (apkInput.files.length > 0) {
      handleNewApkFile(apkInput.files[0]);
    }
  });

  function handleNewApkFile(file) {
    if (!file.name.endsWith('.apk')) {
      alert('Please upload a file with an .apk extension');
      return;
    }

    const sizeMb = (file.size / (1024 * 1024)).toFixed(2);
    const objectUrl = URL.createObjectURL(file);
    const dateStr = new Date().toLocaleTimeString();

    const badge = document.createElement('div');
    badge.className = 'uploaded-apk-badge';
    badge.innerHTML = `
      <div>
        <div style="font-weight: 700; color: var(--green-accent);">${file.name}</div>
        <div style="font-size: 0.72rem; color: var(--text-muted); font-family: var(--font-mono);">
          Size: ${sizeMb} MB • Added: ${dateStr} • Ready to test
        </div>
      </div>
      <a href="${objectUrl}" download="${file.name}" class="btn-hud btn-hud-primary" style="padding: 0.35rem 0.75rem; font-size: 0.75rem;">
        Download
      </a>
    `;

    newApkContainer.prepend(badge);
  }
}

/* ==========================================================================
   5. Dynamic SVG QR Code Generator
   ========================================================================== */
function renderDynamicQrCode() {
  const qrContainer = document.getElementById('qrContainer');
  if (!qrContainer) return;

  // Render high-tech vector QR code pattern with IDR compass arrow center
  const svgQr = `
    <svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
      <!-- Background -->
      <rect width="100" height="100" fill="#ffffff" rx="4"/>
      
      <!-- Finder Pattern Top-Left -->
      <rect x="8" y="8" width="24" height="24" stroke="#0f172a" stroke-width="3" fill="none"/>
      <rect x="14" y="14" width="12" height="12" fill="#0f172a"/>

      <!-- Finder Pattern Top-Right -->
      <rect x="68" y="8" width="24" height="24" stroke="#0f172a" stroke-width="3" fill="none"/>
      <rect x="74" y="14" width="12" height="12" fill="#0f172a"/>

      <!-- Finder Pattern Bottom-Left -->
      <rect x="8" y="68" width="24" height="24" stroke="#0f172a" stroke-width="3" fill="none"/>
      <rect x="14" y="74" width="12" height="12" fill="#0f172a"/>

      <!-- Timing Patterns -->
      <path d="M36 12h4v4h-4zm8 0h4v4h-4zm8 0h4v4h-4zm-16 8h4v4h-4zm8 0h4v4h-4zm-8 8h4v4h-4zm8 0h4v4h-4zm8 0h4v4h-4zm-24 8h4v4h-4zm8 0h4v4h-4zm16 0h4v4h-4zm8 0h4v4h-4zm16 0h4v4h-4zm-48 8h4v4h-4zm16 0h4v4h-4zm8 0h4v4h-4zm16 0h4v4h-4zm-40 8h4v4h-4zm8 0h4v4h-4zm16 0h4v4h-4zm8 0h4v4h-4zm8 0h4v4h-4zm-40 8h4v4h-4zm16 0h4v4h-4zm8 0h4v4h-4zm-32 8h4v4h-4zm8 0h4v4h-4zm16 0h4v4h-4zm16 0h4v4h-4zm-40 8h4v4h-4zm8 0h4v4h-4zm8 0h4v4h-4zm16 0h4v4h-4zm8 0h4v4h-4z" fill="#1e293b"/>

      <!-- Center IDR Badge -->
      <circle cx="50" cy="50" r="13" fill="#07090e" stroke="#00f0ff" stroke-width="2"/>
      <polygon points="50,42 56,54 50,51 44,54" fill="#00f0ff"/>
    </svg>
  `;

  qrContainer.innerHTML = svgQr;
}

/* ==========================================================================
   6. SIH 2026 6-Slide Pitch Deck Controller
   ========================================================================== */
let currentSlide = 1;
const totalSlides = 6;

function initPitchDeck() {
  document.addEventListener('keydown', (e) => {
    // Only capture if not typing inside an input
    if (['INPUT', 'TEXTAREA'].includes(document.activeElement.tagName)) return;
    if (e.key === 'ArrowRight' || e.key === 'PageDown') {
      nextSlide();
    } else if (e.key === 'ArrowLeft' || e.key === 'PageUp') {
      prevSlide();
    }
  });
}

window.goToSlide = function (n) {
  if (n < 1 || n > totalSlides) return;
  currentSlide = n;
  updateDeckDisplay();
};

window.nextSlide = function () {
  if (currentSlide < totalSlides) {
    currentSlide++;
  } else {
    currentSlide = 1; // loop
  }
  updateDeckDisplay();
};

window.prevSlide = function () {
  if (currentSlide > 1) {
    currentSlide--;
  } else {
    currentSlide = totalSlides;
  }
  updateDeckDisplay();
};

function updateDeckDisplay() {
  const slides = document.querySelectorAll('.deck-slide');
  const dots = document.querySelectorAll('.slide-dot');
  const titleEl = document.getElementById('deckHeaderTitle');
  const badgeEl = document.getElementById('slideIndexBadge');

  slides.forEach(slide => {
    const slideNum = parseInt(slide.getAttribute('data-slide'), 10);
    if (slideNum === currentSlide) {
      slide.classList.add('active-slide');
      if (titleEl) {
        titleEl.textContent = `SLIDE ${currentSlide} OF 6 : ${slide.getAttribute('data-title') || ''}`;
      }
    } else {
      slide.classList.remove('active-slide');
    }
  });

  dots.forEach((dot, idx) => {
    if (idx + 1 === currentSlide) {
      dot.classList.add('active-dot');
    } else {
      dot.classList.remove('active-dot');
    }
  });

  if (badgeEl) {
    badgeEl.textContent = `${currentSlide} / ${totalSlides}`;
  }
}

window.toggleSpeakerNotes = function () {
  const activeSlide = document.querySelector('.deck-slide.active-slide');
  if (!activeSlide) return;
  const notesBox = activeSlide.querySelector('.speaker-notes-box');
  if (notesBox) {
    notesBox.style.display = notesBox.style.display === 'none' ? 'block' : 'none';
  }
};

window.toggleDeckFullscreen = function () {
  const deck = document.querySelector('.deck-container');
  if (!deck) return;

  if (!document.fullscreenElement) {
    deck.requestFullscreen().catch(err => {
      console.warn(`Fullscreen error: ${err.message}`);
    });
  } else {
    document.exitFullscreen();
  }
};

/* ==========================================================================
   7. Copy Text Utility
   ========================================================================== */
window.copyText = function (text, btn) {
  navigator.clipboard.writeText(text).then(() => {
    const originalText = btn.textContent;
    btn.textContent = 'Copied!';
    btn.style.color = 'var(--green-accent)';
    setTimeout(() => {
      btn.textContent = originalText;
      btn.style.color = '';
    }, 2000);
  });
};
