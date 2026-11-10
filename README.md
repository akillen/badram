# Apple T2 Linux Setup, Repair & Tuning Repository

This repository maintains the scripts, documentation, and operational logs for running Linux on a 2019 16-inch MacBook Pro (`MacBookPro16,1`) with hardware memory defects.

---

## Hardware Specifications

* **Machine:** Apple MacBook Pro 16-inch (2019, `MacBookPro16,1`, Board ID `Mac-E1008331FDC96864`)
* **CPU:** Intel Core i9-9880H @ 2.30 GHz (8 cores / 16 threads)
* **Security & Bridge Chip:** Apple T2 (`iBridge: 24.16.6005.0.0,0`, EFI `2103.160.2.0.0`)
* **RAM:** 16 GB DDR4-2666 MT/s (soldered, defective in upper physical addresses)
* **OS / Kernel:** Ubuntu 26.04 LTS, T2 Linux Kernel (`7.3.3-2-t2-resolute`)

---

## Directory & Fix Index

### 1. [`ramfix/`](ramfix/) — Bad RAM Physical Address Quarantine
* **Documentation:** [`ramfix/T2-MacBook-Pro-BadRAM-Handover.md`](ramfix/T2-MacBook-Pro-BadRAM-Handover.md)
* **Setup Script:** [`ramfix/apply-t2-badram.sh`](ramfix/apply-t2-badram.sh)
* **Summary:**
  * Contains the physical memory fault map extracted from 8 full passes (~7 hours) of MemTest86 V11.7.
  * 100% of errors occur across 20 physical 4 KB pages in the upper address space (paired symmetrically across bit 25 / 32 MB bank mirrors). The lower 7.13 GB is 100% clean.
  * Quarantined via GRUB configuration using 5 consolidated 48 MB kernel reservations (`memmap=48M$0x1c8000000`, `memmap=48M$0x31d000000`, `memmap=48M$0x345000000`, `memmap=48M$0x3c4000000`, `memmap=48M$0x408000000`) and `GRUB_BADRAM`.

### 2. [`pmfix/`](pmfix/) — Input Freeze & T2 USB Runtime PM Deadlock Fix
* **Documentation:** [`pmfix/T2-MacBook-Pro-Input-Freezes-USB-PM-Handover.md`](pmfix/T2-MacBook-Pro-Input-Freezes-USB-PM-Handover.md)
* **Setup Script:** [`pmfix/apply-t2-pm-fix.sh`](pmfix/apply-t2-pm-fix.sh)
* **Summary:**
  * Addresses intermittent keyboard, trackpad, and Touch Bar unresponsiveness while system power buttons and OS remain alive.
  * Root cause was aggressive USB autosuspend (`control=auto`, 2000 ms timeout) triggered by TLP and `powertop --auto-tune` against Apple T2 virtual USB devices (`05ac:*` on Bus 007).
  * Suspended devices triggered fatal `BUG: scheduling while atomic` kernel errors in `irq/98-bce_dma` when waking from interrupt spinlock context, as well as `pm_runtime_work` self-deadlocks.
  * Enforces `power/control="on"` and `autosuspend_delay_ms="-1"` via `/etc/tlp.d/01-t2.conf`, `/etc/udev/rules.d/90-apple-t2-usb-pm.rules`, and updates to `pcie-aspm-tune.sh`.

### 3. [`audiofix/`](audiofix/) — 6-Channel Speaker DSP Crossover & Mic Beamforming
* **Documentation:** [`audiofix/Audio-DSP-Handover.md`](audiofix/Audio-DSP-Handover.md)
* **Setup Script:** [`audiofix/apply-audio-fix.sh`](audiofix/apply-audio-fix.sh)
* **Revert Script:** [`audiofix/revert-audio-fix.sh`](audiofix/revert-audio-fix.sh)
* **Summary:**
  * Addresses tinny speaker sound, lack of bass, and microphone capture degradation on the 16" MacBook Pro's 6-transducer acoustic array (2 tweeters, 4 force-cancelling woofers, 3 mics).
  * Replaces raw un-equalized multi-channel output with the official T2 Linux `t2-apple-audio-dsp` PipeWire / WirePlumber filter chain.
  * Injects model-specific FIR impulse response curves (`tweeters-48k.wav`, `woofers-48k.wav`), psychoacoustic virtual bass (`bankstown-lv2`), loudness compensation, woofer peak limiting (`lsp-plugins-lv2`), and 3-mic beamforming (`triforce-lv2`).
  * Presents a clean, standard 2-channel stereo sink `MacBook Pro T2 DSP Speakers` (`["FL", "FR"]`) while protecting physical transducers. Fully reversible at any time via `revert-audio-fix.sh`.

### 4. Utility Scripts
* **[`battery-limit`](battery-limit)** — Script to detect and configure charge stop thresholds under `/sys/class/power_supply/`.
* **[`fix-t2-usb-pm.sh`](fix-t2-usb-pm.sh)** — Top-level runner for `pmfix/apply-t2-pm-fix.sh`.
* **[`fix-t2-audio.sh`](fix-t2-audio.sh)** — Top-level runner for `audiofix/apply-audio-fix.sh`.
* **[`fix-graphics-and-grub.sh`](fix-graphics-and-grub.sh)** — Top-level runner for fixing GRUB timeout/font and protecting AMD dGPU from ASPM/powertop crashes.
* **[`graphics fix.md`](graphics%20fix.md)** — Detailed diagnostic log and resolution handoff for hybrid graphics & GRUB safety.
