# IDR-Navigator Presentation & Showcase Website
**Smart India Hackathon (SIH 2026) Submission Hub**

This directory contains the self-contained presentation website for **IDR-Navigator (Intelligent Dead Reckoning System with GNSS Fusion)**.

---

## 🚀 Quick Launch

### Option 1: Double-Click Local Server (Windows)
Double-click [`start_presentation.bat`](file:///e:/inventor/presentation_website/start_presentation.bat). It will automatically start a local Python HTTP server on port 8088 and open the website in your default browser at `http://localhost:8088/`.

### Option 2: Deploy to Google Cloud (Firebase Hosting)
Double-click [`deploy_to_google_cloud.bat`](file:///e:/inventor/presentation_website/deploy_to_google_cloud.bat) to deploy the website to Google Cloud CDN under `tempersoft2018@gmail.com`.
- **Live Google URL**: `https://<your-project-id>.web.app/`
- Includes automatic global SSL, zero server maintenance, and fast edge delivery.

### Option 3: Command Line
```bash
cd presentation_website
python -m http.server 8088
# Then open http://localhost:8088/ in your browser
```

---

## 🌟 Key Sections & Features

1. **Telemetry Hero Section**:
   - High-tech aerospace dark HUD theme with glassmorphism and electric cyan / emerald glowing accents.
   - Live metrics ticker (93.8% IO-VNBD pass rate, 0.02% best drift, 11.2ms inference latency, ₹0 retrofit hardware cost).
   - In-cabin cockpit HUD visual preview.

2. **Demo Video Theater & Video Uploader (`#video-demo`)**:
   - Integrated HTML5 video player hosting the real field test recording (`assets/videos/demo_recording.mp4`, 79.4 MB).
   - 5 interactive milestone chapter buttons to jump directly to key test phases (Open-Sky calibration, Outage entry, Divergence vs IDR, Pothole jerk gating, Standstill ZUPT).
   - Playback speed switcher (0.5x, 1.0x, 1.5x, 2.0x).
   - **Interactive Custom Video Drop Zone**: Drag and drop any custom `.mp4` / `.webm` test recording to immediately preview it in the player using client-side object URLs! Includes a one-click button to reset back to the official SIH recording.

3. **APK Download & Uploader Hub (`#apk-downloads`)**:
   - **IDR Navigator Production Release APK** (`downloads/idr_navigator_v1.0.apk`, 111.6 MB) with instant download button, SHA-256 checksum copy button, and compatibility badges.
   - **Pure C++20 SIMD Edge Engine APK** (`downloads/idr_pure_cpp_engine.apk`, 933 KB) for high-rate tactical IMUs.
   - **Dynamic QR Code Scanner**: Judges and testers can scan the on-screen QR code with their smartphone camera to download the APK directly.
   - **Interactive Custom APK Uploader**: Drag and drop any newly built `.apk` file to inspect package metadata (file size, timestamp) and generate an instant local download link.
   - 3-step 30-second Android installation guide.

4. **Official 6-Slide Master Pitch Deck (`#pitch-deck`)**:
   - Faithful reproduction of the SIH 2026 presentation structure from `SIH_2026_PRESENTATION_MASTER_GUIDE.md`:
     - Slide 1: Title Page & Executive Overview
     - Slide 2: Proposed Solution & 3-Pillar Architecture (with Comparison Matrix)
     - Slide 3: Technical Approach & System Pipeline (with formulas and dual-tier stack)
     - Slide 4: Feasibility, Viability & Indian Road Risk Mitigation (Potholes, ZUPT)
     - Slide 5: Social, Economic & Strategic National Impact
     - Slide 6: Research Benchmarks & Official IO-VNBD Empirical Scorecard
   - Interactive slide controls (Next/Prev, slide indicator dots, left/right keyboard arrow navigation, fullscreen presentation toggle).
   - Collapsible **"Judge Script"** drawer displaying verbatim talking points and defense scripts for each slide.

5. **Live In-Browser Drift & Outage Simulator (`#live-simulator`)**:
   - Real-time HTML5 Canvas physics simulation comparing Green (IDR Neuro-Kalman) vs Red (Classical INS Double Integration).
   - Interactive triggers:
     - **CUT GNSS (TUNNEL OUTAGE)**: Red vehicle veers off track with quadratic drift while IDR holds the lane.
     - **INJECT POTHOLE SHOCK**: Simulates Indian road potholes; IDR's Jerk Variance Gate freezes acceleration integration while Classical DR kicks off-course.
     - **TOGGLE RED LIGHT (ZUPT)**: Standstill detector locks velocity to 0.00 km/h, preventing sensor creep.
     - **RESET SIMULATION**: Restores nominal track state.

6. **Algorithmic Deep Dive & Benchmark Plot (`#benchmarks`)**:
   - Breakdown of the 5 foundational engineering modules with exact mathematical formulas.
   - Empirical trajectory error reduction plot (`assets/images/dead_reckoning_benchmark.png`).

7. **Dedicated Field Video Demo & Video Upload Lab (`video.html`)**:
   - Full-page video demonstration theater featuring the official SIH tunnel test video (`assets/videos/demo_recording.mp4`).
   - Dynamic telemetry HUD panel synchronizing velocity, satellite loss, and filter state with video playback.
   - Interactive drop zone for **videos to be uploaded later** (or uploaded live) with client-side hardware decoding and metadata extraction.
   - Scenario annotator form and test video roster.

8. **Dedicated AI Model & Weights Hub (`model.html`)**:
   - Direct downloads for production `vehicle_speed_tcn.onnx` (8.43 MB), `stage2_model.onnx` (8.43 MB), `best_speed_tcn.pth` (8.44 MB), and `normalize_stats.json`.
   - External links to GitHub repository, Hugging Face Model Hub, Zenodo dataset, and Google Colab.
   - Interactive In-Browser Neural Speed Inference Playground with live sensor sliders and predictive uncertainty gauge.
   - Complete Causal SE-TCN architecture specifications, formulas, and Python/C++20 edge deployment code.

---

## 📁 Directory Structure

```
presentation_website/
├── index.html                   # High-converting idea marketing front page
├── video.html                   # Dedicated field video demo & video upload lab
├── model.html                   # Dedicated AI model, weights & inference hub
├── style.css                    # Aerospace & telemetry HUD dark design system
├── app.js                       # Video controls, APK hub, QR code, and slide deck logic
├── simulator.js                 # Side-by-side vehicle physics & outage simulator
├── start_presentation.bat       # Windows one-click local server launcher
├── README.md                    # Documentation & guide
├── assets/
│   ├── images/
│   │   ├── hero_hud_showcase.jpg
│   │   ├── idr_app_logo.jpg
│   │   ├── favicon.jpg
│   │   ├── dead_reckoning_benchmark.png
│   │   ├── 3d_car.png
│   │   └── nav_car_3d.png
│   └── videos/
│       └── demo_recording.mp4   # 79.4 MB recorded field test video with dual-view telemetry
└── downloads/
    ├── idr_navigator_v1.0.apk   # 111.6 MB Production Flutter Release APK
    ├── idr_pure_cpp_engine.apk  # 933 KB Pure C++20 SIMD NativeActivity APK
    └── models/
        ├── vehicle_speed_tcn.onnx  # 8.43 MB Production ONNX Mobile Edge Model
        ├── stage2_model.onnx       # 8.43 MB Highway & Urban Fine-Tuned ONNX Model
        ├── best_speed_tcn.pth      # 8.44 MB PyTorch Checkpoint State Dict
        └── normalize_stats.json    # 481 B IMU 8-Channel Normalization Scalers
```

