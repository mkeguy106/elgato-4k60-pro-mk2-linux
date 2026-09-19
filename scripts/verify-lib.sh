#!/usr/bin/env bash
# Functions for scripts/verify.sh. Source this file; do not execute it.
# Callers must run with LC_ALL=C: number parsing assumes a dot decimal separator.

SYSFS_ROOT="${SYSFS_ROOT:-/sys}"
SC0710_VENDOR="0x12ab"
SC0710_DEVICE="0x0710"

# Print the PCI address of the first sc0710 card, e.g. 0000:03:00.0.
find_pci_addr() {
    local d
    for d in "${SYSFS_ROOT:-/sys}"/bus/pci/devices/*; do
        [[ -r "$d/vendor" && -r "$d/device" ]] || continue
        if [[ "$(<"$d/vendor")" == "$SC0710_VENDOR" && "$(<"$d/device")" == "$SC0710_DEVICE" ]]; then
            basename "$d"
            return 0
        fi
    done
    return 1
}

# _class_child_of CLASS_GLOB ADDR: print the name of the first class device
# whose parent device is PCI device ADDR. The driver registers both its V4L2
# node and its ALSA card with the PCI device as parent.
_class_child_of() {
    local glob="$1" addr="$2" c
    for c in $glob; do
        [[ -e "$c/device" ]] || continue
        if [[ "$(basename "$(readlink -f "$c/device")")" == "$addr" ]]; then
            basename "$c"
            return 0
        fi
    done
    return 1
}

# Print the V4L2 device node for the card at PCI address $1, e.g. /dev/video2.
find_video_node() {
    local name
    name="$(_class_child_of "${SYSFS_ROOT:-/sys}/class/video4linux/video*" "$1")" || return 1
    echo "/dev/$name"
}

# Print the ALSA card index for the card at PCI address $1, e.g. 3.
find_alsa_card() {
    local name
    name="$(_class_child_of "${SYSFS_ROOT:-/sys}/class/sound/card*" "$1")" || return 1
    echo "${name#card}"
}

# stdin: `v4l2-ctl --query-dv-timings`. Print "WIDTHxHEIGHT FPS".
parse_dv_timings() {
    local text w h fps
    text="$(cat)"
    w="$(grep -oP 'Active width:\s*\K[0-9]+' <<<"$text")" || return 1
    h="$(grep -oP 'Active height:\s*\K[0-9]+' <<<"$text")" || return 1
    fps="$(grep -oP '\(\K[0-9.]+(?= frames per second\))' <<<"$text")" || return 1
    echo "${w}x${h} ${fps}"
}

# $1: "WIDTHxHEIGHT FPS", $2: expected WIDTHxHEIGHT. True if the size matches
# and the rate is 59..60.5 fps (59.94 counts as 60 Hz).
mode_ok() {
    local res="${1% *}" fps="${1#* }"
    [[ "$res" == "$2" ]] || return 1
    awk -v f="$fps" 'BEGIN { exit !(f >= 59 && f <= 60.5) }'
}

# stdin: `v4l2-ctl --list-formats-ext`. True if format FOURCC lists size WxH.
format_has_size() {
    local fourcc="$1" size="$2"
    awk -v f="'$fourcc'" -v s="$size" '
        /^[[:space:]]*\[[0-9]+\]:/ { cur = ($2 == f) }
        cur && /Size:/ && index($0, s) { found = 1 }
        END { exit !found }'
}

# stdin: ffmpeg stderr. Print the last reported frame count.
parse_frame_count() {
    grep -oP 'frame=\s*\K[0-9]+' | tail -n 1 | grep .
}

# True if FRAMES over SECONDS is 59..60.5 fps.
frames_ok() {
    awk -v n="$1" -v s="$2" 'BEGIN { r = n / s; exit !(r >= 59 && r <= 60.5) }'
}

# stdin: ffmpeg volumedetect output. Print the mean volume in dB, e.g. -23.5.
parse_mean_volume() {
    grep -oP 'mean_volume:\s*\K-?[0-9.]+' | tail -n 1 | grep .
}

# True if mean volume $1 (dB) is louder than -60 dB, i.e. not silence.
volume_ok() {
    awk -v v="$1" 'BEGIN { exit !(v > -60) }'
}

# Print the default PipeWire sink and source node names.
audio_defaults() {
    local t
    for t in SINK SOURCE; do
        printf '%s=%s\n' "$t" \
            "$(wpctl inspect "@DEFAULT_AUDIO_${t}@" | grep -oP 'node\.name = "\K[^"]+' | head -n 1)"
    done
}
