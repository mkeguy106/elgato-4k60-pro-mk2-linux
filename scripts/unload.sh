#!/usr/bin/env bash
# Unload the sc0710 module. rmmod refuses while anything holds the card's
# device nodes, and WirePlumber always does: its ALSA monitor keeps the card's
# control device open even when no application is capturing.
#
# Default: stop WirePlumber only, unload, start it again. The PipeWire daemon
# keeps running, so applications stay connected; their sound pauses for a
# second or two while WirePlumber re-links them.
#
#   --restart-pipewire   also stop PipeWire itself. Needed when PipeWire holds
#                        a capture device of the card open. This disconnects
#                        every application's audio, and some do not reconnect
#                        (seen with mpv and the Jellyfin desktop client).
#
# Close the player and any capture program first. rmmod -f is never used:
# force-unloading with an open capture descriptor is a use-after-free.
set -uo pipefail

full=0
case "${1:-}" in
    "") ;;
    --restart-pipewire) full=1 ;;
    *) echo "usage: ${0##*/} [--restart-pipewire]" >&2; exit 2 ;;
esac

if ! grep -q '^sc0710 ' /proc/modules; then
    echo "sc0710 is not loaded"
    exit 0
fi

if (( full )); then
    units=(pipewire.socket pipewire-pulse.socket pipewire.service pipewire-pulse.service wireplumber.service)
    echo "stopping PipeWire: every application's audio is disconnected" >&2
else
    units=(wireplumber.service)
fi
restart_audio() { systemctl --user start "${units[@]}"; }
trap restart_audio EXIT

systemctl --user stop "${units[@]}"

if sudo rmmod sc0710; then
    echo "sc0710 unloaded"
    exit 0
fi

echo "rmmod refused; processes still holding the device:" >&2
sudo fuser -v /dev/video* /dev/snd/* >&2 || true
if (( ! full )); then
    echo "Close the programs listed above and try again. If the holder is pipewire" >&2
    echo "itself, '${0##*/} --restart-pipewire' releases it, at the cost of" >&2
    echo "disconnecting every application's audio." >&2
fi
exit 1
