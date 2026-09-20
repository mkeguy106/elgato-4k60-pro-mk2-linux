# elgato-4k60-pro-mk2-linux

Getting the Elgato 4K60 Pro Mk.2 PCIe capture card (PCI `12ab:0710`, subsystem
`1cfa:000e`) working on Linux: driver packaging, verification, and a
low-latency live view for playing a console through the card.

Status: bring-up complete — 1080p60 SDR video and audio verified on CachyOS
with kernel 6.18 LTS (30-minute soak without a lost frame, OBS and mpv on the
card at the same time). 4K60 is a driver capability that has **not** been
verified here: the only source available is a 1080p60 console. HDR and 10-bit
are out of scope. Results and known problems: `docs/bring-up-log.md`.

## Layout

- `driver/` — submodule: [mkeguy106/sc0710](https://github.com/mkeguy106/sc0710),
  a fork of [Nakildias/sc0710](https://github.com/Nakildias/sc0710), pinned to
  the commit this repo was tested with.
- `packaging/` — pacman package that installs the driver through DKMS.
- `scripts/` — live view (`play.sh`), verification and module unload helpers.
- `tests/` — tests for the script library.
- `docs/` — design specs, plans, and the bring-up log.

## Clone

    git clone --recursive https://github.com/mkeguy106/elgato-4k60-pro-mk2-linux.git

## Before you start: contiguous memory below 4 GB

The driver allocates its capture buffers as physically contiguous blocks below
4 GB (about 4 MB each at 1080p, about 16 MB at 2160p). On a machine that has
been running for a while those blocks do not exist any more, and starting a
capture fails with `Cannot allocate memory` (ENOMEM at `VIDIOC_STREAMON`).

Reserve a pool on the kernel command line and reboot:

    cma=256M@0-4G

The `@0-4G` part matters. A plain `cma=256M` is placed above 4 GB on machines
with more RAM than that, where this driver cannot use it. Check after the
reboot:

    grep -i cma /proc/meminfo                  # CmaTotal: 262144 kB
    journalctl -k -b | grep 'cma: Reserved'    # address below 0x100000000

The kernel needs `CONFIG_DMA_CMA=y`. Without a reboot, this usually frees
enough memory for one session:

    sudo sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches'
    sudo sh -c 'echo 1 > /proc/sys/vm/compact_memory'

## Try the driver without installing anything

    make -C driver
    sudo modprobe -a $(modinfo -F depends driver/build/sc0710.ko | tr ',' ' ')
    sudo insmod driver/build/sc0710.ko

A reboot removes it completely.

## Install (Arch-based, DKMS)

    sudo pacman -S --needed dkms
    cd packaging && makepkg -f
    sudo pacman -U sc0710-mk2-dkms-*.pkg.tar.zst
    dkms status sc0710
    sudo modprobe sc0710

The package installs `/etc/modprobe.d/sc0710-blacklist.conf`, so the module
loads only when you run `modprobe sc0710`, never automatically at boot.

## Kernel updates

DKMS rebuilds the module whenever a kernel's headers package is upgraded, so
keep the headers package installed for every kernel you boot
(`linux-cachyos-lts-headers`, `linux-headers`, ...). After an update that
brought a new kernel:

    dkms status sc0710        # one line per kernel, each ending in "installed"

Two things can stop the card working; neither affects booting, because the
module is not in the initramfs and is never loaded automatically.

- **Until the next reboot.** Upgrading the kernel package removes the running
  kernel's modules from disk. If the driver was not loaded before the update it
  cannot be loaded until you reboot. `play.sh` says so.
- **The build fails on a new kernel series.** This is an out-of-tree driver
  pinned to one tested commit. Point releases of an LTS kernel are very
  unlikely to break it; a new major series occasionally will. pacman prints
  the DKMS error and carries on, and `dkms status` shows no `installed` line
  for that kernel; the build log is
  `/var/lib/dkms/sc0710/<version>/build/make.log`. Boot a kernel that still has
  the module, then move `driver/` to an upstream commit that supports the new
  kernel, rebuild the package and reinstall it:

      git -C driver fetch origin && git -C driver checkout <commit>
      cd packaging && makepkg -f && sudo pacman -U sc0710-mk2-dkms-*.pkg.tar.zst

The `cma=` parameter survives kernel updates as long as it is in the file your
boot loader tooling generates entries from (`/etc/kernel/cmdline` on CachyOS
with Limine).

## Verify

Connect a source with HDCP off and sound playing, then:

    scripts/verify.sh              # expects 1920x1080 at 60 Hz
    scripts/verify.sh 3840x2160    # any other size the source outputs

It prints one PASS/FAIL/LOOK line per check and saves a frame to `out/` for you
to look at.

## Play

    scripts/play.sh
    scripts/install-desktop-entry.sh    # optional: adds it to the app menu (--remove undoes it)

Low-latency live view: mpv shows the video as frames arrive, and a PipeWire
loopback plays the card's audio. Needs `mpv` and PipeWire (`pw-loopback`,
`pactl`). Volume is controlled inside the mpv window with 9/0, / and *, the
mouse wheel, and m to mute. Other programs (OBS, ffmpeg) can capture from the
card at the same time.

If the module is not loaded, `play.sh` loads it: silently where `sudo` needs no
password, otherwise through the desktop's authorization dialog (`pkexec
modprobe sc0710`). Started from the app menu, problems are reported as desktop
notifications. Only one instance runs at a time.

## Unload

    scripts/unload.sh

PipeWire holds the device nodes open, so a plain `rmmod` is refused. The script
stops PipeWire, unloads, and restarts it. Close the player and any capture
program first. Never use `rmmod -f`.

## Known problems

- After some module loads the driver announces the wrong frame rate for a
  60 Hz source (30 or 119.88 fps) until the signal re-locks. It still delivers
  60 frames per second. `play.sh` is not affected; OBS and ffmpeg show the
  wrong number. Unplugging and replugging HDMI, or putting the console to
  sleep and waking it, corrects it.
- Details and the rest of the list: `docs/bring-up-log.md`.

## Roll back

- Uninstall: `sudo pacman -R sc0710-mk2-dkms`
- Machine will not boot with the module: add `module_blacklist=sc0710` to the
  kernel command line from the boot menu.

## License

GPL-2.0-or-later. The driver in `driver/` is GPL-2.0-or-later, copyright its
authors; see `driver/COPYRIGHT`.
