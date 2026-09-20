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
    scripts/unload.sh                    # stop PipeWire, rmmod, restart PipeWire

## Rules

- `driver/` is a submodule of the fork `mkeguy106/sc0710` (remote `upstream` =
  `Nakildias/sc0710`). Driver changes go on topic branches in the fork and are
  offered upstream; the project repo pins the tested commit. Packaging lives in
  `packaging/`, not in the fork, to keep the fork mergeable.
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
- Installing or upgrading the package rebuilds both initramfs images (CachyOS
  limine hook). Expected; only the blacklist file ends up inside them.
- The driver may announce 30 or 119.88 fps after a module load while delivering
  60 (log: "Problem 2"). `verify.sh`'s `signal` check fails on such a load;
  make the source re-lock and rerun before suspecting anything else.
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
