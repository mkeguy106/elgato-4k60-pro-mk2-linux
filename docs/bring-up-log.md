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
