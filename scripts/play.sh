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
# App menu entry: scripts/install-desktop-entry.sh
set -uo pipefail
export LC_ALL=C

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=verify-lib.sh
source "$here/verify-lib.sh"

# Started from the app menu there is no terminal, so messages also go to a
# desktop notification.
notify() {
    [[ -t 2 ]] && return 0
    command -v notify-send >/dev/null || return 0
    notify-send -a "Elgato 4K60 Pro Mk.2" -i camera-video "Elgato 4K60 Pro Mk.2" "$1" || true
}
warn() { echo "play.sh: $*" >&2; notify "$*"; }
die() { warn "$@"; exit 1; }

# wait_for SECONDS COMMAND...: retry the command until it succeeds.
wait_for() {
    local tries=$(( $1 * 5 )); shift
    for (( ; tries > 0; tries-- )); do
        "$@" && return 0
        sleep 0.2
    done
    return 1
}

# A second instance would play the sound twice.
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/elgato-4k60-play.lock"
flock -n 9 || die "the player is already running"

# The package keeps the module from loading at boot, so load it on demand:
# without a prompt where sudo allows that, otherwise through the desktop's
# authorization dialog. Only modprobe runs as root.
load_module() {
    sudo -n modprobe sc0710 2>/dev/null && return 0
    command -v pkexec >/dev/null && pkexec modprobe sc0710
}
module_loaded() { grep -q '^sc0710 ' /proc/modules; }

fresh_load=0
if ! module_loaded; then
    # Diagnose before asking for authorization that cannot help.
    case "$(module_problem "$(uname -r)")" in
        reboot)
            die "the kernel was updated since the last boot. Reboot to finish the update, then start the player again." ;;
        not-built)
            die "the driver is not built for kernel $(uname -r). Check 'dkms status sc0710'; see README.md, \"Kernel updates\"." ;;
    esac
    load_module && module_loaded \
        || die "could not load the sc0710 module (try in a terminal: sudo modprobe sc0710)"
    fresh_load=1
fi

addr="$(find_pci_addr)" || die "no Elgato 4K60 Pro Mk.2 found on the PCI bus"
have_node() { node="$(find_video_node "$addr")"; }
wait_for 5 have_node || die "the card has no V4L2 node"
pw="$(pipewire_name_for "$addr")"

find_source() { pactl list short sources | cut -f2 | grep -F "alsa_input.$pw." | head -n 1; }
have_source() { src="$(find_source)"; [[ -n "$src" ]]; }

# Right after a module load PipeWire needs a moment to pick the card up.
src=""
(( fresh_load )) && wait_for 5 have_source
if ! have_source; then
    # PipeWire can list the card's input profile as active without creating the
    # node (seen when another program held the device at probe time).
    pactl set-card-profile "alsa_card.$pw" off
    pactl set-card-profile "alsa_card.$pw" input:stereo-fallback
    wait_for 4 have_source
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
    ( sleep 1; exec pw-loopback -C "$src" -l "${AUDIO_LATENCY_MS:-20}" -n elgato-capture-audio ) 9>&- &
    audio_pid=$!
else
    warn "PipeWire has no audio source for the card; continuing without sound"
fi

# The app id ties the window to the menu entry (icon, task manager grouping).
mpv "av://v4l2:$node" --demuxer-lavf-o=input_format=yuyv422 \
    --profile=low-latency --untimed --no-audio \
    --script="$here/mpv-game-volume.lua" \
    --title="Elgato 4K60 Pro Mk.2" \
    --wayland-app-id=elgato-4k60-play --x11-name=elgato-4k60-play \
    --log-file="$log" "$@"

if grep -q 'Cannot allocate memory' "$log"; then
    notify "The driver could not get contiguous memory. Run scripts/play.sh in a terminal for what to do."
    cat >&2 <<'MSG'
play.sh: the driver could not get contiguous memory for its DMA buffers.
It needs four 4 MB physically contiguous blocks below 4 GB, and after long
uptime there may be none. Free some and try again:
    sudo sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches'
    sudo sh -c 'echo 1 > /proc/sys/vm/compact_memory'
The durable fix is cma=256M@0-4G on the kernel command line (plain cma=256M
lands above 4 GB and does not help). See README.md, "Before you start".
MSG
    exit 1
fi
