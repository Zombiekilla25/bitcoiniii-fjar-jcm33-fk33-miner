# Hardware validation

The standalone path completed these gates on Ubuntu 24.04 x86-64:

1. Exact-card SQRL USB/JTAG selection.
2. FPGA programming without Vivado on the runtime host.
3. Complete framed protocol probe: 117 bytes in and 45 bytes out.
4. Full 350 MHz mining-image synthesis, implementation, and routing.
5. Positive routed timing with WNS `+0.031 ns` and TNS `0.000 ns`.
6. Zero routing errors across 642,228 fully routed nets.
7. Live Stratum subscription and authorization.
8. Matching hardware and Python SHA3-256T digests.
9. Accepted FJAR pool shares through the standalone transport.
10. One bridge discovering and programming five physical FK33 cards.
11. Five independent miners producing accepted shares without mismatches.
12. Real reboot recovery with persistent USB permissions, five loaded
    bitstreams, five active miners, and five fresh accepted shares.

The bridge may log failure to read optional JungleCat metadata on an FK33. That
message was nonfatal during validation.

## Fleet acceptance gate

For every configured card, require:

- exactly one matching USB serial;
- its two FTDI interfaces released from `ftdi_sio`;
- read/write access to its USB node;
- one distinct TCP listener;
- the expected serial followed by the expected port in the fleet log;
- a completed bitstream-load event;
- matching `hw=` and `sw=` digest lines;
- a pool response with `result: True`.

Any mismatch, traceback, rejected share, repeated service restart, or changed
serial-to-port association is a stop condition.
