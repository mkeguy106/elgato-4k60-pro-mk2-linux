#!/usr/bin/env bash
# Live view of the Elgato 4K60 Pro Mk.2.
#   Video: mpv reads the V4L2 node directly and shows frames as they arrive.
#   Audio: PipeWire loops the card's capture source to the default output and
#          corrects clock drift between the card and the output device.
# The two paths are separate on purpose. Muxing them into one stream made every
# video frame wait on the audio timeline: about 1.5 s of delay in practice.
# mpv's --audio-file with the ALSA device is silent (timestamp bases differ).
#
# Volume: 9/0, / and *, mouse wheel, m to mute (mpv-game-volume.lua adjusts the
#         PipeWire stream, because the audio does not pass through mpv).
#
# Usage: scripts/play.sh [extra mpv options]
#        AUDIO_LATENCY_MS=20 scripts/play.sh     (loopback latency, default 20)
set -uo pipefail
export LC_ALL=C

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=verify-lib.sh
source "$here/verify-lib.sh"

die() { echo "play.sh: $*" >&2; exit 1; }

grep -q '^sc0710 ' /proc/modules \
    || die "the sc0710 module is not loaded (sudo modprobe sc0710, or sudo insmod driver/build/sc0710.ko)"
addr="$(find_pci_addr)" || die "no Elgato 4K60 Pro Mk.2 found on the PCI bus"
node="$(find_video_node "$addr")" || die "the card has no V4L2 node"
pw="$(pipewire_name_for "$addr")"

find_source() { pactl list short sources | cut -f2 | grep -F "alsa_input.$pw." | head -n 1; }

src="$(find_source)"
if [[ -z "$src" ]]; then
    # PipeWire can list the card's input profile as active without creating the
    # node (seen when another program held the device at probe time).
    pactl set-card-profile "alsa_card.$pw" off
    pactl set-card-profile "alsa_card.$pw" input:stereo-fallback
    for _ in $(seq 1 20); do
        src="$(find_source)"
        [[ -n "$src" ]] && break
        sleep 0.2
    done
fi

log="$(mktemp)"
audio_pid=""
cleanup() {
    [[ -n "$audio_pid" ]] && kill "$audio_pid" 2>/dev/null
    rm -f "$log"
}
trap cleanup EXIT

if [[ -n "$src" ]]; then
    # The driver only delivers audio while video is streaming, so give mpv a
    # moment to start before the loopback opens the source.
    ( sleep 1; exec pw-loopback -C "$src" -l "${AUDIO_LATENCY_MS:-20}" -n elgato-capture-audio ) &
    audio_pid=$!
else
    echo "play.sh: PipeWire has no audio source for the card; continuing without sound" >&2
fi

mpv "av://v4l2:$node" --demuxer-lavf-o=input_format=yuyv422 \
    --profile=low-latency --untimed --no-audio \
    --script="$here/mpv-game-volume.lua" \
    --title="Elgato 4K60 Pro Mk.2" --log-file="$log" "$@"

if grep -q 'Cannot allocate memory' "$log"; then
    cat >&2 <<'MSG'
play.sh: the driver could not get contiguous memory for its DMA buffers.
It needs four 4 MB physically contiguous blocks below 4 GB, and after long
uptime there may be none. Free some and try again:
    sudo sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches'
    sudo sh -c 'echo 1 > /proc/sys/vm/compact_memory'
The durable fix is cma=256M on the kernel command line. See docs/bring-up-log.md.
MSG
    exit 1
fi
