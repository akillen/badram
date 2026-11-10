#!/usr/bin/env bash
# revert-audio-fix.sh - Cleanly uninstall T2 Apple Audio DSP and restore stock audio
set -euo pipefail

echo "=== Reverting Apple T2 Audio DSP configurations ==="

pkexec bash -c "
    echo 'Removing udev ALSA card rename rule...'
    rm -f /etc/udev/rules.d/99-t2-audio-rename.rules
    if command -v udevadm >/dev/null 2>&1; then
        udevadm control --reload-rules
        udevadm trigger --subsystem-match=sound --action=change
    fi

    echo 'Removing WirePlumber DSP configuration...'
    rm -f /etc/wireplumber/wireplumber.conf.d/50-t2-audio.conf
    rm -f /etc/wireplumber/wireplumber.conf.d/*-dsp.conf

    echo 'Removing audio data (FIRs and graphs)...'
    rm -rf /usr/share/t2linux-audio
"

echo "Restarting WirePlumber and PipeWire for current user..."
systemctl --user daemon-reexec
systemctl --user restart wireplumber pipewire pipewire-pulse

echo "=== Audio DSP configurations completely reverted ==="
echo "Stock raw audio routing is restored."
