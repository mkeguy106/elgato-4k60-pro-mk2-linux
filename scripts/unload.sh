#!/usr/bin/env bash
# Unload the sc0710 module. PipeWire and WirePlumber keep the V4L2 and ALSA
# nodes open even when no application is capturing, so rmmod refuses until
# they let go. This stops them, unloads, and starts them again. Desktop audio
# drops out for a few seconds. rmmod -f is never used: force-unloading with an
# open capture descriptor is a use-after-free.
set -uo pipefail

if ! grep -q '^sc0710 ' /proc/modules; then
    echo "sc0710 is not loaded"
    exit 0
fi

units=(pipewire.socket pipewire-pulse.socket pipewire.service pipewire-pulse.service wireplumber.service)
restart_audio() { systemctl --user start "${units[@]}"; }
trap restart_audio EXIT

systemctl --user stop "${units[@]}"

if sudo rmmod sc0710; then
    echo "sc0710 unloaded"
    exit 0
fi

echo "rmmod refused; processes still holding the device:" >&2
sudo fuser -v /dev/video* /dev/snd/* >&2 || true
exit 1
