# Apple T2 MacBook Pro (`MacBookPro16,1`) Input Freeze & USB Runtime PM Runbook

This document details the root cause, kernel stack traces, diagnostic steps, and permanent solution for the internal keyboard, trackpad, and Touch Bar freeze issue encountered on Ubuntu T2 Linux (`ubuntu-26.04-7.3.3-2-t2-resolute`).

---

## 1. Problem Description & Symptoms

* **Hardware:** 2019 16" MacBook Pro (`MacBookPro16,1`), Intel Core i9-9880H, Apple T2 Security Chip (`iBridge: 24.16.6005.0.0,0`).
* **OS / Kernel:** Ubuntu 26.04 LTS, kernel `7.3.3-2-t2-resolute`.
* **Symptoms:**
  * After varying periods of uptime or brief idle periods (often 2–30 minutes), the internal keyboard, trackpad, and Touch Bar completely cease responding.
  * The rest of the operating system (display, audio, background services, network, CPU, RAM) continues running normally with no system panic.
  * Pressing the physical power button still immediately brings up the GNOME power-off/session dialog because the power key sends a direct hardware ACPI/SMC signal, but the user cannot click or press Enter.
  * Plugged-in external USB devices or SSH sessions remain functional if already connected.

---

## 2. Root Cause Analysis

### Architecture Background
On Apple T2 Macs, the internal keyboard, trackpad, Touch Bar display, Touch Bar backlight, FaceTime HD camera, and ambient light sensor do **not** connect via standard PS/2 or legacy I2C/SPI buses. Instead, they are exposed as **virtual USB devices** hosted on a virtual root hub (Bus 007) managed over PCIe by the Apple Buffer Copy Engine driver (`t2bce_core`, `t2bce_vhci`, `hid_appletb_kbd`, `hid_appletb_bl`, `apple-bce`).

All internal T2 human interface devices share Apple USB vendor ID `05ac`:
* `05ac:0340` — Apple Internal Keyboard / Trackpad
* `05ac:8302` — Apple Touch Bar Display
* `05ac:8102` — Apple Touch Bar Backlight
* `05ac:8104` — Apple Internal Subsystem
* `05ac:8233` — Apple iBridge
* `05ac:8262` — Apple Ambient Light Sensor
* `05ac:8103` — Apple Headset
* `05ac:8514` — Apple FaceTime HD Camera (Built-in)

### The Dual Deadlock Mechanism
During battery optimization efforts, power management tools (**TLP** with `USB_AUTOSUSPEND=1` and `pcie-aspm-tune.service` running `powertop --auto-tune`) enabled aggressive runtime autosuspend (`power/control="auto"`, `autosuspend_delay_ms=2000`) across all USB devices, including Bus 007.

Autosuspending these virtual devices triggers two distinct fatal kernel deadlocks:

#### Failure Mode A: Atomic Context Sleep in BCE DMA Handler (`BUG: scheduling while atomic`)
1. After 2 seconds of user inactivity, the kernel runtime-suspends the keyboard/trackpad (`05ac:0340`) and Touch Bar.
2. The user touches a key or the trackpad.
3. The T2 hardware sends a PCIe interrupt. The kernel BCE DMA interrupt service thread (`irq/98-bce_dma`) catches the completion while holding spinlocks (`bce_process_dma_completions_locked`).
4. In the completion path:
   `bce_vhci_transfer_queue_completion` $\to$ `usb_hcd_giveback_urb` $\to$ `hid_irq_in` $\to$ `input_handle_event` $\to$ `appletb_kbd_inp_event` $\to$ `appletb_kbd_set_mode` $\to$ `usbhid_power` $\to$ `usb_autopm_get_interface` $\to$ `rpm_resume`.
5. Because the USB device was suspended, `rpm_resume` calls `schedule()` to wait for the wake-up transition to finish.
6. **Sleeping while holding a spinlock in an interrupt thread is an atomic violation.** The kernel logs:
   ```text
   kernel: BUG: scheduling while atomic: irq/98-bce_dma/599/0x00000002
   kernel: Call Trace:
   kernel:  schedule+0x28/0xb0
   kernel:  rpm_resume+0x1b0/0x6d0
   kernel:  usb_autopm_get_interface+0x1b/0x70
   kernel:  usbhid_power+0x2f/0x50 [usbhid]
   kernel:  appletb_kbd_set_mode+0x47/0xd0 [hid_appletb_kbd]
   kernel:  appletb_kbd_inp_event+0x108/0x15c [hid_appletb_kbd]
   ...
   kernel:  bce_vhci_transfer_queue_completion+0x1c2/0x3d0 [t2bce_vhci]
   kernel:  bce_process_dma_completions_locked+0xba/0x140 [t2bce_core]
   ```
7. `irq/98-bce_dma` permanently hangs in state `D` (`TASK_UNINTERRUPTIBLE`), triggering repeating RCU stalls and `t2bce_vhci: [00] pause timeout waiting for 1 outputs`. All input processing stops.

#### Failure Mode B: Self-Deadlock in `pm_runtime_work`
When the kernel workqueue worker attempts to suspend `hid_appletb_kbd`:
1. `pm_runtime_work` $\to$ `rpm_suspend` $\to$ `hid_suspend` $\to$ `appletb_kbd_suspend`.
2. Inside `appletb_kbd_suspend`, it calls `appletb_kbd_set_mode` which calls `usb_autopm_get_interface` $\to$ `rpm_resume`.
3. Because the device is currently in the `RPM_SUSPENDING` transition state, `rpm_resume` blocks waiting for suspend to complete—which cannot happen because the suspend function is itself waiting for `rpm_resume`.
4. The worker thread locks up indefinitely (`INFO: task kworker/u64:0:12 blocked for more than 120 seconds`).

---

## 3. The Permanent Solution

To ensure rock-solid stability while retaining aggressive ASPM and battery tuning elsewhere, runtime autosuspend must be strictly prohibited on all Apple T2 internal devices and the T2 PCIe bridge.

The solution consists of four coordinated components:

### 1. TLP Denylist (`/etc/tlp.d/01-t2.conf`)
Denylists all 8 internal T2 USB device IDs and disables runtime PCIe power management on the T2 controller subtree:
```ini
# Prevent USB autosuspend on Apple T2 internal devices
USB_DENYLIST="05ac:0340 05ac:8302 05ac:8102 05ac:8104 05ac:8233 05ac:8262 05ac:8103 05ac:8514"

# Disable PCIe Runtime PM on the Apple T2 PCIe subtree
RUNTIME_PM_DISABLE="00:1b.0 04:00.0 04:00.1 04:00.2 04:00.3"
RUNTIME_PM_DRIVER_DENYLIST="mei_me nouveau radeon xhci_hcd t2bce_core t2bce_audio"
```

### 2. Udev Rule Safeguard (`/etc/udev/rules.d/90-apple-t2-usb-pm.rules`)
Enforces `power/control="on"` and `autosuspend_delay_ms="-1"` whenever USB or T2 PCI devices are added or change state:
```udev
ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="05ac", ATTR{power/autosuspend_delay_ms}="-1", ATTR{power/control}="on"
ACTION=="add|change", SUBSYSTEM=="usb", DRIVERS=="t2bce_vhci", ATTR{power/autosuspend_delay_ms}="-1", ATTR{power/control}="on"
ACTION=="add|change", SUBSYSTEM=="pci", ATTR{vendor}=="0x106b", ATTR{power/control}="on"
```

### 3. ASPM Script Protection (`/usr/local/sbin/pcie-aspm-tune.sh`)
Updated the ASPM tuning script so that:
1. `restore_apple_t2_runtime_pm` runs **before** `powertop --auto-tune` to disable delay timers (`autosuspend_delay_ms = -1`).
2. `restore_apple_t2_runtime_pm` runs **after** `powertop --auto-tune` to ensure all `05ac` devices and protected T2 PCIe endpoints are immediately forced back to `power/control = on`.

### 4. Automated Setup Script (`apply-t2-pm-fix.sh`)
Provides an idempotent, single-command installer to re-apply and verify the configuration across system updates.

---

## 4. Verification Commands

Run the following commands to confirm that T2 devices are exempt from autosuspend:

1. **Verify TLP USB status:**
   ```bash
   tlp-stat -u
   ```
   *Expected output:* All `Bus 007` devices report `control = on, autosuspend_delay_ms = -1`.

2. **Verify live sysfs power attributes:**
   ```bash
   for d in /sys/bus/usb/devices/7-*; do
       echo "$d: control=$(cat "$d/power/control") delay=$(cat "$d/power/autosuspend_delay_ms")"
   done
   ```
   *Expected output:* Every device under `7-*` has `control=on` and `delay=-1`.

3. **Verify kernel logs for any regressions:**
   ```bash
   journalctl -k -b 0 | grep -iE 'scheduling while|t2bce_vhci.*pause|blocked for more than'
   ```
   *Expected output:* Clean (no output).
