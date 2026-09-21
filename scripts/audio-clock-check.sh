#!/usr/bin/env bash
# Measures how fast the card's ALSA capture stream really advances, by reading
# the hardware pointer twice. A 48 kHz device must advance 48000 frames per
# second with or without an HDMI signal; sound servers use that as a clock.
# Needs a program capturing from the card (the player, OBS, arecord).
#
# Usage: scripts/audio-clock-check.sh [SECONDS]     (default 5)
set -uo pipefail
export LC_ALL=C

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=verify-lib.sh
source "$here/verify-lib.sh"

secs="${1:-5}"
addr="$(find_pci_addr)" || { echo "audio-clock-check: no card found" >&2; exit 1; }
card="$(find_alsa_card "$addr")" || { echo "audio-clock-check: the card has no ALSA device" >&2; exit 1; }
status="/proc/asound/card${card}/pcm0c/sub0/status"

read_ptr() { awk '/^hw_ptr/ {print $3}' "$status"; }

if ! grep -q '^state: RUNNING' "$status" 2>/dev/null; then
    echo "audio-clock-check: nothing is capturing from hw:${card},0 (state: $(awk '/^state/ {print $2}' "$status" 2>/dev/null || echo closed))" >&2
    exit 1
fi

p0="$(read_ptr)"; t0="$(date +%s.%N)"
sleep "$secs"
p1="$(read_ptr)"; t1="$(date +%s.%N)"

awk -v p0="$p0" -v p1="$p1" -v t0="$t0" -v t1="$t1" -v card="$card" 'BEGIN {
    rate = (p1 - p0) / (t1 - t0)
    off = (rate - 48000) / 48000 * 100
    printf "hw:%s  %.0f Hz over %.1f s  (%+.2f%% against 48000)\n", card, rate, t1 - t0, off
    exit (off < -1 || off > 1) ? 1 : 0
}'
