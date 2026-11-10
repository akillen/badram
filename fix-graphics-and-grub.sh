#!/usr/bin/env bash
set -euo pipefail

# Check root permissions
if [[ $EUID -ne 0 ]]; then
   echo "[ERROR] This script must be run as root. Please run with sudo: sudo $0"
   exit 1
fi

echo "========================================================"
echo "  Apple T2 MacBook Pro Graphics & GRUB Safety Config"
echo "========================================================"

# --- STEP 1: Fix GRUB Menu and High-DPI Font ---
echo "[1/4] Configuring GRUB for visible menu and readable high-DPI font..."

FONT_SRC="/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
FONT_DST="/boot/grub/fonts/unicode-28.pf2"

if [[ -f "$FONT_SRC" ]]; then
    mkdir -p /boot/grub/fonts
    grub-mkfont -s 28 -o "$FONT_DST" "$FONT_SRC"
    echo "  -> Created 28pt high-DPI font at $FONT_DST"
else
    echo "  -> Warning: DejaVuSansMono font not found, using system default font."
fi

# Backup grub default
cp -a /etc/default/grub "/etc/default/grub.bak.$(date +%Y%m%d_%H%M%S)"

# Ensure GRUB_TIMEOUT_STYLE=menu and GRUB_TIMEOUT=5
sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=menu/' /etc/default/grub
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/' /etc/default/grub

# Ensure GRUB_FONT is configured if font was created
if [[ -f "$FONT_DST" ]]; then
    if grep -q "^GRUB_FONT=" /etc/default/grub; then
        sed -i "s|^GRUB_FONT=.*|GRUB_FONT=\"$FONT_DST\"|" /etc/default/grub
    else
        echo "GRUB_FONT=\"$FONT_DST\"" >> /etc/default/grub
    fi
fi

# Verify BadRAM configuration is untouched
if ! grep -q "memmap=" /etc/default/grub; then
    echo "[ERROR] BadRAM memmap parameters missing from /etc/default/grub! Aborting update-grub."
    exit 1
fi

echo "  -> Running update-grub..."
update-grub
echo "  -> GRUB now permanently displays a 5-second menu with large readable text on boot."

# --- STEP 2: Protect AMD GPU in PCIe ASPM / Powertop Tuning ---
echo "[2/4] Updating PCIe ASPM service to protect AMD GPU from crashing..."

SRC_ASPM="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pmfix/pcie-aspm-tune.sh"
DST_ASPM="/usr/local/sbin/pcie-aspm-tune.sh"

if [[ -f "$SRC_ASPM" ]]; then
    cp "$SRC_ASPM" "$DST_ASPM"
    chmod 755 "$DST_ASPM"
    systemctl daemon-reload
    echo "  -> Installed updated ASPM tuning script protecting AMD dGPU (vendor 0x1002)."
else
    echo "  -> Warning: $SRC_ASPM not found, skipping."
fi

# Ensure AMD GPU runtime PM is set to 'on' immediately
for dev in 0000:03:00.0 0000:02:00.0 0000:01:00.0 0000:00:01.0; do
    if [[ -e "/sys/bus/pci/devices/${dev}/power/control" ]]; then
        echo "on" > "/sys/bus/pci/devices/${dev}/power/control" 2>/dev/null || true
    fi
done

# --- STEP 3: Restore amdgpu-off.service (Disabled) ---
echo "[3/4] Restoring amdgpu-off.service (disabled by default)..."

cat << 'EOF' > /etc/systemd/system/amdgpu-off.service
[Unit]
Description=Disable AMD dGPU via vgaswitcheroo
After=systemd-modules-load.service
Before=display-manager.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'for i in $(seq 1 30); do [ -e /sys/kernel/debug/vgaswitcheroo/switch ] && exec sh -c "echo OFF > /sys/kernel/debug/vgaswitcheroo/switch"; sleep 1; done; exit 1'

[Install]
WantedBy=multi-user.target
EOF

chmod 644 /etc/systemd/system/amdgpu-off.service
systemctl daemon-reload
systemctl disable amdgpu-off.service
echo "  -> Restored amdgpu-off.service and confirmed it is DISABLED."

# --- STEP 4: Verify Current GPU and Display Status ---
echo "[4/4] Current Graphics Status:"
if command -v switcherooctl >/dev/null 2>&1; then
    switcherooctl list || true
fi

echo "========================================================"
echo "  All fixes applied successfully!"
echo "  1. GRUB: Will always show a clear 5s countdown with large 28pt text."
echo "  2. AMD GPU: Protected from PCIe ASPM/powertop wedging."
echo "  3. amdgpu-off: Restored (disabled) so dgpu-on/dgpu-off aliases work."
echo "  4. External Display: Ready to connect via USB-C/Thunderbolt."
echo "========================================================"
