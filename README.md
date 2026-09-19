# elgato-4k60-pro-mk2-linux

Getting the Elgato 4K60 Pro Mk.2 PCIe capture card (PCI `12ab:0710`, subsystem
`1cfa:000e`) working on Linux: driver, packaging, verification, and later a
low-latency player and true 10-bit HDR10 capture.

Status: bring-up in progress. See `docs/superpowers/specs/` for the design.

## Layout

- `driver/` — submodule: [mkeguy106/sc0710](https://github.com/mkeguy106/sc0710),
  a fork of [Nakildias/sc0710](https://github.com/Nakildias/sc0710), pinned to
  the commit this repo was tested with.
- `packaging/` — pacman package that installs the driver through DKMS.
- `scripts/` — verification and module unload helpers.
- `docs/` — design specs, plans, and the bring-up log.

## Clone

    git clone --recursive https://github.com/mkeguy106/elgato-4k60-pro-mk2-linux.git

## License

GPL-2.0-or-later. The driver in `driver/` is GPL-2.0-or-later, copyright its
authors; see `driver/COPYRIGHT`.
