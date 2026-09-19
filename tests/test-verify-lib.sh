#!/usr/bin/env bash
# Tests for scripts/verify-lib.sh. Run: bash tests/test-verify-lib.sh
set -uo pipefail
export LC_ALL=C
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

failures=0
check() { # check DESCRIPTION EXPECTED ACTUAL
    if [[ "$2" == "$3" ]]; then
        printf 'ok    %s\n' "$1"
    else
        printf 'FAIL  %s\n      expected: %q\n      actual:   %q\n' "$1" "$2" "$3"
        failures=$((failures + 1))
    fi
}
status() { "$@" >/dev/null 2>&1; echo $?; }

# Fake sysfs: one sc0710 card at 0000:03:00.0 with video2 and sound card3,
# plus an unrelated webcam on video0 and sound card1.
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
card="$root/devices/pci0000:00/0000:03:00.0"
cam="$root/devices/pci0000:00/0000:00:14.0"
mkdir -p "$card" "$cam" "$root/bus/pci/devices" \
    "$root/class/video4linux/video0" "$root/class/video4linux/video2" \
    "$root/class/sound/card1" "$root/class/sound/card3"
echo 0x12ab >"$card/vendor"; echo 0x0710 >"$card/device"
echo 0x8086 >"$cam/vendor";  echo 0xa36d >"$cam/device"
ln -s "$card" "$root/bus/pci/devices/0000:03:00.0"
ln -s "$cam"  "$root/bus/pci/devices/0000:00:14.0"
ln -s "$cam"  "$root/class/video4linux/video0/device"
ln -s "$card" "$root/class/video4linux/video2/device"
ln -s "$cam"  "$root/class/sound/card1/device"
ln -s "$card" "$root/class/sound/card3/device"

export SYSFS_ROOT="$root"
# shellcheck source=../scripts/verify-lib.sh
source "$here/../scripts/verify-lib.sh"

check "find_pci_addr finds the card"        "0000:03:00.0" "$(find_pci_addr)"
check "find_video_node picks the card node" "/dev/video2"  "$(find_video_node 0000:03:00.0)"
check "find_alsa_card picks the card index" "3"            "$(find_alsa_card 0000:03:00.0)"
check "find_video_node fails for no match"  "1"            "$(status find_video_node 0000:09:00.0)"
check "find_alsa_card fails for no match"   "1"            "$(status find_alsa_card 0000:09:00.0)"
check "find_pci_addr fails with no card"    "1"            "$(SYSFS_ROOT="$root/empty" status find_pci_addr)"

timings_4k60=$'\tActive width: 3840\n\tActive height: 2160\n\tTotal width: 4400\n\tTotal height: 2250\n\tFrame format: progressive\n\tPixelclock: 594000000 Hz (60.00 frames per second)'
timings_1080=$'\tActive width: 1920\n\tActive height: 1080\n\tPixelclock: 148500000 Hz (59.94 frames per second)'
check "parse_dv_timings 4k60"     "3840x2160 60.00" "$(parse_dv_timings <<<"$timings_4k60")"
check "parse_dv_timings 1080p"    "1920x1080 59.94" "$(parse_dv_timings <<<"$timings_1080")"
check "parse_dv_timings garbage"  "1" "$(status parse_dv_timings <<<"no signal")"
check "mode_ok accepts 1080p 60.00"   "0" "$(status mode_ok "1920x1080 60.00" 1920x1080)"
check "mode_ok accepts 1080p 59.94"   "0" "$(status mode_ok "1920x1080 59.94" 1920x1080)"
check "mode_ok accepts 4k when asked" "0" "$(status mode_ok "3840x2160 60.00" 3840x2160)"
check "mode_ok rejects 30 fps"        "1" "$(status mode_ok "1920x1080 30.00" 1920x1080)"
check "mode_ok rejects wrong size"    "1" "$(status mode_ok "1920x1080 60.00" 3840x2160)"

formats=$'ioctl: VIDIOC_ENUM_FMT\n\tType: Video Capture\n\n\t[0]: \'YUYV\' (YUYV 4:2:2)\n\t\tSize: Discrete 3840x2160\n\t\t\tInterval: Discrete 0.017s (60.000 fps)\n\t[1]: \'BGR3\' (24-bit BGR 8-8-8)\n\t\tSize: Discrete 3840x2160'
check "format_has_size YUYV 4k"        "0" "$(status format_has_size YUYV 3840x2160 <<<"$formats")"
check "format_has_size BGR3 4k"        "0" "$(status format_has_size BGR3 3840x2160 <<<"$formats")"
check "format_has_size missing format" "1" "$(status format_has_size NV12 3840x2160 <<<"$formats")"
check "format_has_size wrong size"     "1" "$(status format_has_size YUYV 1920x1080 <<<"$formats")"

progress=$'frame=  120 fps= 60 q=-0.0 size=N/A time=00:00:02.00\rframe= 1799 fps= 60 q=-0.0 Lsize=N/A time=00:00:30.00'
check "parse_frame_count takes the last value" "1799" "$(parse_frame_count <<<"$progress")"
check "parse_frame_count fails on no frames"   "1"    "$(status parse_frame_count <<<"error opening input")"
check "frames_ok accepts 59.94 fps"  "0" "$(status frames_ok 1798 30)"
check "frames_ok accepts 60 fps"     "0" "$(status frames_ok 1800 30)"
check "frames_ok rejects 50 fps"     "1" "$(status frames_ok 1500 30)"
check "frames_ok rejects 120 fps"    "1" "$(status frames_ok 3600 30)"

vol=$'[Parsed_volumedetect_0 @ 0x55d0] n_samples: 960000\n[Parsed_volumedetect_0 @ 0x55d0] mean_volume: -23.5 dB\n[Parsed_volumedetect_0 @ 0x55d0] max_volume: -4.1 dB'
check "parse_mean_volume"          "-23.5" "$(parse_mean_volume <<<"$vol")"
check "parse_mean_volume no data"  "1" "$(status parse_mean_volume <<<"nothing")"
check "volume_ok accepts -23.5"    "0" "$(status volume_ok -23.5)"
check "volume_ok rejects silence"  "1" "$(status volume_ok -91.0)"

echo
if (( failures )); then echo "$failures test(s) failed"; exit 1; fi
echo "all tests passed"
