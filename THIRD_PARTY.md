# Third-party runtime components

## SQRL bridge

This release includes `third_party/sqrl/sqrl_bridge_rawjtag_coe`, an x86-64
Linux SQRL bridge patched at two validated instruction sites for direct
USER1/USER2 BSCAN transport.

The project maintainer represents that David Stanfill, publisher of the SQRL
bridge and a Squirrels Research contributor, granted permission to redistribute
the original executable and this patched derivative as part of this project.
See:

- `third_party/sqrl/REDISTRIBUTION_PERMISSION.md`
- `third_party/sqrl/PATCH_NOTES.md`
- `third_party/sqrl/patch_rawjtag.py`

Upstream reference:
[github.com/SquirrelsResearch/eth-release-pkg](https://github.com/SquirrelsResearch/eth-release-pkg),
commit `622233937b70d25ea0133be41bf39add14e67617`.

The installer uses the bundled executable by default and accepts
`--sqrl-bridge PATH` for an authorized compatible override.

## Compatibility libraries

The bridge may require `libncurses.so.5` and `libtinfo.so.5` on current
Linux systems. These libraries are not bundled. Obtain them from an authorized
distribution or installation and pass their directory with
`--compat-libs DIR`. The installer runs `ldd` and refuses unresolved
libraries.

## Operational constraints

The bridge creates and truncates `virtual_ports` in its working directory.
The service provides a private writable fleet directory; running older bridge
builds from an unwritable directory can crash.

One bridge process must own the whole local FK33 fleet. Do not start one bridge
per card. It allocates consecutive ports in USB scan order, and the miner
services validate each serial-to-port mapping before connecting.

The executable binds its TCP listeners to all interfaces. Restrict the fleet
port range with the host firewall or use an isolated mining network.
