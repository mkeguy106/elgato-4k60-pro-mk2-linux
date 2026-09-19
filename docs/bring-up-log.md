# Bring-up log

Card: Elgato 4K60 Pro Mk.2, PCI `12ab:0710` / `1cfa:000e` at `0000:03:00.0`, PCIe Gen2 x4.
Driver: `mkeguy106/sc0710` at `ea0a71215e24a33aa8b26b5cc66e3592c9dfdfe1` (version `2026.09.02-1`).

## Build (unprivileged, 2026-09-19)

| Kernel | Compiler | Result | Headers Makefile checksum unchanged |
|---|---|---|---|
| 6.18.50-3-cachyos-lts | clang/LLVM (auto-detected by the driver Makefile) | built, 0 errors | yes |
| 7.2.5-1-cachyos | clang/LLVM (auto-detected by the driver Makefile) | built, 0 errors | yes |

Module dependencies reported by modinfo:
`videobuf2-common,videodev,videobuf2-v4l2,videobuf2-vmalloc,videobuf2-dma-sg,snd,snd-pcm`

Warnings worth noting: no compiler warnings on either kernel. The only warning
line is from make itself (`-j1 forced in submake: resetting jobserver mode`),
which is the driver Makefile deliberately building single-threaded.

The submodule working tree was clean after both builds (`build/` is ignored by
the fork; `lib/sc0710-version.h` was not modified).

## First load by hand (2026-09-19, kernel 6.18.50-3-cachyos-lts)

- Loaded with `insmod` from `driver/build/`; nothing installed system-wide.
- Board name reported by the driver: `Elgato 4K60 Pro MK.2 [card=1,autodetected]`,
  subsystem `1cfa:000e`, interrupt-driven DMA service over MSI.
- V4L2 node: `/dev/video2` — ALSA card index: 5 (`sc0710 - Elgato 4K60 Pro MK.2`).
- Source connected: first-generation Nintendo Switch, docked. It outputs at most
  1920x1080 at 60 Hz, SDR. It cannot exercise 4K60 or HDR.
- Detected timings: the driver logged `Detected timing 2200x1125 -> format:
  1920x1080p30` preceded by `No FPS Hint -> Pick 1920x1080p30`. 2200x1125 is the
  correct total for 1080p, so the resolution is right, but the Switch outputs
  60 Hz and the driver fell back to p30 for lack of a rate hint.
  `v4l2-ctl --query-dv-timings` returned `No data available` (ENODATA) with no
  streaming client open. Both to be looked at in Task 5.
- Kernel log warnings or errors: none from the driver. The kernel logged
  `module verification failed: signature and/or required key missing - tainting
  kernel`, expected for an unsigned out-of-tree module with Secure Boot off.
  No BUG/Oops/call trace.
- Default audio sink/source changed by loading the module: no.
- `scripts/unload.sh`: worked. PipeWire needs a moment after the restart before
  `wpctl` reports default nodes again (an immediate query returns empty names).
- Bug found and fixed while testing: `lsmod | grep -q` under `set -o pipefail`
  reports "not loaded" for a loaded module (grep exits at first match, lsmod
  dies of SIGPIPE, pipefail makes the pipeline fail). `unload.sh` and the
  planned `verify.sh` now read `/proc/modules` instead.
- Module left unloaded at the end of this task.
