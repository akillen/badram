#!/usr/bin/env bash
# ==============================================================================
# T2 MacBook Pro (MacBookPro16,1) BadRAM & Kernel memmap Setup Script
# Derived from 8-pass MemTest86 physical address log (2026-11-08)
# ==============================================================================
set -euo pipefail

GRUB_FILE="/etc/default/grub"
BACKUP_FILE="/etc/default/grub.bak.$(date +%Y%m%d-%H%M%S)"

# Padded GRUB_BADRAM: masks 12x 2MB twin regions (24 MB total) covering all 20 bad pages
BADRAM_VAL="0x00000001c8600000,0xfffffffffde00000,0x000000031d200000,0xfffffffffde00000,0x0000000345600000,0xfffffffffde00000,0x00000003c4200000,0xfffffffffde00000,0x00000003c4c00000,0xfffffffffde00000,0x0000000408e00000,0xfffffffffde00000"

# Consolidated kernel memmap=: reserves 5x 48MB blocks (240 MB total) across each twin pair
# Note: \$ in /etc/default/grub ensures update-grub writes \$ into /boot/grub/grub.cfg
MEMMAP_ARGS='memmap=48M\$0x1c8000000 memmap=48M\$0x31d000000 memmap=48M\$0x345000000 memmap=48M\$0x3c4000000 memmap=48M\$0x408000000'

if [[ $EUID -ne 0 ]]; then
    echo "Please run as root: sudo bash $0"
    exit 1
fi

cp -a "$GRUB_FILE" "$BACKUP_FILE"
echo "[+] Backed up $GRUB_FILE to $BACKUP_FILE"

# Configure GRUB_BADRAM
if grep -q '^GRUB_BADRAM=' "$GRUB_FILE"; then
    sed -i "s|^GRUB_BADRAM=.*|GRUB_BADRAM=\"${BADRAM_VAL}\"|" "$GRUB_FILE"
else
    echo "" >> "$GRUB_FILE"
    echo "# Quarantine bad physical RAM clusters (MemTest86 2026-11-08)" >> "$GRUB_FILE"
    echo "GRUB_BADRAM=\"${BADRAM_VAL}\"" >> "$GRUB_FILE"
fi

# Append memmap= args to GRUB_CMDLINE_LINUX_DEFAULT if not already present
if ! grep -q '0x1c8000000' "$GRUB_FILE"; then
    sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"|GRUB_CMDLINE_LINUX_DEFAULT=\"\1 ${MEMMAP_ARGS}\"|" "$GRUB_FILE"
fi

echo "[+] Updated $GRUB_FILE:"
grep -E '^(GRUB_BADRAM|GRUB_CMDLINE_LINUX_DEFAULT)=' "$GRUB_FILE"

echo "[+] Regenerating /boot/grub/grub.cfg..."
update-grub

echo "[+] Verifying /boot/grub/grub.cfg contains badram and escaped memmap..."
grep -E 'badram |memmap=' /boot/grub/grub.cfg | head -n 5

echo "[+] Done! Reboot and verify with: sudo dmesg | grep -E 'BIOS-e820|user-defined physical RAM map' -A 25"
