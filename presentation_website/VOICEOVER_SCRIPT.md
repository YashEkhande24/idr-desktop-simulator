# IDR-NAVIGATOR: FIELD DEMONSTRATION
## Voiceover Narration Script for Video Recording
**Target Video:** `IDR_Navigator_Field_Demo_Combined.mp4` / `demo_recording.mp4`  
**Total Video Runtime:** 05:59  
**Tone:** Confident, professional, clear, articulate, authoritative engineering pitch.

---

### VOICE ACTOR INSTRUCTIONS:
- **Speech Rate:** Normal, steady conversational pace (~130 words per minute).
- **Pauses:** `[...]` indicates a natural breath/pause to allow the viewer to look at the screen.
- **Emphasis:** Bolded words in quotes should receive natural vocal emphasis.
- **Pronunciation Guide:**
  - **GNSS:** *"G-N-S-S"* (or *Global Navigation Satellite System*)
  - **IMU:** *"I-M-U"* (Inertial Measurement Unit)
  - **SE-TCN:** *"S-E-T-C-N"* (Squeeze-and-Excitation Temporal Convolutional Network)
  - **EKF:** *"E-K-F"* (Extended Kalman Filter)
  - **ZUPT:** *"ZUPT"* (rhymes with *erupt*)
  - **HDOP:** *"H-DOP"* (Horizontal Dilution of Precision)
  - **SO(3):** *"S-O-three"*
  - **Savitzky-Golay:** *"Suh-VIT-skee GO-lay"*
  - **Mahony:** *"MAY-huh-nee"*

---

## PART 1: TRIAL 01 — HIGHWAY UNDERPASS TUNNEL OUTAGE
**Location:** Pune–Nashik Highway (NH60)  
**Segment Duration:** 00:00 – 03:31

---

### [00:00 - 00:07] • Phase 1: Open-Sky Baseline Calibration
> **Visual Cue:** The video opens on a roadside in broad daylight. Both screens display the green **`GNSS ACTIVE`** badge with **`±0.7m`** accuracy.

**VOICEOVER:**  
"Respected evaluators, [...] before entering the blackout zone, observe the opening baseline on both feeds. On the left is our synchronized road ground truth, and on the right is our real-time cockpit HUD. 

Notice the green indicator: **GNSS is active**, satellite health is optimal, and positional accuracy is calibrated to **zero point seven meters** under clear open sky."

---

### [00:07 - 00:14] • Phase 2: Intentional GNSS Severing
> **Visual Cue:** At 00:07, the rider’s hand reaches up and pulls down the Android quick settings shade, toggling Location OFF to simulate entering a tunnel.

**VOICEOVER:**  
"Right here at the seven-second mark, [...] we pull down the notification shade to deliberately sever location services. 

This replicates a sudden, zero-satellite signal blackout as encountered inside highway underpasses and deep transit tunnels."

---

### [00:14 - 00:35] • Phase 3: Outage Banner & Neural Takeover
> **Visual Cue:** The red **`OUTAGE`** telemetry banner slides in. The vehicle moves forward along the highway underpass.

**VOICEOVER:**  
"Immediately, the cockpit shifts into emergency dead reckoning mode. 

Notice that despite zero satellite availability, the vehicle marker does **not** freeze, disappear, or jump into surrounding terrain. Our on-device eight-channel Dilated **SE-TCN** neural network is now estimating instantaneous speed directly from raw inertial vibrations."

---

### [00:35 - 01:15] • Phase 4: Highway Traversal & Lane Clamping
> **Visual Cue:** The vehicle navigates smoothly through the underpass. The red car icon tracks the exact highway curve.

**VOICEOVER:**  
"Under classical double-integration, accelerometer sensor bias compounds quadratically—causing positional error to exceed **one hundred and forty meters** within just thirty seconds. 

In contrast, IDR-Navigator fuses our neural speed estimates with a **9D Extended Kalman Filter** and vector road clamping, keeping the vehicle strictly confined within its actual driving lane."

---

### [01:15 - 02:00] • Phase 5: Road Bumps & Vibration Rejection
> **Visual Cue:** The road surface shows bumps, uneven asphalt, and highway patches.

**VOICEOVER:**  
"A major failure mode in inertial navigation is road roughness—speed breakers and potholes typically inject false acceleration spikes. 

Our **Savitzky-Golay jerk gating filter** actively isolates genuine vehicle forward propulsion from chassis vibration, preventing artificial speed surges."

---

### [02:00 - 02:45] • Phase 6: Standstill & Traffic Deceleration
> **Visual Cue:** The vehicle decelerates and halts momentarily in traffic.

**VOICEOVER:**  
"Watch closely as the vehicle slows down. [...] Standard inertial systems suffer from coordinate drift when stationary. 

Here, our physics-coupled Zero-Velocity Update—or **ZUPT**—detects complete stops instantly, freezing coordinate drift without relying on GPS Doppler velocity."

---

### [02:45 - 03:31] • Phase 7: Tunnel Exit & Sigmoidal Re-Convergence
> **Visual Cue:** The vehicle clears the underpass and pulls to the side safely.

**VOICEOVER:**  
"As the vehicle clears the underpass, IDR-Navigator executes seamless satellite handoff via our sigmoidal **HDOP gate**—eliminating the erratic UI teleportation typical of conventional consumer maps. 

This concludes Trial One with continuous, unbroken lane-level tracking throughout the entire blackout."

---

## PART 2: TRIAL 02 — SANGAMNER BYPASS EXTENDED BLACKOUT
**Location:** Sangamner Bypass Highway  
**Segment Duration:** 03:31 – 05:59

---

### [03:31 - 03:50] • Phase 8: Transition to Extended Blackout Trial
> **Visual Cue:** The dashboard switches to **`TRIAL 02: SANGAMNER BYPASS`**. High-speed motorcycle footage begins.

**VOICEOVER:**  
"Now transitioning to **Trial Two** on the Sangamner Bypass. 

In this second run, we subject the system to an extended multi-minute blackout over high-speed bypass curves, testing long-duration drift tolerance and edge thermal stability."

---

### [03:50 - 04:35] • Phase 9: High-Speed Curvature & Mahony Attitude Filter
> **Visual Cue:** The motorcycle leans and corners along sweeping highway curves.

**VOICEOVER:**  
"Observe how the vehicle negotiates banking and curve maneuvers. 

Our dynamic **Mahony SO(3) attitude observer** continuously separates centrifugal lateral acceleration from gravity, ensuring heading angle drift remains clamped even during sustained highway sweeps."

---

### [04:35 - 05:15] • Phase 10: Zero External Hardware & Edge Efficiency
> **Visual Cue:** The camera feed clearly displays the motorcycle cockpit—just a standard phone mounted with zero cables.

**VOICEOVER:**  
"Crucially, this entire pipeline runs **one hundred percent locally** on the smartphone's edge NPU. 

Notice there are **zero external wires**, zero OBD-two telematics boxes, and zero wheel speed encoders. It delivers an inference latency of just **eleven point two milliseconds** while consuming less than eight percent CPU overhead."

---

### [05:15 - 05:45] • Phase 11: Long-Distance Blackout Stability
> **Visual Cue:** Over 8,000 meters logged on the red outage banner (`DIST: 8590m`). The car icon remains pinned to the road.

**VOICEOVER:**  
"Even after thousands of meters traversed through complete satellite denial, our vehicle remains locked to vector road geometry. 

The solution represents a robust, production-ready architecture suitable for mass automotive, logistics, and emergency fleet deployment."

---

### [05:45 - 05:59] • Phase 12: Closing Summary
> **Visual Cue:** Vehicle comes to a safe stop at the trial terminus.

**VOICEOVER:**  
"IDR-Navigator proves that high-precision vehicular dead reckoning is completely achievable using nothing more than commodity smartphone sensors and intelligent deep learning fusion. [...] 

Thank you."
