#!/usr/bin/env bash
# Adds an application menu entry that starts scripts/play.sh, or removes it.
# The entry holds this clone's absolute path, so it is generated here instead
# of being shipped as a file. Only touches the user's own applications folder.
#
# Usage: scripts/install-desktop-entry.sh [--remove]
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
apps="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
# The file name doubles as the window's app id (see --wayland-app-id in
# play.sh), which is how the desktop matches the mpv window to this entry.
entry="$apps/elgato-4k60-play.desktop"

case "${1:-}" in
    --remove)
        rm -f "$entry"
        echo "removed $entry"
        ;;
    "")
        # Desktop entry quoting: inside double quotes \ " ` $ take a backslash,
        # and a literal % is written %%.
        exec_path="$here/play.sh"
        exec_path="${exec_path//\\/\\\\}"
        exec_path="${exec_path//\"/\\\"}"
        exec_path="${exec_path//\`/\\\`}"
        exec_path="${exec_path//\$/\\\$}"
        exec_path="${exec_path//%/%%}"

        mkdir -p "$apps"
        cat > "$entry" <<EOF
[Desktop Entry]
Type=Application
Name=Elgato 4K60 Pro Mk.2
GenericName=Capture Card Live View
Comment=Low-latency live view of the capture card, with sound
Exec="$exec_path"
Icon=camera-video
Terminal=false
Categories=AudioVideo;Video;Player;
Keywords=capture;hdmi;console;switch;
StartupWMClass=elgato-4k60-play
EOF
        echo "installed $entry"
        ;;
    *)
        echo "usage: ${0##*/} [--remove]" >&2
        exit 2
        ;;
esac

if command -v update-desktop-database >/dev/null; then
    update-desktop-database "$apps" 2>/dev/null || true
fi
