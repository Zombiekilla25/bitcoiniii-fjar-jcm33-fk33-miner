# JCM33 525 MHz validation record

## Passing result

The dual-alignment BitcoinIII canary passed on 2026-08-28:

```text
accepted_A=185
accepted_B=211
rejected=0
hardware_software_mismatches=0
```

Both VU33P devices received independent jobs through their physical USER2
chain positions, returned lane-identified candidates through USER1, matched
software SHA3-256T verification, and produced shares accepted by PythonPool.

## Qualified configuration

- Clock target: 525 MHz
- Algorithm: SHA3-256T / BitcoinIII
- Pool used for qualification: `stratum.pythonpool.dev:3357`
- Transport: nine-bit USER2 capture with low/high byte alignment lock
- Dispatch: independent A-tailpad and B-tailpad frames
- Voltage operation: none
- Automatic 350 MHz restore: none

## Not covered by this result

The passing result does not qualify an overclock, voltage change, different
carrier, failed cooling system, or modified transport. Any higher clock must
pass implementation timing and then repeat the same A/B acceptance, rejection,
and hardware/software mismatch gates before it is labeled production-ready.
