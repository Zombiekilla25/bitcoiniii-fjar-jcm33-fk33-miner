# Hardware validation

The v0.3.0-beta standalone path completed these gates on Ubuntu 24.04 x86-64:

1. Exact-card SQRL USB/JTAG selection and fail-closed serial/port mapping.
2. FPGA programming without Vivado on the runtime host.
3. Complete 117-byte job and 45-byte share framed transport.
4. SHA3T known-answer simulation and physical digest verification.
5. Full 500 MHz synthesis, placement, routing, and bit generation.
6. Positive timing: WNS `+0.336 ns`, TNS `0.000 ns`, WHS `+0.010 ns`.
7. Zero routing errors across 360,460 fully routed nets.
8. One bridge programming six physical FK33 cards.
9. Six independent miners producing matching hardware/Python digests.
10. Pool-accepted shares from every card with zero measured rejects.
11. Fresh `extranonce2` work every 7.5 seconds before nonce exhaustion.
12. Measured effective fleet rate of 2.887 GH/s, up 91.95% from 1.504 GH/s.

The bridge may report failure to read optional JungleCat metadata on an FK33.
That message was nonfatal during validation.

## Fleet acceptance gate

For every card require its expected USB serial and port, released FTDI
interfaces, completed bitstream load, matching `hw=` and `sw=` digests, fresh
work-roll messages, and pool responses with `result: True`.

Any unexpected mapping, traceback, rejected share, digest mismatch, comparator
disagreement, repeated restart, or stale nonce-space behavior is a stop
condition.
