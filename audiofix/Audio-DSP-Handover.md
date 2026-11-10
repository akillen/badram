# Apple T2 MacBook Pro 16,1 Audio DSP Handover & Verification Runbook

## Executive Summary

On the 16" MacBook Pro (`MacBookPro16,1`), Apple employs a custom **six-transducer acoustic system** (two high-frequency tweeters and four force-cancelling woofers) paired with a **three-microphone beamforming array**. In macOS, sound reproduction relies fundamentally on software-based Digital Signal Processing (DSP) inside CoreAudio.

Under standard Linux installations, the hardware exposes a raw 6-channel PCM (`FL, SL, RL, FR, SR, RR`). Without DSP, Linux sends raw full-range audio directly to individual transducers with no crossover filtering, no acoustic chassis equalization, and no excursion limiting, resulting in weak, tinny sound, virtually zero bass, and risked physical damage at high volumes.

We deployed the modern **`t2-apple-audio-dsp`** PipeWire/WirePlumber filter chain configured specifically for the `MacBookPro16,1`. It restores deep bass, acoustic balance, and microphone beamforming while presenting a standard 2-channel stereo sink to applications.

---

## Why Previous Attempts Failed

### 1. Why `t2-better-audio` Had No Effect
* [`t2-better-audio`](https://github.com/kekrby/t2-better-audio) is a legacy script from older Linux/PulseAudio iterations.
* It only copies PulseAudio / ALSA Card Profile (`ACP`) configuration files (`apple-t2x6.conf`).
* Modern Ubuntu T2 Linux relies on **ALSA UCM2** (`/usr/share/alsa/ucm2/AppleT2/HiFi-x6.conf`), which automatically supercedes ACP mixer profiles.
* Furthermore, `t2-better-audio` contained no DSP algorithms, crossovers, or equalizers.

### 2. Why EasyEffects Caused a Left Bias and Degraded Sound
* EasyEffects is designed to intercept and process standard 2-channel stereo (`FL, FR`) or standard 5.1/7.1 surround layouts.
* The T2 ALSA sink presents 6 discrete channels where `SL/RL` and `SR/RR` represent physical woofer drivers rather than side/rear surround channels.
* EasyEffects matrixed and downmixed these non-standard channels unpredictably, applying stereo processing unevenly across the tweeters and woofers, which caused severe phase cancellation and a sharp bias toward the left channel.

---

## Technical Architecture of the Solution

```
Application Stereo Stream (Firefox, Spotify, etc.)
                   │
                   ▼
  [Audio/Sink] "MacBook Pro T2 DSP Speakers" (2 Channels: FL, FR)
                   │
                   ├──► bankstown-lv2 (Psychoacoustic sub-bass harmonic synthesis)
                   │
                   ├──► lsp-plugins loudness compensation (ell / elr)
                   │
                   ├──► Split to Crossovers & FIR Convolution
                   │         │
                   │         ├─► High Frequencies: PipeWire Convolver (tweeters-48k.wav)
                   │         │         │
                   │         │         ├──► Physical Channel 2: Left Tweeter (FL)
                   │         │         └──► Physical Channel 5: Right Tweeter (FR)
                   │         │
                   │         └─► Low Frequencies: PipeWire Convolver (woofers-48k.wav)
                   │                   │
                   │                   ▼
                   │             lsp-plugins stereo peak limiter (woofer excursion protection)
                   │                   │
                   │                   ├──► Physical Channel 0: Left Woofer 1 (SL)
                   │                   ├──► Physical Channel 1: Left Woofer 2 (RL)
                   │                   ├──► Physical Channel 3: Right Woofer 1 (SR)
                   │                   └──► Physical Channel 4: Right Woofer 2 (RR)
                   │
                   ▼
  Raw Hardware Sink: `alsa_output.platform-sound.RawSpeakers` (Hidden from user)
```

### Microphone Array Architecture
* Uses `triforce-lv2` beamforming filter across all 3 physical microphone capsules (`AUX0, AUX1, AUX2`).
* Applies high-pass filtering (120 Hz) and 80x gain stage.
* Exposes a clean, mono DSP microphone source: `MacBook Pro T2 DSP Mic`.

---

## Installed Files and Components

| Component | Target Location | Purpose |
| :--- | :--- | :--- |
| **Udev Rule** | `/etc/udev/rules.d/99-t2-audio-rename.rules` | Renames ALSA card `1` to `t2-16_1` so WirePlumber rules uniquely match this model |
| **WirePlumber Config** | `/etc/wireplumber/wireplumber.conf.d/50-t2-audio.conf` | Matches `t2-16_1`, hides raw endpoints, and auto-instantiates DSP graphs |
| **DSP Graph & FIR Curves** | `/usr/share/t2linux-audio/16_1/` | Contains `graph.json`, `mic.json`, and `.wav` impulse response convolution files |
| **LV2 Plugins (APT)** | `bankstown-lv2`, `triforce-lv2`, `lsp-plugins-lv2`, `swh-lv2` | DSP audio processing plugins |
| **PipeWire Extras (APT)**| `libpipewire-0.3-modules-extra`, `libspa-0.2-modules-extra` | PipeWire native filter-chain modules |

---

## Verification & Usage Runbook

### 1. Check Installation Health
Run the bundled verification script:
```bash
/home/aaronkillen/Development/badram/audiofix/check-install.sh
```
Expected output:
```
=== t2bce_audio + udev ALSA card rename ===
  OK   /sys/module/t2bce_audio
  OK   /etc/udev/rules.d/99-t2-audio-rename.rules
  OK   ALSA card id=t2-16_1

=== WirePlumber DSP config ===
  OK   /etc/wireplumber/wireplumber.conf.d/50-t2-audio.conf

=== Audio data: /usr/share/t2linux-audio/16_1/ ===
  OK   /usr/share/t2linux-audio/16_1
  OK   /usr/share/t2linux-audio/16_1/graph.json
  OK   /usr/share/t2linux-audio/16_1/mic.json
  OK   /usr/share/t2linux-audio/16_1/*.wav (present)

All checked files present (8 items).
```

### 2. Verify Active PipeWire Sinks
Run:
```bash
wpctl status
```
* **Default Sink:** Should display `* audio_effect.t2-161-speakers [Audio/Sink]`.
* **Default Source:** Should display `* audio_effect.t2-161-mic [Audio/Source]`.
* **Raw Speakers:** The raw card (`RawSpeakers`) will be marked passive/hidden so accidental full-range blasts to physical speakers cannot occur.

### 3. Volume Level & Headroom Configuration
* Under GNOME Settings $\to$ Sound, control the volume using **"MacBook Pro T2 DSP Speakers"**.
* **Stock DSP Configuration Maintained:**
  * Uses the calibrated official `t2-apple-audio-dsp` profile without non-standard internal gain modifications.
  * Preserves the exact ISO 226 equal-loudness Fletcher-Munson contours across the full 0%–100% volume slider.
* **Over-Amplification for Extra Loudness:**
  * GNOME Over-Amplification is enabled via `org.gnome.desktop.sound allow-volume-above-100-percent true`.
  * The standard 0%–100% range gives precise, smooth control for quiet and moderate listening.
  * Whenever maximum macOS-level acoustic power and loudness are desired, the volume bar can be pushed smoothly between 100% and 150%.

---

## Reversibility & Rollback

This fix is 100% reversible and touches no core system binaries, kernels, or base ALSA configuration files.

To completely revert back to the stock, un-processed raw audio setup at any time:
```bash
/home/aaronkillen/Development/badram/audiofix/revert-audio-fix.sh
```

What `revert-audio-fix.sh` does:
1. Deletes `/etc/udev/rules.d/99-t2-audio-rename.rules` and triggers udev to revert card name back to `Audio`.
2. Deletes `/etc/wireplumber/wireplumber.conf.d/50-t2-audio.conf`.
3. Deletes `/usr/share/t2linux-audio`.
4. Restarts `wireplumber`, `pipewire`, and `pipewire-pulse` for the current user.
5. Instantly restores stock raw ALSA/PipeWire routing without requiring a reboot.
