# 2019 16" T2 MacBook Pro (`MacBookPro16,1`) BadRAM Quarantine Handover & Runbook

This document contains the complete hardware inventory, physical memory failure map (extracted from 8 passes / ~7 hours of MemTest86 V11.7 logs on `2026-11-08`), and step-by-step instructions to quarantine the defective RAM regions on Linux (`ubuntu-26.04-7.1.8-t2-resolute.iso`)—either from Windows/WSL2 or directly from a new session on the MacBook Pro.

---

## 1. System & Hardware Inventory

* **Model:** Apple `MacBookPro16,1` (2019 16-inch MacBook Pro, Board ID `Mac-E1008331FDC96864`)
* **CPU:** Intel Core i9-9880H @ 2.30 GHz (8 cores / 16 threads)
* **Security Chip:** Apple T2 (`iBridge: 24.16.6005.0.0,0`, EFI `2103.160.2.0.0`)
* **System RAM:** 16 GB (2 × 8 GB SK Hynix `HMA81GS6CJR8N-VK` DDR4-2666 MT/s, 19-19-19-43, 1.2V)
* **Tested Physical Address Span:** `0x0` – `0x47F000000` (18,416 MB address space due to `0x7B000000–0xFFFFFFFF` PCIe/MMIO hole below 4 GB)
* **Internal NVMe Partitions Detected:**
  1. `HD(1,GPT,3FC7B265-886D-42FA-8FD2-F553E7204868)` — EFI (300 MB)
  2. `HD(2,GPT,E7F63BF0-D841-4A82-89DC-798441893004)` — macOS APFS (`Macintosh HD`, ~238 GB)
  3. `HD(3,GPT,5949AFB1-6B1E-450B-9A53-FEAED5A94CC1)` — `Linux` (~715 GB)

---

## 2. Complete Physical Memory Error Map

Across **8 full passes** (Session 1: `03:35–07:09` with 621 errors; Session 2: `13:09–16:37` with 50 errors), **100% of all errors occurred inside the exact same 20 physical 4 KB pages (80 KB total)**. Zero new pages appeared after Pass 1 of Session 1.

### Key Architectural Findings
1. **Lower 7.13 GB (`0x0` – `0x1C87E7FFF`) is 100% Clean:** Zero errors occurred anywhere below `0x1C87E8150` (~7,303 MB). Apple UEFI, GRUB, T2 `apple-bce` early boot buffers, and the Linux kernel/`initramfs` all load well below 4 GB (`0x100000000`), so early boot will not hit bad RAM.
2. **Bit-25 (`0x02000000` = 32 MB) Hardware Bank/Row Mirror:** Every single defective region appears as an exact twin separated by `0x02000000` (32 MB, bit 25) with the identical sub-megabyte offset and identical stuck data bit (`Expected ^ Actual`):

| Cluster | Lower Twin (`Bit 25 = 0`) | Upper Twin (`Bit 25 = 1`, `+0x2000000`) | Approx. Offset | Stuck Bit Mask (`XOR`) | Logged Hits |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1** | `0x1C87E8000` – `0x1C87F0000` *(pages `0x1C87E8`, `0x1C87EF`)* | `0x1CA7E8000` – `0x1CA7F0000` *(pages `0x1CA7E8`, `0x1CA7E9`, `0x1CA7EE`, `0x1CA7EF`)* | ~7.13 GB / ~7.16 GB | `0x00000001`, `0x00000004` | 27 |
| **2** | `0x31D266000` – `0x31D268000` *(pages `0x31D266`, `0x31D267`)* | `0x31F266000` – `0x31F268000` *(pages `0x31F266`, `0x31F267`)* | ~12.46 GB / ~12.49 GB | `0x00400000` | 60 |
| **3** | `0x3457CF000` – `0x3457D0000` *(page `0x3457CF`)* | `0x3477CF000` – `0x3477D0000` *(page `0x3477CF`)* | ~13.09 GB / ~13.12 GB | `0x20000000` | 2 |
| **4a** | `0x3C430D000` – `0x3C430E000` *(page `0x3C430D`)* | `0x3C630D000` – `0x3C630E000` *(page `0x3C630D`)* | ~15.07 GB / ~15.10 GB | `0x00001000` | 17 |
| **4b** | `0x3C4C96000` – `0x3C4C98000` *(pages `0x3C4C96`, `0x3C4C97`)* | `0x3C6C96000` – `0x3C6C98000` *(pages `0x3C6C96`, `0x3C6C97`)* | ~15.07 GB / ~15.11 GB | `0x00002000` | 210 |
| **5** | `0x408FC7000` – `0x408FC8000` *(page `0x408FC7`)* | `0x40AFC7000` – `0x40AFC8000` *(page `0x40AFC7`)* | ~16.14 GB / ~16.17 GB | `0x00000100` | 25 |

### Exact List of All 20 Failing 4 KB Pages
```text
0x1C87E8000 - 0x1C87E8FFF   (min=0x1C87E8150, max=0x1C87E8810, xor=0x00000004)
0x1C87EF000 - 0x1C87EFFFF   (min=0x1C87EF440, max=0x1C87EF440, xor=0x00000001)
0x1CA7E8000 - 0x1CA7E8FFF   (min=0x1CA7E80B0, max=0x1CA7E8B80, xor=0x00000004)
0x1CA7E9000 - 0x1CA7E9FFF   (min=0x1CA7E99A8, max=0x1CA7E99A8, xor=0x00000004)
0x1CA7EE000 - 0x1CA7EEFFF   (min=0x1CA7EE608, max=0x1CA7EE608, xor=0x00000001)
0x1CA7EF000 - 0x1CA7EFFFF   (min=0x1CA7EF340, max=0x1CA7EF420, xor=0x00000001)
0x31D266000 - 0x31D266FFF   (min=0x31D266F14, max=0x31D266FF0, xor=0x00400000)
0x31D267000 - 0x31D267FFF   (min=0x31D267030, max=0x31D267930, xor=0x00400000)
0x31F266000 - 0x31F266FFF   (min=0x31F266F10, max=0x31F266FD0, xor=0x00400000)
0x31F267000 - 0x31F267FFF   (min=0x31F267010, max=0x31F267910, xor=0x00400000)
0x3457CF000 - 0x3457CFFFF   (min=0x3457CF830, max=0x3457CF830, xor=0x20000000)
0x3477CF000 - 0x3477CFFFF   (min=0x3477CF810, max=0x3477CF810, xor=0x20000000)
0x3C430D000 - 0x3C430DFFF   (min=0x3C430DA18, max=0x3C430DD58, xor=0x00001000)
0x3C4C96000 - 0x3C4C96FFF   (min=0x3C4C96F48, max=0x3C4C96FC8, xor=0x00002000)
0x3C4C97000 - 0x3C4C97FFF   (min=0x3C4C97008, max=0x3C4C97948, xor=0x00002000)
0x3C630D000 - 0x3C630DFFF   (min=0x3C630D9F8, max=0x3C630DD38, xor=0x00001000)
0x3C6C96000 - 0x3C6C96FFF   (min=0x3C6C96F28, max=0x3C6C96FE8, xor=0x00002000)
0x3C6C97000 - 0x3C6C97FFF   (min=0x3C6C97028, max=0x3C6C97E78, xor=0x00002000)
0x408FC7000 - 0x408FC7FFF   (min=0x408FC7390, max=0x408FC73B0, xor=0x00000100)
0x40AFC7000 - 0x40AFC7FFF   (min=0x40AFC72D0, max=0x40AFC7390, xor=0x00000100)
```

---

## 3. Ready-to-Use GRUB & Kernel Parameters

### A. Padded `GRUB_BADRAM` (Masks 12 × 2 MB blocks = 24 MB total)
Clearing bit 25 (`0x02000000`) in the 64-bit mask (`0xfffffffffde00000`) causes each `addr,mask` pair to match **both** the lower and upper twin simultaneously with a 2 MB safety boundary:
```text
0x00000001c8600000,0xfffffffffde00000,0x000000031d200000,0xfffffffffde00000,0x0000000345600000,0xfffffffffde00000,0x00000003c4200000,0xfffffffffde00000,0x00000003c4c00000,0xfffffffffde00000,0x0000000408e00000,0xfffffffffde00000
```

### B. Surgical `GRUB_BADRAM` (Masks only 46 pages = 184 KB total)
```text
0x00000001c87e0000,0xfffffffffdff0000,0x000000031d266000,0xfffffffffdffe000,0x00000003457cf000,0xfffffffffdfff000,0x00000003c430d000,0xfffffffffdfff000,0x00000003c4c96000,0xfffffffffdffe000,0x0000000408fc7000,0xfffffffffdfff000
```

### C. Consolidated Kernel `memmap=` (Reserves 5 × 48 MB blocks = 240 MB total)
* **In raw `/boot/grub/grub.cfg` (or interactive GRUB edit mode `e`):**
  ```text
  memmap=48M\$0x1c8000000 memmap=48M\$0x31d000000 memmap=48M\$0x345000000 memmap=48M\$0x3c4000000 memmap=48M\$0x408000000
  ```
* **In `/etc/default/grub` (inside double quotes, so `update-grub` outputs `\$`):**
  ```bash
  GRUB_BADRAM="0x00000001c8600000,0xfffffffffde00000,0x000000031d200000,0xfffffffffde00000,0x0000000345600000,0xfffffffffde00000,0x00000003c4200000,0xfffffffffde00000,0x00000003c4c00000,0xfffffffffde00000,0x0000000408e00000,0xfffffffffde00000"
  GRUB_CMDLINE_LINUX_DEFAULT="quiet splash intel_iommu=on iommu=pt pm_async=off memmap=48M\\$0x1c8000000 memmap=48M\\$0x31d000000 memmap=48M\\$0x345000000 memmap=48M\\$0x3c4000000 memmap=48M\\$0x408000000"
  ```

---

## 4. Fallback Plan: How to Patch the ISO or USB Directly on the MacBook (macOS)

If you ever need to re-patch a fresh copy of `ubuntu-26.04-7.1.8-t2-resolute.iso` (or an already-flashed USB stick `/dev/diskN`) directly from a new session on the MacBook Pro:

### Why Direct Sector Patching Is Simpler Than Mounting & Repacking on macOS
Mounting an `.iso` on macOS mounts it **read-only**, and rebuilding a bootable hybrid T2 UEFI ISO from scratch requires `xorriso` with exact El Torito boot catalog flags.

Instead, in `ubuntu-26.04-7.1.8-t2-resolute.iso`:
* `/boot/grub/grub.cfg` is stored uncompressed at **2048-byte sector `6499`** (byte offset `0xCB1800`).
* `/boot/grub/loopback.cfg` is stored uncompressed at **2048-byte sector `7800`** (byte offset `0xF3C000`).
* Their ISO9660 directory entry file-size fields sit in **sector `23`** (byte offset `0xB800`).
* `/md5sum.txt` sits at **sector `2451805`** (byte offset `0x4AD15A800`, length `60256` bytes).

Because the patched `grub.cfg` (`1340` bytes) and `loopback.cfg` (`852` bytes) still fit inside their original single 2048-byte sectors, **a 40-line Python 3 script can patch either the `.iso` file OR the raw USB drive (`/dev/rdiskX`) in-place in under 1 second** with zero external tools:

```python
#!/usr/bin/env python3
"""
In-place BadRAM + memmap patcher for ubuntu-26.04-7.1.8-t2-resolute.iso (or raw USB device).
Usage: python3 patch_t2_iso.py /path/to/ubuntu-26.04-7.1.8-t2-resolute.iso
"""
import hashlib, re, struct, sys

target_path = sys.argv[1]

new_grub_cfg = (
    "set timeout=10\n\n"
    "badram 0x00000001c8600000,0xfffffffffde00000,0x000000031d200000,0xfffffffffde00000,0x0000000345600000,0xfffffffffde00000,0x00000003c4200000,0xfffffffffde00000,0x00000003c4c00000,0xfffffffffde00000,0x0000000408e00000,0xfffffffffde00000\n\n"
    "loadfont unicode\n\n"
    "set menu_color_normal=white/black\n"
    "set menu_color_highlight=black/light-gray\n\n"
    "menuentry \"Try or Install Ubuntu (T2 BadRAM Patched)\" {\n"
    "    set gfxpayload=keep\n"
    "    linux  /casper/vmlinuz  memmap=48M\\$0x1c8000000 memmap=48M\\$0x31d000000 memmap=48M\\$0x345000000 memmap=48M\\$0x3c4000000 memmap=48M\\$0x408000000 --- quiet splash intel_iommu=on iommu=pt pm_async=off\n"
    "    initrd /casper/initrd\n"
    "}\n"
    "menuentry \"Try or Install Ubuntu (Lower 7GB RAM Only - mem=7G)\" {\n"
    "    set gfxpayload=keep\n"
    "    linux  /casper/vmlinuz  mem=7G --- quiet splash intel_iommu=on iommu=pt pm_async=off\n"
    "    initrd /casper/initrd\n"
    "}\n"
    "menuentry \"Ubuntu (safe graphics + T2 BadRAM Patched)\" {\n"
    "    set gfxpayload=keep\n"
    "    linux  /casper/vmlinuz nomodeset  memmap=48M\\$0x1c8000000 memmap=48M\\$0x31d000000 memmap=48M\\$0x345000000 memmap=48M\\$0x3c4000000 memmap=48M\\$0x408000000 --- quiet splash intel_iommu=on iommu=pt pm_async=off\n"
    "    initrd /casper/initrd\n"
    "}\n"
    "grub_platform\n"
    "if [ \"$grub_platform\" = \"efi\" ]; then\n"
    "menuentry 'Boot from next volume' {\n"
    "    exit 1\n"
    "}\n"
    "menuentry 'UEFI Firmware Settings' {\n"
    "    fwsetup\n"
    "}\n"
    "fi\n"
).encode("ascii")

new_loopback_cfg = (
    "\n"
    "badram 0x00000001c8600000,0xfffffffffde00000,0x000000031d200000,0xfffffffffde00000,0x0000000345600000,0xfffffffffde00000,0x00000003c4200000,0xfffffffffde00000,0x00000003c4c00000,0xfffffffffde00000,0x0000000408e00000,0xfffffffffde00000\n"
    "menuentry \"Try or Install Ubuntu (T2 BadRAM Patched)\" {\n"
    "    set gfxpayload=keep\n"
    "    linux  /casper/vmlinuz  memmap=48M\\$0x1c8000000 memmap=48M\\$0x31d000000 memmap=48M\\$0x345000000 memmap=48M\\$0x3c4000000 memmap=48M\\$0x408000000 iso-scan/filename=${iso_path} --- quiet splash\n"
    "    initrd /casper/initrd\n"
    "}\n"
    "menuentry \"Ubuntu (safe graphics + T2 BadRAM Patched)\" {\n"
    "    set gfxpayload=keep\n"
    "    linux  /casper/vmlinuz nomodeset  memmap=48M\\$0x1c8000000 memmap=48M\\$0x31d000000 memmap=48M\\$0x345000000 memmap=48M\\$0x3c4000000 memmap=48M\\$0x408000000 iso-scan/filename=${iso_path} --- quiet splash\n"
    "    initrd /casper/initrd\n"
    "}"
).encode("ascii")

grub_md5 = hashlib.md5(new_grub_cfg).hexdigest()
loop_md5 = hashlib.md5(new_loopback_cfg).hexdigest()

with open(target_path, "r+b") as f:
    f.seek(23 * 2048)
    s23 = bytearray(f.read(2048))
    for ext, new_len in [(6499, len(new_grub_cfg)), (7800, len(new_loopback_cfg))]:
        pat = struct.pack("<I", ext) + struct.pack(">I", ext)
        pos = s23.find(pat)
        assert pos != -1, f"Extent {ext} not found in sector 23"
        s23[pos+8:pos+16] = struct.pack("<I", new_len) + struct.pack(">I", new_len)
    f.seek(23 * 2048)
    f.write(bytes(s23))

    f.seek(6499 * 2048)
    f.write(new_grub_cfg.ljust(2048, b"\x00"))

    f.seek(7800 * 2048)
    f.write(new_loopback_cfg.ljust(2048, b"\x00"))

    f.seek(2451805 * 2048)
    orig_md5 = f.read(60256).decode("ascii")
    new_md5 = re.sub(r"[0-9a-f]{32}(\s+\./boot/grub/grub\.cfg)", grub_md5 + r"\1", orig_md5)
    new_md5 = re.sub(r"[0-9a-f]{32}(\s+\./boot/grub/loopback\.cfg)", loop_md5 + r"\1", new_md5)
    f.seek(2451805 * 2048)
    f.write(new_md5.encode("ascii"))

print("Patched successfully!")
```

---

## 5. Verification Checklist Inside Linux

1. **Confirm the kernel command line:**
   ```bash
   cat /proc/cmdline
   ```
   Verify `memmap=48M$0x1c8000000 memmap=48M$0x31d000000 memmap=48M$0x345000000 memmap=48M$0x3c4000000 memmap=48M$0x408000000` appears with literal `$` signs.
2. **Confirm the E820 / EFI memory map exclusions:**
   ```bash
   sudo dmesg | grep -E "BIOS-e820|user-defined physical RAM map" -A 35
   ```
   Verify `reserved` / `unusable` ranges cover:
   * `0x00000001c8000000 - 0x00000001caffffff`
   * `0x000000031d000000 - 0x000000031fffffff`
   * `0x0000000345000000 - 0x0000000347ffffff`
   * `0x00000003c4000000 - 0x00000003c6ffffff`
   * `0x0000000408000000 - 0x000000040affffff`
3. **Persist onto the installed system before rebooting (or on first boot):**
   Run `sudo bash apply-t2-badram.sh` (or edit `/etc/default/grub` as shown in Section 3C and run `sudo update-grub`).
4. **Stress-test the remaining 16.1 GB of usable RAM:**
   ```bash
   sudo apt-get install -y stress-ng
   stress-ng --vm 8 --vm-bytes 85% --verify -t 15m
   ```
