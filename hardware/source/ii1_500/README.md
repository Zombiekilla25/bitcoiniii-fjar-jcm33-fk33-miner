# 500 MHz II1 source

This directory contains the hardware source and build flow for the
hardware-validated 500 MHz, initiation-interval-one SHA3-256T FK33 engine.

Run `run_build.sh` on a Vivado 2026.1 development host. The build performs the
known-answer simulation first, then synthesis, placement, routing, setup and
hold timing gates, and uncompressed bitstream generation for the legacy SQRL
loader.

The validated six-card result and whole-rig power measurement are documented
in `docs/PERFORMANCE.md`.
