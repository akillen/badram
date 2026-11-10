#!/usr/bin/env bash
# ==============================================================================
# Apple T2 MacBook Pro (MacBookPro16,1) USB / PCIe Power Management Fix
# Prevents input freezes and scheduling-while-atomic deadlocks on T2 virtual USB.
# ==============================================================================
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
    echo "Please run as root: sudo bash $0" >&2
    exit 1
fi

echo "[+] 1. Installing TLP configuration (/etc/tlp.d/01-t2.conf)..."
mkdir -p /etc/tlp.d
cat >/etc/tlp.d/01-t2.conf <<'EOF'
# Prevent USB autosuspend on Apple T2 internal devices (keyboard, trackpad, Touch Bar, ALS, iBridge, camera)
# Autosuspending these causes a scheduling-while-atomic deadlock in irq/98-bce_dma and hid_appletb_kbd.
USB_DENYLIST="05ac:0340 05ac:8302 05ac:8102 05ac:8104 05ac:8233 05ac:8262 05ac:8103 05ac:8514"

# Disable PCIe Runtime PM on the Apple T2 PCIe subtree
RUNTIME_PM_DISABLE="00:1b.0 04:00.0 04:00.1 04:00.2 04:00.3"
RUNTIME_PM_DRIVER_DENYLIST="mei_me nouveau radeon xhci_hcd t2bce_core t2bce_audio"
EOF

echo "[+] 2. Installing udev rule (/etc/udev/rules.d/90-apple-t2-usb-pm.rules)..."
cat >/etc/udev/rules.d/90-apple-t2-usb-pm.rules <<'EOF'
# Keep Apple T2 USB devices and virtual root hub powered on (disable runtime autosuspend)
ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="05ac", ATTR{power/autosuspend_delay_ms}="-1", ATTR{power/control}="on"
ACTION=="add|change", SUBSYSTEM=="usb", DRIVERS=="t2bce_vhci", ATTR{power/autosuspend_delay_ms}="-1", ATTR{power/control}="on"
ACTION=="add|change", SUBSYSTEM=="pci", ATTR{vendor}=="0x106b", ATTR{power/control}="on"
EOF

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/pcie-aspm-tune.sh" ]]; then
    echo "[+] 3. Synchronizing /usr/local/sbin/pcie-aspm-tune.sh..."
    install -m 0755 "${SCRIPT_DIR}/pcie-aspm-tune.sh" /usr/local/sbin/pcie-aspm-tune.sh
fi

echo "[+] 4. Reloading udev rules..."
udevadm control --reload-rules

echo "[+] 5. Applying live power settings to T2 USB and PCIe devices..."
for usb_dev in /sys/bus/usb/devices/*; do
    [[ -e "${usb_dev}/power/control" ]] || continue
    real_path="$(readlink -f "$usb_dev" 2>/dev/null || true)"
    if [[ ( -f "${usb_dev}/idVendor" && "$(cat "${usb_dev}/idVendor" 2>/dev/null)" == "05ac" ) || "$real_path" == *"/t2bce_vhci/"* ]]; then
        if [[ -w "${usb_dev}/power/autosuspend_delay_ms" ]]; then
            echo "-1" >"${usb_dev}/power/autosuspend_delay_ms" 2>/dev/null || true
        fi
        status="$(cat "${usb_dev}/power/runtime_status" 2>/dev/null || true)"
        if [[ "$status" != "suspending" ]]; then
            echo "on" >"${usb_dev}/power/control" 2>/dev/null || true
        fi
        echo "  USB $(basename "$usb_dev"): control=$(cat "${usb_dev}/power/control" 2>/dev/null || echo '?') delay=$(cat "${usb_dev}/power/autosuspend_delay_ms" 2>/dev/null || echo '?')"
    fi
done

for pci_dev in 0000:00:1b.0 0000:04:00.0 0000:04:00.1 0000:04:00.2 0000:04:00.3; do
    if [[ -e "/sys/bus/pci/devices/${pci_dev}/power/control" ]]; then
        echo "on" >"/sys/bus/pci/devices/${pci_dev}/power/control" 2>/dev/null || true
        echo "  PCI ${pci_dev}: control=$(cat "/sys/bus/pci/devices/${pci_dev}/power/control" 2>/dev/null || echo '?')"
    fi
done

if command -v tlp >/dev/null 2>&1; then
    echo "[+] 6. Triggering TLP update..."
    tlp start >/dev/null 2>&1 || true
fi

echo "[+] Done! All Apple T2 devices are protected from autosuspend."
