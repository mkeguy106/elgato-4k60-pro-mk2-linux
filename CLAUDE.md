# CLAUDE.md

Elgato 4K60 Pro Mk.2 (PCI `12ab:0710` / `1cfa:000e`, at `0000:03:00.0`) on this PC.
Two sub-projects: bring-up (done 2026-09-19) and the player (mpv-based;
`scripts/play.sh` works, polish pending). The source is a first-generation
Nintendo Switch: 1080p60 SDR. HDR and 10-bit were dropped from scope; 4K60 is
an unverified driver capability.
Specs and plans: `docs/superpowers/`. Results so far: `docs/bring-up-log.md`.

## Commands

    bash tests/test-verify-lib.sh        # unit tests for scripts/verify-lib.sh
    make -C driver                       # unprivileged module build -> driver/build/sc0710.ko
    cd packaging && makepkg -f           # build the DKMS pacman package
    sudo modprobe sc0710                 # load the installed module
    scripts/verify.sh [WIDTHxHEIGHT]     # automated checks (default 1920x1080); needs a live source with sound
    scripts/play.sh                      # live view: mpv video + PipeWire audio loopback
    scripts/install-desktop-entry.sh     # app menu entry for play.sh (generated: holds this clone's path)
    bash tests/test-install-desktop-entry.sh
    scripts/audio-clock-check.sh [SECS]  # real rate of the card's audio stream; needs a capturing program
    scripts/unload.sh                    # stop PipeWire, rmmod, restart PipeWire

## Rules

- `driver/` is a submodule of the fork `mkeguy106/sc0710` (remote `upstream` =
  `Nakildias/sc0710`). Driver changes go on topic branches in the fork and are
  offered upstream; the project repo pins the tested commit. Packaging lives in
  `packaging/`, not in the fork, to keep the fork mergeable.
- The pin is the fork branch `integration` (`7ee2d48`): upstream `ea0a712`
  plus two patches, each also on its own branch off upstream for the upstream
  PRs: `silence-clock-pacing` (`e0ab897`, Nakildias/sc0710#89; paces no-signal
  silence by `ktime`, the stock code ran the 48 kHz stream at ~42.4 kHz) and
  `rate-hint-plausibility` (`deac8a3`, Nakildias/sc0710#90; see the next rule). When moving the pin
  to a newer upstream, rebuild `integration` from upstream plus whichever of
  the two is not merged yet, then check `scripts/audio-clock-check.sh` with
  the source off and the kernel log line at the next HDMI lock. The user
  wants AI involvement disclosed in upstream PRs, while commit messages stay
  free of it.
- Frame rate label ("Problem 2"): MCU status byte 0x0c is not a usable rate
  for the Switch on this card (52, 98 or 0 for one 1080p60 signal, latched at
  lock, never refreshed; no other MCU register carries the rate). The patch
  believes it only within 2 Hz of a mode with the detected totals and
  otherwise picks the mode nearest 60 Hz, logging `FPS hint N fits no ...` or
  `No FPS Hint -> Pick ...`. `echo 1 > /sys/module/sc0710/parameters/mcu_scan`
  (root) dumps the MCU registers to the kernel log, read-only, no reload;
  `sc0710_debug_mode` is runtime-writable but prints ~10 lines/s without a
  signal and gates per-frame prints: player closed, short windows only.
- The card must stay PipeWire's graph clock (capture nodes get
  `priority.driver` 2000, outputs ~1000). A WirePlumber rule that lowers it was
  tried on 2026-09-20 and reverted: with a signal the card delivers 1024-frame
  bursts on the video interrupt, and as a follower its audio is resynced
  constantly. `priority.driver` cannot be changed at runtime with `pw-cli`.
  Evidence for audio clock trouble: `journalctl --user -u pipewire | grep
  spa.alsa` ("follower ... resync") and `pw-top -b -n 2`.
- `scripts/unload.sh` restarts PipeWire, which cuts every program's sound; some
  (Jellyfin desktop) do not reconnect. Warn the user before running it. An
  upgraded package does not need an unload: the running module keeps working
  and the new file is used from the next load.
- Never run the fork's `scripts/install-sc0710.sh` or `scripts/sc0710-cli.sh`.
- Never `rmmod -f`. Use `scripts/unload.sh`, after closing the player and any
  capture program.
- The module is blacklisted from autoloading (`/etc/modprobe.d/sc0710-blacklist.conf`,
  owned by the package). Load it with `modprobe sc0710`.
- The kernel command line carries `cma=256M@0-4G` (`/etc/kernel/cmdline`,
  Limine). The driver needs contiguous DMA buffers below 4 GB; a plain
  `cma=256M` lands above 4 GB on this 32 GB machine and does nothing. If
  capture fails with ENOMEM at STREAMON, check `grep -i cma /proc/meminfo`.
- Never probe `limine-update` with `--help`: it ignores arguments, elevates
  itself through sudo and rebuilds the boot entries and both initramfs images.
- Kernel updates: the stock dkms pacman hooks rebuild the module when a headers
  package is upgraded (both headers packages are explicitly installed).
  `kernel-modules-hook` is not installed, so after a kernel upgrade an unloaded
  module cannot be loaded until reboot; `module_problem` in `verify-lib.sh`
  tells `play.sh` which case it is. A failed build on a new kernel series is
  fixed by moving the `driver/` pin, never by editing `/usr/src`.
- Installing or upgrading the package rebuilds both initramfs images (CachyOS
  limine hook). Expected; only the blacklist file ends up inside them.
- Audio only flows while video is streaming unless the module is loaded with
  `keep_audio_alive=1`. Capture both in one process when testing audio.
- ALSA `hw:` access is exclusive, and the PipeWire source
  (`alsa_input.pci-0000_03_00.0.stereo-fallback`) exists only while nothing
  holds the ALSA device. When two programs need audio, use the PipeWire source.
- mpv cannot play the card's audio itself (`--audio-file=av://alsa:` is
  silent); one muxed ffmpeg stream into mpv works but adds about 1.5 s. That is
  why `play.sh` keeps video and audio on separate paths.
- `play.sh` is a long-running bash script: never edit it in place while the
  player is open (bash reads scripts incrementally). Write a copy and `mv` it
  over. It loads the module itself (`sudo -n`, then `pkexec`), holds a lock in
  `$XDG_RUNTIME_DIR`, and sets the mpv app id `elgato-4k60-play`, which must
  stay equal to the desktop entry's file name.
- Scripts that parse numbers must set `LC_ALL=C` (system locale uses a comma
  decimal separator).
- `pgrep -f PATTERN` from a tool shell matches the shell's own command line.
  Write the pattern as `'[m]pv av://v4l2'`, or the player looks open when it
  is not (this produced a wrong log entry on 2026-09-21).
- Under `set -o pipefail`, test for the module with `/proc/modules`, not
  `lsmod | grep -q`.
- Kernel log is readable without root: `journalctl -k | grep -i sc0710`.
- An old version of this driver corrupted the kernel headers' top-level
  `Makefile`. After changing anything about how the module is built, compare
  `sha256sum /usr/lib/modules/*/build/Makefile` before and after.
- 7.2.5-1-cachyos is compile-verified only until someone boots it and runs
  `scripts/verify.sh`; update `docs/bring-up-log.md` when that happens.
- `~/sc0710` is an unrelated clone of the dead original driver. Leave it alone.
- Root commands run one per call, never chained, each described in plain words.
