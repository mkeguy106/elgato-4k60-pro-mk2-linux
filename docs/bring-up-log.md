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

## Automated verification, module loaded by hand (2026-09-19, Switch at 1080p60)

Final run of `scripts/verify.sh` (expected size 1920x1080):

    module         PASS  sc0710 is loaded
    devices        PASS  pci=0000:03:00.0 video=/dev/video2 alsa=hw:5,0
    signal         FAIL  1920x1080 119.88 (want 1920x1080 at 60)
    format-YUYV    PASS  1920x1080 listed
    format-BGR3    PASS  1920x1080 listed
    capture        PASS  1800 frames in 30s
    kernel-log     PASS  no sc0710 errors during capture
    audio          FAIL  mean volume -91.0 dB
    picture        LOOK
    audio-default  PASS  default sink and source unchanged

Captured frame: the Switch's "Ready to start system update" dialog, sharp,
correctly aligned, correct colours. The dialog is silent, so the audio result
says nothing about the audio path yet; to be re-run with sound playing.

### Problem 1: capture cannot start on a fragmented system (root cause found)

First runs with a live signal delivered 0 frames: `VIDIOC_STREAMON` returned
ENOMEM and the kernel logged `page allocation failure: order:10,
mode:0xcc4(GFP_KERNEL|GFP_DMA32)` from `sc0710_dma_chain_alloc`.

- The driver sets a 32-bit DMA mask and calls `dma_alloc_coherent` once per
  chain, 4 chains per channel, at stream start. A 1080p YUYV frame (4147200
  bytes) needs an order-10 (4 MB) physically contiguous block below 4 GB, so at
  least four of them. At 3840x2160 each chain would need about 16 MB, beyond
  what the page allocator can give at all.
- After 4 days of uptime the DMA32 zone had 530 MB free but zero 4 MB blocks.
- `echo 1 > /proc/sys/vm/compact_memory` alone yielded one block (not enough).
  `sync; echo 3 > /proc/sys/vm/drop_caches` followed by compaction yielded 151,
  and capture then worked.
- With no signal the driver serves its placeholder without starting DMA, which
  is why the no-signal run "worked" at about 4 fps.
- Durable fixes available on this kernel (`CONFIG_CMA=y`, `CONFIG_DMA_CMA=y`,
  `CONFIG_CMA_SIZE_MBYTES=0`): reserve a pool with `cma=256M` on the kernel
  command line (reboot needed), or enable VT-d in the BIOS plus `intel_iommu=on`
  so DMA buffers need not be physically contiguous (no DMAR lines in the boot
  log, so VT-d is currently off). Not yet decided.

### Problem 2: driver reports double the real frame rate

The driver reports 1920x1080 at 119.88 fps (pixel clock 296.7 MHz) for a
first-generation Switch, which outputs 60 Hz; on the first load it guessed p30
(`No FPS Hint`). Delivery is a true 60 fps (1800 frames in 30 s of capture
timestamps), so this is a labelling error, but players and OBS will be told
119.88. Related upstream knobs: `hdmi_rate_decode`, `procedural_timings`.
Not yet investigated.

## Automated verification, second pass (2026-09-19, Switch on the Mario Kart 8 title screen)

Run while the user's mpv was also streaming video from the card (multi-client).

    module         PASS  sc0710 is loaded
    devices        PASS  pci=0000:03:00.0 video=/dev/video2 alsa=hw:5,0
    signal         PASS  1920x1080 60.00
    format-YUYV    PASS  1920x1080 listed
    format-BGR3    PASS  1920x1080 listed
    capture        PASS  1800 frames in 30s
    kernel-log     PASS  no sc0710 errors during capture
    audio          PASS  mean volume -30.3 dB
    picture        LOOK  inspect out/frame-1080.png: correct image, aligned, right colours
    audio-default  PASS  default sink and source unchanged
    
    all automated checks passed

Findings since the first pass:

- **Audio path works.** A direct 10 s ALSA capture measured mean -31.0 dB, max
  -12.8 dB (48 kHz stereo). The earlier -91 dB was the Switch's silent
  system-update dialog.
- **Signal loss and recovery works.** The Switch restarted for a system update
  while mpv was streaming; the driver logged `Signal restoration - DMA was
  running, have streaming clients` and `DMA restarted after signal
  restoration`, and the picture came back in the same mpv window.
- **Frame rate is detected correctly after a re-lock.** After the Switch
  restarted the driver logged `1920x1080p60`. The wrong values (p30, then
  119.88) came from the first detections after module load. Problem 2 above is
  therefore intermittent, not constant.
- **mpv live view renders on the desktop** (confirmed by the user) with
  `mpv av://v4l2:/dev/video2 --demuxer-lavf-o=input_format=yuyv422
  --profile=low-latency --untimed --audio-file=av://alsa:hw:5,0`.

### Problem 3: mpv loses audio across a signal loss

After the Switch restarted, mpv kept showing video but the card's ALSA capture
device was closed (`/proc/asound/card5/pcm0c/sub0/status`: closed; `fuser`
showed mpv holding only `/dev/video2`). mpv does not reopen an external
`--audio-file` input after it errors. A fresh mpv decodes real audio (mean
-30.6 dB via `--ao=pcm`), but in that headless test only 1.4 s of audio was
written for 8 s of video, so `--untimed` with a separately opened audio input
may also starve audio. To be settled in the player design: candidates are
playing audio outside mpv through a PipeWire loopback, or feeding mpv one muxed
stream. No PipeWire source for the card appeared in `pactl list short sources`.

### Problem 3, resolved: use one combined stream into mpv

- A fresh mpv with `--audio-file=av://alsa:hw:5,0` was also silent. While it
  ran, the card's capture PCM was held by mpv in state `XRUN`: mpv had opened
  the device but was not reading it. Likely cause, not confirmed: the V4L2
  timestamps are boot-relative (about 365000 s) and the ALSA timestamps are
  wall-clock (about 1.79e9 s), and mpv does not rebase an external track
  separately, so the audio looks decades ahead of the video.
- Working, confirmed by the user with picture and sound (Mario Kart 8 title
  music): let ffmpeg read both devices, rebase them to a common zero, and pipe
  one uncompressed NUT stream into mpv:

      ffmpeg -hide_banner -loglevel error -fflags nobuffer -thread_queue_size 1024 \
        -f v4l2 -input_format yuyv422 -i /dev/video2 \
        -thread_queue_size 1024 -f alsa -ac 2 -ar 48000 -i hw:5,0 \
        -map 0:v -map 1:a -c:v rawvideo -c:a pcm_s16le -f nut - \
        | mpv - --profile=low-latency --cache=no

  `--untimed` is deliberately absent so mpv keeps audio and video in sync.
  Still to be judged by the user: sync accuracy, stutter (about 250 MB/s
  through the pipe; `--stream-buffer-size=4MiB` on the mpv side if needed),
  and input delay. This is the basis for the player.

### Player: split design replaces the combined stream (2026-09-19)

- The combined ffmpeg-to-mpv stream had sound but about 1.5 s of delay (user:
  "from the time I hit the gas to the car moving"), with or without
  `--untimed` and small queues. Likely cause, not verified: ffmpeg rebases each
  input to its own start, the audio device opens about a second after the
  video, and the muxer outputs in timestamp order, so every video frame waits
  for audio that does not exist yet.
- Video-only `mpv av://v4l2:<node> --profile=low-latency --untimed` is
  responsive (user: "so much better").
- PipeWire offers the card as `alsa_input.pci-0000_03_00.0.stereo-fallback`
  once no other program holds the ALSA device. The profile showed as active
  without a source node until it was toggled off and on. A 10 s `pw-record`
  from that source measured mean -24.7 dB, max -7.8 dB, no driver complaints,
  default sink/source unchanged.
- `scripts/play.sh` = mpv video (unbuffered) + `pw-loopback` audio (20 ms
  default), finds devices by PCI address, re-creates the PipeWire source if it
  is missing, explains the contiguous-memory failure. Audible result and
  audio/video sync still to be confirmed by the user.
- User result with `scripts/play.sh`: sound present and in sync, playable
  (finished a Mario Kart 8 race in third place). mpv's own volume keys had no
  effect because the audio bypasses mpv; `scripts/mpv-game-volume.lua` now
  rebinds 9/0, / and *, the mouse wheel and m to adjust the PipeWire stream
  `output.elgato-capture-audio` with an on-screen level. Tested through mpv's
  IPC against the live stream: 100% -> 105% -> 95% -> muted -> 100%.
- User confirmed the in-mpv volume keys work during play.

## Packaged install (2026-09-19)

- Package: `sc0710-mk2-dkms 2026.09.02.1.r223.ea0a712-1`, built with
  `makepkg -fd` (`-d` because `dkms`, a runtime dependency, was not installed
  yet at build time). Contents inspected before install: only
  `/usr/src/sc0710-<ver>/`, `/usr/lib/sc0710/sc0710-dkms-make.sh`, the licence
  and `/etc/modprobe.d/sc0710-blacklist.conf`; the install script only prints.
- `dkms` 3.4.3-1 installed from the distro repos first.
- `dkms status sc0710`:

      sc0710/2026.09.02.1.r223.ea0a712, 6.18.50-3-cachyos-lts, x86_64: installed
      sc0710/2026.09.02.1.r223.ea0a712, 7.2.5-1-cachyos, x86_64: installed

  Both were installed by the stock `70-dkms-install.hook`; the fork's
  `sc0710-dkms-ensure` hook was not needed.
- Kernel headers Makefile checksums unchanged after DKMS builds: yes
- snapper pre/post snapshot numbers: 5195 / 5196 (`dkms`), 5197 / 5198
  (`sc0710-mk2-dkms`). Last snapshot before any change: 5194.
- Side effect not foreseen in the plan: the transaction triggered CachyOS's
  limine-mkinitcpio hook, which regenerated the initramfs for both kernels and
  updated `/boot/limine.conf`. `lsinitcpio` on both images shows only
  `etc/modprobe.d/sc0710-blacklist.conf`; the module itself is not in either
  initramfs.
- Boot guard present (`blacklist sc0710`): yes
- Module file loaded by `modprobe`:
  `/lib/modules/6.18.50-3-cachyos-lts/updates/dkms/sc0710.ko.zst`
- First detection after this load was correct (`1920x1080p60`), unlike the
  first hand load (Problem 2 stays intermittent). No kernel warnings or errors.
- Default audio sink and source unchanged by the load; no WirePlumber priority
  rule added.
- 7.2.5-1-cachyos: compiled and installed by DKMS; NOT runtime-tested.
- `scripts/verify.sh` against the installed module:

      module         PASS  sc0710 is loaded
      devices        PASS  pci=0000:03:00.0 video=/dev/video2 alsa=hw:5,0
      signal         PASS  1920x1080 60.00
      format-YUYV    PASS  1920x1080 listed
      format-BGR3    PASS  1920x1080 listed
      capture        PASS  1800 frames in 30s
      kernel-log     PASS  no sc0710 errors during capture
      audio          PASS  mean volume -34.6 dB
      picture        LOOK  inspect out/frame-1080.png: correct image, aligned, right colours
      audio-default  PASS  default sink and source unchanged

      all automated checks passed

  Captured frame: Mario Kart 8 results table, sharp, aligned, correct colours.
  The whole frame is dim, most likely the Switch's idle screen dimming (the
  controller had been idle for several minutes); not confirmed.
- Problem 1 decision (user, 2026-09-19): reserve contiguous memory with
  `cma=256M` on the kernel command line. Not applied yet.

### Problem 1 fix: the pool has to be placed below 4 GB

Plain `cma=256M` would not help on this machine. Kernel 6.18 `mm/cma.c` places
the pool bottom-up starting at 4 GB whenever the limit allows it ("Avoid using
first 4GB to not interfere with constrained zones like DMA/DMA32"), x86 passes
all of RAM as the limit, and this PC has 32 GB. The driver sets a 32-bit DMA
mask, so a pool above 4 GB is rejected and `dma_alloc_coherent` falls back to
the fragmented DMA32 zone as before. The parameter to use is `cma=256M@0-4G`.
Established from the v6.18 source; to be confirmed after a reboot with
`grep -i cma /proc/meminfo` and the `cma: Reserved` line in the kernel log.

The command line lives in `/etc/kernel/cmdline`; `limine-update` regenerates
the boot entries and both initramfs images from it.

### Mistake: `limine-update --help` runs the update

While looking up how to regenerate the boot entries, `limine-update --help` was
run as a normal user, expecting usage text. The script ignores its arguments
and re-executes itself through sudo, so it ran as root for about 3 s
(17:59:43-17:59:46) and was killed by the closed output pipe while building the
LTS initramfs in its temp directory. Checked afterwards: all 10 `path#hash`
entries in `/boot/limine.conf` match the files on disk, both initramfs images
still carry the 17:57 timestamp of the package install, the Limine EFI binary
is unchanged, no temp directory was left behind. Nothing to repair. Lesson:
read a root-capable tool's script or man page instead of probing it with
`--help`.

### Problem 1 fix applied, reboot pending (2026-09-19)

- Appended `cma=256M@0-4G` to `/etc/kernel/cmdline` (backup:
  `/etc/kernel/cmdline.bak-2026-09-19`), then ran `sudo limine-update` to
  completion (exit 0).
- `/boot/limine.conf`: both live entries (6.18 LTS and 7.2) carry the new
  parameter; the snapshot entries keep the previous command line, so booting a
  snapshot entry is a way back, as is editing the entry in the Limine menu.
  All 10 `path#hash` entries verify against the files on disk.
- Not yet in effect: `CmaTotal` is still 0 until the next reboot. To check
  after rebooting: `grep -i cma /proc/meminfo` (expect `CmaTotal: 262144 kB`)
  and `journalctl -k -b | grep 'cma: Reserved'` (expect a base address below
  `0x100000000`). After a reboot the module has to be loaded by hand
  (`sudo modprobe sc0710`) because of the boot guard.

### Problem 1 fix confirmed after reboot (2026-09-19, 18:04 boot)

- `cma: Reserved 256 MiB at 0x0000000044600000` (about 1.1 GB, below 4 GB);
  `CmaTotal: 262144 kB`.
- `CmaFree` was 250444 kB with the module loaded and idle, 235164 kB with
  `scripts/play.sh` streaming: about 15 MB less, matching the driver's four
  ~4 MB DMA chains. The capture buffers come from the reserved pool, so
  STREAMON no longer depends on finding free 4 MB blocks in a fragmented
  DMA32 zone. (At 2 minutes of uptime fragmentation would not have shown
  either way; the CmaFree drop is the evidence.)
- Boot guard worked: module absent after boot, loaded with
  `sudo modprobe sc0710` from the DKMS path.
- Problem 2 seen again on this load: `No FPS Hint -> Pick 1920x1080p30`, and
  mpv labels the stream 30 fps. With `--untimed` this does not affect
  `play.sh`; frames are shown as they arrive.

## Interactive verification on the installed module (2026-09-19, after the reboot)

### 30-minute soak at 1080p60 (18:07:58-18:37:58)

- `ffmpeg -f v4l2 -input_format yuyv422 -i /dev/video2 -map 0:v -t 1800 -f null -`
  counted **107998 frames in 1800 s** (59.999 fps; `frames_ok`: rate OK),
  speed 1x throughout.
- `scripts/play.sh` (mpv + PipeWire loopback) streamed from the card for the
  whole period, so this was also 30 minutes of two simultaneous video clients.
- Kernel log: no sc0710 lines at all during the soak (0 matching
  error/fail/timeout/tear/short/resync/overrun). `CmaFree` identical before
  and after (235164 kB): the second client shares the driver's DMA buffers
  and nothing leaked.
- ffmpeg printed 53323 `non monotonically increasing dts` warnings. Cause is
  Problem 2: this module load labelled the signal p30, so ffmpeg used a 1/30
  time base while frames arrived at 60 per second and every second frame
  collided with its predecessor's timestamp. No frames were dropped; a
  recorder that trusts the advertised rate would be affected, `play.sh`
  (`--untimed`) is not.
- Tears, frame shifts or audio dropouts seen by the user: none reported
  ("seemed fine to me").

### OBS, and OBS together with mpv (18:48-19:03)

OBS 32.2.2 with a "Video Capture Device (V4L2)" source on `/dev/video2`
(YUYV 4:2:2, 1920x1080) and an "Audio Input Capture (PulseAudio)" source on
`alsa_input.pci-0000_03_00.0.stereo-fallback`, running for 15 minutes while
`scripts/play.sh` (mpv + loopback) kept streaming from the same card.

- No stall, crash or machine hang (upstream issues #79 and #48 did not
  reproduce at 1080p60). Both programs held `/dev/video2` throughout; the
  PipeWire source served the loopback and OBS at the same time.
- OBS Stats after about 14 minutes: FPS 60.00, average render time 0.7 ms,
  frames missed due to rendering lag 4 / 51161 (0.0%), CPU 0.6%, memory
  607.5 MB. Nothing was recorded or streamed, so encoder skips do not apply.
- Kernel log from OBS start to the end of the check: no sc0710 lines, no
  kernel warnings of any kind. `CmaFree` unchanged at 235164 kB.
- OBS opened the device as `Framerate: 30.00 fps` (Problem 2: this module
  load labelled the signal p30). OBS's 60.00 is its own render rate, so it
  does not show how many distinct capture frames per second reached the
  preview. Smoothness of the OBS preview and the Elgato audio meter were not
  reported by the user; OBS's log shows audio packets arriving from the card.

### Summary

| Check | Result | Notes |
|---|---|---|
| mpv live view with audio | pass | `scripts/play.sh` on the DKMS module after the reboot; user: "seemed fine to me". Stream labelled 30 fps by the driver, shown untimed at the real 60. |
| OBS 15 minutes | pass | 4 / 51161 frames missed (0.0%), no kernel lines |
| OBS + mpv together | pass | both live for the whole OBS run |
| 30-minute 1080p60 soak | 107998 frames, rate OK | no tears reported; no kernel lines; ffmpeg + mpv as two clients |

Player command: `scripts/play.sh` (replaces the plan's interim mpv command).

## Known problems observed

- **Frame rate label after module load (Problem 2).** On some loads the first
  detection logs `No FPS Hint -> Pick 1920x1080p30` (or reports 119.88 fps)
  for a 60 Hz source; after any signal re-lock it reads p60. Delivery is
  always 60 frames per second. Effects seen: mpv and OBS announce 30 fps,
  ffmpeg warns about non-monotonic timestamps on every second frame, and
  `verify.sh`'s `signal` check fails on such a load. Reproduce: load the
  module with the Switch already outputting and read the kernel log; not every
  load shows it. Workaround: make the source re-lock (replug HDMI or
  sleep/wake the console). Upstream knobs to examine: `hdmi_rate_decode`,
  `procedural_timings`. Not investigated.
- **Contiguous memory at stream start (Problem 1).** Fixed on this machine by
  `cma=256M@0-4G`; any other machine with more than 4 GB of RAM needs the
  same, or an IOMMU. At 3840x2160 each DMA chain would be about 16 MB, which
  only a CMA pool can supply.
- **mpv cannot take the card's audio directly** (`--audio-file=av://alsa:` is
  silent, and an external audio input is not reopened after a signal loss);
  `play.sh` routes audio through a PipeWire loopback instead.
- **Installing or upgrading the package rebuilds both initramfs images**
  (CachyOS limine hook reacting to the modprobe.d file). Harmless, slow.
- 4K60, HDR and 10-bit were not exercised: the only source is a 1080p60 SDR
  console.

## Close-out (2026-09-19)

Bring-up is complete for the scope that can be tested here: 1080p60 SDR video
and audio through the DKMS-installed module on 6.18.50-3-cachyos-lts. Not
verified: 3840x2160 at 60 Hz (no such source), kernel 7.2.5-1-cachyos at run
time. The boot guard is still in place. Next: the player (`scripts/play.sh`
exists and is in daily use; desktop entry and a short spec are left), and the
frame rate label problem in the driver.
Boot guard decision (user, 2026-09-19): keep it. The module stays blacklisted
from autoloading; to revisit once the driver has more hours on it and kernel
7.2 has been run once by hand.

## Player: app menu launcher (2026-09-19)

- `scripts/install-desktop-entry.sh` generates
  `~/.local/share/applications/elgato-4k60-play.desktop` (the entry holds the
  clone's absolute path, so it is not shipped as a file); `--remove` deletes it.
- `scripts/play.sh` now loads the module when it is missing (`sudo -n modprobe
  sc0710`, else `pkexec modprobe sc0710`), waits for the V4L2 node and the
  PipeWire source after a fresh load, reports problems as desktop notifications
  when there is no terminal, allows one instance at a time (lock in
  `$XDG_RUNTIME_DIR`; a second one would double the sound), and gives the mpv
  window the app id `elgato-4k60-play` so the desktop matches it to the entry.
  The contiguous-memory message now names `cma=256M@0-4G`.
- Live test by the user, module unloaded with `scripts/unload.sh` first, then
  started from the app menu: "works". Machine side: `play.sh` was started by
  the session's systemd with no terminal, ran `modprobe sc0710` through sudo
  without a prompt (19:18:51, 24 s after the unload), and the PipeWire source
  was present with the loopback attached on that first launch.
- The already-running guard was tested by holding the lock: the second
  instance exits with a notification and leaves the running player alone.
- While the old `play.sh` was still running, the new version was swapped in
  with `mv`, not edited in place: bash reads a running script incrementally.
- Problem 2 tally: this load again picked `1920x1080p30`. Of four loads with
  the Switch already outputting, three mislabelled the rate (p30, p30, p30)
  and one got p60; the 119.88 reading came later on the first of them. It is
  the usual case after a load, not a rare one.

## Kernel updates (2026-09-19)

Checked how the install behaves across `pacman -Syu` with a new kernel:

- Headers for both kernels are explicitly installed, and the stock dkms hooks
  (`70-dkms-install`, `70-dkms-upgrade`, `71-dkms-remove`) trigger on
  `usr/lib/modules/*/build/include/`, so the module is rebuilt automatically.
- `kernel-modules-hook` is not installed: after a kernel upgrade the running
  kernel's modules are gone from disk, and an unloaded sc0710 cannot be loaded
  until reboot.
- `play.sh` now tells these cases apart before asking for authorization
  (`module_problem` in `verify-lib.sh`, with tests): "reboot to finish the
  update", "driver not built for this kernel", or the generic load failure.
  Tested in a bubblewrap sandbox with an empty `/proc/modules`, fake module
  trees and stub `sudo`/`pkexec`/`notify-send`, so the loaded driver and the
  running player were not disturbed. Not yet seen with a real kernel update.
- README gained a "Kernel updates" section with the recovery steps.

## Other programs' audio stutters while the console is off (2026-09-20/21)

Report: with the player open and the Switch off, Jellyfin's sound stuttered;
it stopped as soon as the Switch was turned on.

### Root cause

1. With no HDMI signal the driver keeps the ALSA capture stream alive by
   feeding silence (`driver/lib/sc0710-audio.c`, delivery-gap watchdog). It fed
   a fixed 480 frames and then re-armed a *relative* 10 ms delayed work. Each
   cycle really takes about 11.3 ms (timer rounding at HZ=1000 plus worker
   latency), so the 48 kHz stream advanced at 42446 Hz (measured: `hw_ptr`
   gained 84960 frames in 2.00 s, in steps of 480).
2. PipeWire gives ALSA capture nodes `priority.driver` 2000 and the built-in
   output 1009. `play.sh`'s `pw-loopback` links the two, so the capture card
   becomes the clock of the whole playback graph (`pw-top`: the card's node on
   the first line, the output, Jellyfin and the loopback as `+` followers).
3. The output, a follower of a clock running 11.6 % slow, ran dry:
   `spa.alsa: front:3p: follower avail:234 ... target:512, resync (27
   suppressed)` every 2 s, about 14 resyncs per second, from the second the
   player was opened until the loopback was stopped. With the Switch on the
   card's audio comes from real HDMI samples at 48 kHz and nothing is wrong.

### First fix attempt, reverted

A WirePlumber rule lowering the card's `priority.driver` to 100 made the
speakers the graph clock. Jellyfin was clean, but with the Switch on the card
delivers audio in 1024-frame bursts on the video frame interrupt (16.7 ms
apart with roughly every fourth slot skipped, 33 ms), and as a clock follower
its stream was resynchronised constantly: 95 `hw:5c: follower ... resync`
lines in six minutes, some hiding 160 repeats, 4907 node errors. For
comparison, 30 minutes with the card as clock and a signal present (the soak)
produced 3 lines. The user heard nothing wrong, but it was a regression in the
game audio, so the rule was removed. `priority.driver` cannot be changed at
runtime (`pw-cli set-param ... Props` is accepted and ignored).

### Fix

Driver patch `e0ab897` on the fork branch `silence-clock-pacing` (upstream
`ea0a712` plus this one commit; upstream had nothing newer): the watchdog
feeds the number of frames owed at 48 kHz since the gap began, by `ktime`. The
clock restarts when real samples resume and when the worker was held up for
more than 50 ms (never floods the ring buffer), and is rebased every second's
worth of frames so the multiplication cannot overflow. All new state is
touched only from the existing work item. A model of the arithmetic gives
42478 Hz for the old scheme and 47999.9 Hz for the new one.

Tested as a hand-built module (`insmod`, nothing installed), card as graph
clock again, no rule:

| | unpatched | patched |
|---|---|---|
| `scripts/audio-clock-check.sh`, Switch off | 42446 Hz | 48032 Hz, 48018 Hz |
| speaker resync lines, Switch off | one every 2 s | none |
| Switch on (signal restored 13:16:43, detected p60) | fine | fine |
| `spa.alsa` lines over the following 29 h, player open throughout | - | 1 |
| driver errors | 0 | 0 |

User: Jellyfin "sounds fine" with the player open and the Switch off; game
audio fine.

Made permanent on 2026-09-21: branch pushed to the fork, pin moved, package
`sc0710-mk2-dkms 2026.09.02.1.r224.e0ab897-1` installed over r223 (snapshots
5248/5249), DKMS `installed` for both kernels, header checksums unchanged. The
installed module has the same `srcversion` (DC5C7C3DFCEED15261BBC68) as the
tested build, which stayed loaded through the upgrade: no unload was needed.

Still to do: offer the patch upstream. Not changed: the 100 ms the watchdog
waits before it starts feeding silence, so other audio can drop out once for
that long at the moment the signal disappears.

### Side effect to know about

`scripts/unload.sh` restarts PipeWire. That disconnected every program's
audio; the Jellyfin desktop client did not reconnect and had to be restarted.
Now stated in the README.

New: `scripts/audio-clock-check.sh` measures the real rate of the card's audio
stream from `hw_ptr` (fails outside 48000 +/- 1 %).
