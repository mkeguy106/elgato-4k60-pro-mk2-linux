# Bring-up: Elgato 4K60 Pro Mk.2 on this PC

Date: 2026-09-19
Status: design approved, awaiting spec review
Sub-project: 1 of 4

## Scope change (2026-09-19, after Task 4)

The primary source turned out to be a first-generation Nintendo Switch (docked:
at most 1920x1080 at 60 Hz, SDR). Decided by the user on that basis:

- HDR is no longer a goal. Sub-project 2 (10-bit spike) and sub-project 4
  (10-bit in the driver) are dropped. The project is now bring-up, then the
  player. Statements below that call 10-bit a hard requirement are superseded.
- Bring-up is verified at the mode the connected source outputs: 1920x1080 at
  60 Hz for the Switch. Wherever this document says 3840x2160 at 60 Hz, read
  that instead. 4K60 remains a capability the driver claims and this project
  has not verified; it can be checked later with a 4K source without changing
  the design.
- The player (sub-project 3) targets SDR low-latency play-through with audio.
  It must not assume a fixed resolution.
- Player direction chosen by the user (2026-09-19): mpv, not a custom
  application — a launcher script that finds the card by PCI address, an mpv
  profile, and a desktop entry. The user wants audio fed through mpv in one
  combined stream so it stays in sync. Working pipeline, confirmed by the user
  with picture and sound: `ffmpeg -fflags nobuffer -f v4l2 -input_format
  yuyv422 -i <node> -f alsa -ac 2 -ar 48000 -i hw:<card>,0 -map 0:v -map 1:a
  -c:v rawvideo -c:a pcm_s16le -f nut - | mpv - --profile=low-latency
  --cache=no`. Attaching audio with mpv's `--audio-file=av://alsa:...` does
  NOT work (silent; see Problem 3 in `docs/bring-up-log.md`). The launcher also
  has to cope with the contiguous-memory failure recorded there.

## Project context

Goal of the whole project: the Elgato 4K60 Pro Mk.2 PCIe capture card working on
this PC (CachyOS, KDE Plasma Wayland, RTX 3080, dual 4K HDR displays), with a
player window with audio, 4K60, and true 10-bit HDR10 capture. The source is a
game console. The card is used both for low-latency play-through and as a
capture device for OBS/ffmpeg.

The project is split into four sub-projects, each with its own spec and plan:

1. **Bring-up** (this document) — driver fork installed, 4K60 SDR video and
   audio verified.
2. **10-bit spike** — time-boxed investigation into whether and how the card
   delivers 10-bit under Linux. Uses the dual-boot Windows install on this PC to
   compare card register state in SDR and HDR10 modes. Output is an answer.
3. **Player** — window with audio, low latency, HDR output on KDE Wayland.
4. **10-bit in the driver** — implement the spike's findings; offer upstream.

True 10-bit capture is a hard requirement of the project as a whole. It is not
a requirement of bring-up, which is its prerequisite: the spike needs a loaded
driver with register access.

### Facts established on 2026-09-19

- Card: PCI `12ab:0710`, subsystem `1cfa:000e`, at `0000:03:00.0`. No driver
  bound. Link is PCIe Gen2 x4 (the card's maximum) behind chipset port
  `00:1b.4`.
- Kernels installed: `6.18.50-3-cachyos-lts` (running, built with clang 22) and
  `7.2.5-1-cachyos`. Headers for both are installed. `dkms` is not installed.
  Secure Boot is disabled. IOMMU is off.
- Root is btrfs; `snapper`, `snap-pac` and `limine-snapper-sync` are installed.
- `~/sc0710` is a clone of `stoth68000/sc0710`, dead since March 2023; it does
  not build on kernels >= 6.5 (videobuf v1 removed). It is not used.
- `Nakildias/sc0710` (GPL-2.0, last push 2026-09-02) is a maintained rework. Per
  its README and issue tracker — not yet verified here — it supports this card
  without a firmware step, kernels 6.12 through 7.x, DKMS, multiple concurrent
  clients, IRQ-driven zero-copy DMA, YUYV and BGR24 formats, EDID control, and
  HDR as 8-bit BGR24 passthrough or PQ-to-SDR tone mapping. P010/P016 are not
  implemented. 4K60 tearing under load is listed as under investigation.

## Scope

In scope: creating the two GitHub repos, building and installing the driver
fork on this PC, verifying 4K60 SDR video and audio in ffmpeg, mpv and OBS, a
bring-up log, rollback procedures.

Out of scope: the player, HDR, 10-bit, driver source changes beyond what is
needed to build, upstream pull requests, and the fork's `sc0710-cli` script
(not packaged unless a need appears).

## 1. Repositories and layout

- `mkeguy106/sc0710` — GitHub fork of `Nakildias/sc0710`. `main` tracks
  upstream. Our changes live on topic branches.
- `mkeguy106/elgato-4k60-pro-mk2-linux` — public project repo. The local
  directory remains `~/elgato_4k_capture`. License: GPL-2.0-or-later.
- `~/sc0710` stays untouched.

```
driver/      git submodule -> mkeguy106/sc0710, pinned to the tested commit
packaging/   PKGBUILD and pacman install hook for building from driver/
scripts/     verify.sh
docs/        specs, plans, bring-up-log.md; later the 10-bit notes
README.md
CLAUDE.md
LICENSE
```

`packaging/` lives in the project repo, not in the fork, so the fork's diff
against upstream stays empty until real driver work begins.

Commit messages carry no reference to AI or automated generation.

## 2. Build and install

Staged; each stage is reversible before the next begins. Steps that need root
are presented to the user to run or approve.

1. **Install `dkms`** with pacman.
2. **Unprivileged test build.** Run `make` in `driver/` as the normal user
   against the running kernel. Record a SHA-256 of
   `/usr/lib/modules/$(uname -r)/build/Makefile` before and after; they must
   match. (An older version of this driver corrupted that file through `MO=`;
   upstream issue #52. The current Makefile does not use `MO=`.) The driver's
   Makefile detects the clang-built kernel and sets `LLVM=1`.
3. **First load by hand.** With the user's work saved, load the built module
   with `insmod` from `driver/build/` after loading its recorded dependencies.
   Nothing is installed system-wide at this point; a reboot removes it.
   Check `dmesg`, the new `/dev/video*` node and the new ALSA card.
4. **Package.** Only after stage 3 succeeds. `packaging/PKGBUILD` is derived
   from upstream's `aur/PKGBUILD` with these differences:
   - sources come from the local `driver/` checkout at the pinned commit;
   - the install hook does not `modprobe` the module;
   - package name `sc0710-mk2-dkms`, which conflicts with and does not provide
     `sc0710-dkms-git`;
   - it installs only the DKMS source tree, the make wrapper script that
     `dkms.conf` invokes, and the license — not `sc0710-cli` or the firmware
     extraction scripts, which this card does not need;
   - upstream's post-transaction "ensure installed" hook and its helper
     library are not packaged. If stage 6 shows the module as `built` rather
     than `installed`, the hook is added then, after reading the library.
5. **Boot guard.** The package installs
   `/etc/modprobe.d/sc0710-blacklist.conf` containing `blacklist sc0710`, so
   the module loads only on an explicit `modprobe sc0710` rather than by PCI ID
   at every boot. The file is removed by a follow-up change once the soak test
   passes. Emergency escape, documented in the README: add
   `module_blacklist=sc0710` to the kernel command line from the Limine menu.
6. **DKMS for both kernels.** `dkms status` must show the module installed for
   `6.18.50-3-cachyos-lts` and `7.2.5-1-cachyos`. Runtime testing happens on
   the booted 6.18 kernel. 7.2.5 is compile-verified only and recorded as such
   in the bring-up log until the user next boots it.

## 3. Verification

Prerequisites: console connected to the card's HDMI input, HDCP disabled on the
console, output set to SDR at 3840x2160 60 Hz.

`scripts/verify.sh` runs the automatable checks and prints pass/fail per check;
the interactive ones are performed by hand and recorded in
`docs/bring-up-log.md`.

| Check | Pass condition |
|---|---|
| Signal detection | `v4l2-ctl --query-dv-timings` reports 3840x2160 at 60 Hz |
| Formats | `v4l2-ctl --list-formats-ext` lists YUYV and BGR24 at 3840x2160 |
| Video capture | 30 s ffmpeg V4L2 capture to the null muxer reports 59-60 fps; no sc0710 errors in `dmesg` during the run |
| Picture | one captured frame saved as PNG shows the console's actual picture, correctly aligned, correct colours |
| Audio device | an ALSA capture card for the driver exists |
| Audio capture | 10 s, 48 kHz stereo recording; ffmpeg `volumedetect` mean volume above -60 dB while the console plays sound |
| Live view | mpv shows live video with audio using its low-latency profile; this is the interim player |
| OBS | V4L2 video source plus audio input run for 10 minutes without a stall or crash |
| Multi-client | OBS and mpv capture at the same time |
| Soak | 30 minutes at 4K60; count of visible tears/frame shifts and any `dmesg` errors recorded |
| Audio defaults | default PipeWire sink and source unchanged after the module loads |

Tearing at 4K60 is a known upstream problem. Observing it is a finding to
record, not a bring-up failure. Bring-up fails if the module will not build or
load, if no correct picture or no audio can be captured at all, or if the
machine locks up or panics.

If the default audio device changes (upstream issue #86), add a WirePlumber
rule lowering the card's priority. Not added otherwise.

## 4. Rollback

- **Unload.** `rmmod sc0710` refuses while PipeWire holds the video node. The
  documented procedure stops the user's PipeWire and WirePlumber services,
  unloads, and restarts them. `rmmod -f` is never used: force-unloading with an
  open capture descriptor is a use-after-free.
- **Uninstall.** `pacman -R sc0710-mk2-dkms` removes the DKMS module for every
  kernel and the blacklist file.
- **Snapshots.** `snap-pac` is installed; the plan verifies that a root snapper
  config is active so the install transaction gets pre/post snapshots bootable
  from Limine.
- **Unbootable.** `module_blacklist=sc0710` on the kernel command line.

## 5. Closing out bring-up

- `docs/bring-up-log.md` records the pinned driver commit, kernel versions, each
  check's result, and observed problems.
- Project `CLAUDE.md` and `README.md` describe build, load, unload, verify and
  rollback.
- The `sc0710` entry in `~/CLAUDE.md` and the Obsidian project note and
  `GitHub Projects.md` index are updated to point at this project.
