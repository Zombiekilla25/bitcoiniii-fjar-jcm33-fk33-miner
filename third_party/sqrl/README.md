# Bundled SQRL raw-JTAG bridge

This directory contains an x86-64 Linux SQRL bridge executable patched for
direct USER1/USER2 BSCAN transport:

```text
sqrl_bridge_rawjtag_coe
SHA256 8c7230f0bf586e9297dc0e568bd19278aeeb7cff8dbb3dde150811f11393218a
```

The original executable is the SQRL bridge artifact with SHA256
`4381283543d0c39650463f7ad8a91874eaeb0c5b2884be263fc4f9ab7bd19ec5`,
published in the Squirrels Research `eth-release-pkg` repository. The
repository reference used for provenance was commit
`622233937b70d25ea0133be41bf39add14e67617`, path
`1.7_Beta2/sqrl_bridge_2.1.4`.

See `PATCH_NOTES.md` for the exact byte changes and
`REDISTRIBUTION_PERMISSION.md` for the permission representation supplied by
this project's maintainer.

The bridge may require ABI-5 `libncurses` and `libtinfo` libraries. Those
libraries are not bundled. The installer checks dependencies with `ldd` and
accepts an authorized compatibility directory via `--compat-libs`.

The bridge listens on all interfaces. Protect its TCP ports with a firewall or
run it only on an isolated mining network.
