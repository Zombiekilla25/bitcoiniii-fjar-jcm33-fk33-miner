# Third-party runtime components

This repository does not distribute the SQRL raw-JTAG bridge executable or the
legacy ABI libraries sometimes required by that executable.

The installer accepts operator-supplied paths:

```text
--sqrl-bridge /path/to/sqrl_bridge_rawjtag_coe
--compat-libs /path/to/compat_libs
```

Only use files you are authorized to possess and run. Employment history,
hardware ownership, or technical compatibility does not by itself establish
redistribution rights. Do not attach these third-party files to a public GitHub
release unless their license or rightsholder explicitly permits redistribution.

The validated bridge was an x86-64 Linux executable. On Ubuntu 24.04 it needed
`libncurses.so.5` and `libtinfo.so.5` supplied through `LD_LIBRARY_PATH`. Your
copy may have different dependencies. The installer runs `ldd` with the chosen
compatibility directory and refuses unresolved libraries.

The bridge creates and truncates a file named `virtual_ports` in its working
directory. The supplied service gives every card a private writable directory;
running it from an unwritable directory can crash older bridge builds.

The validated executable bound its TCP listener to all interfaces. Restrict the
configured port with the host firewall or use an isolated mining network. The
Python miner connects through `127.0.0.1`, but that does not itself prevent
other hosts from reaching a listener bound to `0.0.0.0`.
