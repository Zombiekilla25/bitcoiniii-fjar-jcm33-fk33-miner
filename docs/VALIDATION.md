# Hardware validation

The standalone path completed these gates on Ubuntu 24.04 x86-64:

1. Exact-card SQRL USB/JTAG selection.
2. FPGA programming without Vivado on the runtime host.
3. One-byte BSCAN handshake (`5a` in, exactly one `a5` out).
4. Complete framed protocol probe: 117 bytes in and 45 bytes out.
5. Full 350 MHz mining-image synthesis, implementation, and routing.
6. Positive routed timing with WNS `+0.031 ns` and TNS `0.000 ns`.
7. Zero routing errors across 642,228 fully routed nets.
8. Live Stratum subscription and authorization.
9. Matching hardware and Python SHA3-256T digests.
10. Accepted FJAR pool shares through the standalone transport.

The canary test used one isolated FK33. It does not guarantee every board,
power supply, cooling configuration, host, pool, or network will behave the
same way.

The bridge may log failure to read optional JungleCat metadata on an FK33. That
message was nonfatal during validation; bitstream loading, framed transport,
digest comparison, and pool submissions proceeded successfully.
