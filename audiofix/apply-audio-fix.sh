#!/usr/bin/env bash
# apply-audio-fix.sh - Install T2 Apple Audio DSP for MacBookPro16,1
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Installing Apple T2 Audio DSP for MacBookPro16,1 ==="

# 1. Ensure required dependencies are installed
echo "Checking packages..."
pkexec apt-get install -y bankstown-lv2 triforce-lv2 swh-lv2 lsp-plugins-lv2 libpipewire-0.3-modules-extra libspa-0.2-modules-extra

# 2. Clean up legacy t2-better-audio udev rule if present
if [ -f "/usr/lib/udev/rules.d/91-audio-custom.rules" ]; then
    echo "Cleaning up legacy t2-better-audio udev rule..."
    pkexec rm -f "/usr/lib/udev/rules.d/91-audio-custom.rules"
fi

# 3. Install udev card rename rule
echo "Installing udev rename rule..."
pkexec bash -c "
    sed 's/@MODEL_DIR@/16_1/g' '${SCRIPT_DIR}/configs/99-t2-audio-rename.rules' > /etc/udev/rules.d/99-t2-audio-rename.rules
    chmod 0644 /etc/udev/rules.d/99-t2-audio-rename.rules
    udevadm control --reload-rules
    udevadm trigger --subsystem-match=sound --action=change
"

# 4. Install WirePlumber software DSP configuration
echo "Installing WirePlumber DSP configuration..."
pkexec bash -c "
    install -d -o root -g root -m 0755 /etc/wireplumber/wireplumber.conf.d
    install -o root -g root -m 0644 '${SCRIPT_DIR}/configs/wireplumber.conf' /etc/wireplumber/wireplumber.conf.d/50-t2-audio.conf
"

# 5. Install DSP curves, FIR impulse responses, and graphs
echo "Installing DSP graphs and FIR convolution files..."
pkexec bash -c "
    install -d -o root -g root -m 0755 /usr/share/t2linux-audio/16_1
    for ext in wav json; do
        for file in '${SCRIPT_DIR}/configs/16_1/'*.\$ext; do
            [ -e \"\$file\" ] || continue
            install -o root -g root -m 0644 \"\$file\" /usr/share/t2linux-audio/16_1/
        done
    done
"

# 6. Restart user PipeWire and WirePlumber services
echo "Restarting PipeWire and WirePlumber for current user..."
systemctl --user daemon-reexec
systemctl --user restart wireplumber pipewire pipewire-pulse

echo "=== Audio DSP setup completed successfully ==="
