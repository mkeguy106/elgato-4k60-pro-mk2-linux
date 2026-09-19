#!/usr/bin/env bash
# Automated bring-up checks for the Elgato 4K60 Pro Mk.2.
# Spec: docs/superpowers/specs/2026-09-19-bring-up-design.md, section 3.
# Usage: scripts/verify.sh [WIDTHxHEIGHT]   (expected source size, default 1920x1080)
# Needs: module loaded, source connected at 60 Hz SDR with sound playing.
set -uo pipefail
export LC_ALL=C

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=verify-lib.sh
source "$here/verify-lib.sh"
out="$here/../out"
mkdir -p "$out"

seconds=30
expect="${1:-1920x1080}"
fails=0
report() { # report NAME STATUS DETAIL
    printf '%-14s %-5s %s\n' "$1" "$2" "$3"
    [[ "$2" == FAIL ]] && fails=$((fails + 1))
    return 0
}

if grep -q '^sc0710 ' /proc/modules; then
    report module PASS "sc0710 is loaded"
else
    report module FAIL "sc0710 is not loaded"
    exit 1
fi

addr="$(find_pci_addr)" && node="$(find_video_node "$addr")" && card="$(find_alsa_card "$addr")"
if [[ -z "${node:-}" || -z "${card:-}" ]]; then
    report devices FAIL "pci=${addr:-none} video=${node:-none} alsa=${card:-none}"
    exit 1
fi
report devices PASS "pci=$addr video=$node alsa=hw:$card,0"

if timings="$(v4l2-ctl -d "$node" --query-dv-timings 2>&1 | parse_dv_timings)" && mode_ok "$timings" "$expect"; then
    report signal PASS "$timings"
else
    report signal FAIL "${timings:-no timings detected} (want $expect at 60)"
fi

formats="$(v4l2-ctl -d "$node" --list-formats-ext 2>&1)"
for fourcc in YUYV BGR3; do
    if format_has_size "$fourcc" "$expect" <<<"$formats"; then
        report "format-$fourcc" PASS "$expect listed"
    else
        report "format-$fourcc" FAIL "$expect not listed"
    fi
done

start="$(date '+%F %T')"
ffmpeg -hide_banner -nostdin -y \
    -f v4l2 -input_format yuyv422 -i "$node" \
    -f alsa -ac 2 -ar 48000 -i "hw:$card,0" \
    -map 0:v -t "$seconds" -f null - \
    -map 1:a -t "$seconds" "$out/audio.wav" \
    2>"$out/capture.log"
if frames="$(parse_frame_count <"$out/capture.log")" && frames_ok "$frames" "$seconds"; then
    report capture PASS "$frames frames in ${seconds}s"
else
    report capture FAIL "${frames:-0} frames in ${seconds}s (want 59-60.5 fps); see out/capture.log"
fi

journalctl -k --since "$start" --no-pager | grep -i sc0710 \
    | grep -iE 'error|fail|timeout|tear|short|resync|overrun' >"$out/kernel-errors.log"
if [[ -s "$out/kernel-errors.log" ]]; then
    report kernel-log FAIL "$(wc -l <"$out/kernel-errors.log") suspicious line(s); see out/kernel-errors.log"
else
    report kernel-log PASS "no sc0710 errors during capture"
fi

if [[ -s "$out/audio.wav" ]] \
    && vol="$(ffmpeg -hide_banner -nostdin -i "$out/audio.wav" -af volumedetect -f null - 2>&1 | parse_mean_volume)" \
    && volume_ok "$vol"; then
    report audio PASS "mean volume ${vol} dB"
else
    report audio FAIL "mean volume ${vol:-unknown} dB (want above -60; is the console playing sound?)"
fi

if ffmpeg -hide_banner -nostdin -y -f v4l2 -input_format yuyv422 -i "$node" \
        -frames:v 1 "$out/frame.png" 2>>"$out/capture.log" \
    && ffmpeg -hide_banner -nostdin -y -i "$out/frame.png" -vf scale=1920:-1 \
        "$out/frame-1080.png" 2>>"$out/capture.log"; then
    report picture LOOK "inspect out/frame-1080.png: correct image, aligned, right colours"
else
    report picture FAIL "could not save a frame; see out/capture.log"
fi

if [[ -f "$out/audio-defaults.before" ]]; then
    if diff -q "$out/audio-defaults.before" <(audio_defaults) >/dev/null; then
        report audio-default PASS "default sink and source unchanged"
    else
        report audio-default FAIL "default sink or source changed since baseline"
    fi
else
    report audio-default LOOK "no baseline at out/audio-defaults.before"
fi

echo
if (( fails )); then
    echo "$fails check(s) failed"
    exit 1
fi
echo "all automated checks passed"
