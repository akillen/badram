# T2 MacBook Pro Graphics, PCIe Power Management & GRUB Safety Guide

## 1. What Actually Happened (Root Cause Investigation)

Earlier, when attempting to turn discrete graphics on (`dgpu-on`) to connect an external monitor, the system experienced a login loop (logging in via GDM would instantly freeze and kick you back to the login screen).

### Root Causes Discovered in System Logs:
1. **The Login Loop / GPU Freeze:**
   * It was **not** a fundamental Wayland incompatibility.
   * During boot, `pcie-aspm-tune.service` executed `powertop --auto-tune` and forced PCIe ASPM link power management across the system.
   * Because the AMD Navi 14 dGPU (`0000:03:00.0`, vendor ID `0x1002`) was only protected when turned off via `vgaswitcheroo`, `powertop --auto-tune` enabled runtime autosuspend and aggressive link power management on the AMD GPU and its upstream PCIe bridges while GNOME Shell was actively rendering.
   * This triggered:
     ```
     kernel: amdgpu 0000:03:00.0: ring gfx_0.0.0 timeout
     kernel: amdgpu 0000:03:00.0: [drm] device wedged
     gnome-shell: amdgpu: The CS has cancelled because the context is lost.
     ```
   * As soon as the GPU wedged, GNOME Shell crashed and logind terminated the user session, trapping you in a login loop.

2. **The GRUB Intercept Nightmare:**
   * `/etc/default/grub` had `GRUB_TIMEOUT=0` and `GRUB_TIMEOUT_STYLE=hidden`.
   * On Apple EFI firmware, this made intercepting GRUB nearly impossible without spamming Escape, which easily dumped you into an unconfigured `grub>` command prompt.
   * Furthermore, on the 16-inch Retina display (3072x1920), no high-DPI GRUB font was specified, rendering bootloader text tiny and unreadable.

---

## 2. The Solution & Safeguards

We created an automated runner script: [`fix-graphics-and-grub.sh`](fix-graphics-and-grub.sh)

### What it does:
1. **GRUB Peace of Mind:**
   * Generates a large **28pt high-DPI font** (`/boot/grub/fonts/unicode-28.pf2`) from `DejaVuSansMono.ttf`.
   * Sets `GRUB_TIMEOUT=5` and `GRUB_TIMEOUT_STYLE=menu`.
   * **Result:** Every time you boot or reboot, GRUB will comfortably show a 5-second countdown menu with big, clear, readable text. You will **never** have to mash the Escape key or panic again.
   * Preserves all `BadRAM` parameters (`GRUB_BADRAM`, `memmap=...`) intact.
2. **AMD dGPU PCIe & Power Protection:**
   * Updated `pcie-aspm-tune.sh` to explicitly add `0x1002` (AMD vendor ID) and all its upstream PCIe bridges to `PROTECTED_DEVICES`.
   * Prevents `powertop --auto-tune` or ASPM scripts from ever touching the AMD GPU power states or PCIe links while it is running.
3. **Restores `amdgpu-off.service` (Disabled):**
   * Recreates `/etc/systemd/system/amdgpu-off.service`.
   * Keeps it **disabled** so the AMD card remains powered on for external monitors.
   * Restores full functionality to the `dgpu-on`, `dgpu-off`, and `dgpu-status` aliases in `~/.bashrc`.

---

## 3. How to Apply

In your terminal, execute:
```bash
sudo /home/aaronkillen/Development/badram/fix-graphics-and-grub.sh
```

Once run, you can safely plug in your external monitor via any USB-C / Thunderbolt port without risk of crashing or losing boot access.
