# Raw-JTAG patch notes

The distributed executable differs from the identified upstream SQRL artifact
at exactly two instruction sites. The changes bypass the CoE paths and use the
FPGA BSCAN USER instructions expected by this miner.

| Virtual/file offset | Original bytes | Patched bytes | Purpose |
|---|---|---|---|
| `0x210f6` | `488b7f104189cd4d89c64885ff7473` | `4189cd4d89c6e91f01000090909090` | V2 bulk read: CoE FIFO to raw USER1 |
| `0x2144c` | `0f845e010000` | `e9d600000090` | V1 bulk write: CoE command 0x1204 to raw USER2 |

Checksums:

```text
original 4381283543d0c39650463f7ad8a91874eaeb0c5b2884be263fc4f9ab7bd19ec5
patched  8c7230f0bf586e9297dc0e568bd19278aeeb7cff8dbb3dde150811f11393218a
```

`patch_rawjtag.py` refuses any source with a different checksum or unexpected
instruction bytes and verifies the output checksum.
