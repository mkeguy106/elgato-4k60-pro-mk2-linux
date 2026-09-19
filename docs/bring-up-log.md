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
- Tears, frame shifts or audio dropouts seen by the user: (to be filled in)
