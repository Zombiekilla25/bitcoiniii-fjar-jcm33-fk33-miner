# Hardware validation

## Native FK33 650 MHz — v0.5.0-beta

The native eight-bit 650 MHz image completed these gates on one physical FK33:

1. Exact uncompressed bitstream identity and VU33P target verification.
2. Native eight-bit FK33 transport identity.
3. Positive routed timing: setup WNS `+0.002 ns`, hold WHS `+0.007 ns`.
4. Sixty-minute BitcoinIII hardware soak at unchanged voltage.
5. 740 hardware share frames with matching hardware/software digests.
6. 65 byte-identical duplicate candidates suppressed before submission.
7. 675 submitted and 675 accepted pool shares.
8. Zero rejected shares, digest mismatches, and protocol errors.
9. Post-soak temperature `41.076 C` and VCCINT `0.803 V` observed.
10. Exact qualified 525 MHz rollback loaded and confirmed.

This qualifies one card and one route; it does not establish fleet-wide yield.
The 650 MHz image remains an explicit selection until a multi-card rollout
passes.

## FK33 525 MHz fleet — v0.4.0-beta

The `v0.4.0-beta` standalone path completed these gates on Ubuntu 24.04
x86-64:

1. Exact-card USB/JTAG selection and fail-closed serial-to-port mapping.
2. FPGA programming without Vivado on the runtime host.
3. Complete 117-byte job and 45-byte share framed transport.
4. SHA3T simulation and physical hardware/Python digest verification.
5. Complete 525 MHz synthesis, placement, routing, and bit generation.
6. Positive timing: WNS `+0.056 ns`, TNS `0.000 ns`, WHS `+0.010 ns`.
7. Fully routed implementation with zero routing errors.
8. One shared bridge programming six physical FK33 cards.
9. Six independent accepted-share streams.
10. Fresh `extranonce2` work every 7.5 seconds.
11. A 660-second target-derived result of 3.172 GH/s.
12. A 9.87% gain over the measured 2.887 GH/s 500 MHz baseline.
13. 680 submitted and 680 accepted shares.
14. Zero rejects, duplicates, digest faults, or runtime faults.
15. Authenticated 500 MHz rollback image retained.

The systemd readiness helper requires the expected serial and TCP port
mapping, complete fleet programming, and a listening port before starting a
miner.

An unexpected mapping, traceback, rejected share, digest mismatch, comparator
disagreement, restart loop, or stale nonce-space condition is a stop condition.
