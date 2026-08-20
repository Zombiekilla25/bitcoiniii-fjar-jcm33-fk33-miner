#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$ROOT"

printf 'Verifying SHA256SUMS...\n'
sha256sum --check SHA256SUMS

printf '\nChecking Python syntax and offline tests...\n'
python3 - <<'PY'
import pathlib

paths = [
    pathlib.Path("runtime/fjar_bridge.py"),
    pathlib.Path("runtime/fleet_status.py"),
    pathlib.Path("tests/test_fjar_bridge.py"),
]
for path in paths:
    compile(path.read_text(), str(path), "exec")
print(f"Python syntax passed: {len(paths)} files")
PY
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v

printf '\nChecking shell syntax...\n'
for SCRIPT in ./*.sh hardware/source/*.sh; do
    bash -n "$SCRIPT"
done

printf '\nChecking Tcl completeness...\n'
if command -v tclsh >/dev/null 2>&1; then
    tclsh <<'TCL'
set files [concat \
    [glob -nocomplain hardware/source/*.tcl] \
    [glob -nocomplain runtime/*.tcl]]
foreach file $files {
    set channel [open $file r]
    set source [read $channel]
    close $channel
    if {![info complete $source]} {
        puts stderr "Incomplete Tcl syntax: $file"
        exit 1
    }
}
puts "Tcl files complete: [llength $files]"
TCL
else
    python3 - <<'PY'
import pathlib

try:
    import tkinter
except ImportError:
    print("SKIP: neither tclsh nor Python tkinter is available.")
    raise SystemExit(0)

interp = tkinter.Tcl()
files = sorted(pathlib.Path("hardware/source").glob("*.tcl"))
files += sorted(pathlib.Path("runtime").glob("*.tcl"))
for path in files:
    if interp.call("info", "complete", path.read_text()) != 1:
        raise SystemExit(f"Incomplete Tcl syntax: {path}")
print(f"Tcl files complete: {len(files)}")
PY
fi

printf '\nChecking systemd unit syntax...\n'
if command -v systemd-analyze >/dev/null 2>&1; then
    systemd-analyze verify \
        systemd/fjar-fk33-worker@.service \
        systemd/fjar-fk33-bridge@.service
else
    printf 'SKIP: systemd-analyze is unavailable.\n'
fi

printf '\nChecking release configuration invariants...\n'
grep -Fq \
    'USER_WALLET = os.environ.get("FJAR_WALLET", "").strip()' \
    runtime/fjar_bridge.py

EXPECTED_DEV_WALLET='fjarcode:qq5daj4gl6q7t7hpwm2e5vu84gn4p3h7huu4h64z9l'
EMBEDDED_ADDRESSES=$(grep -Eo 'fjarcode:[a-z0-9]{20,120}' \
    runtime/fjar_bridge.py | sort -u)
if [[ "$EMBEDDED_ADDRESSES" != "$EXPECTED_DEV_WALLET" ]]; then
    printf 'Unexpected embedded FJAR address set:\n%s\n' \
        "$EMBEDDED_ADDRESSES" >&2
    exit 1
fi

test -s hardware/prebuilt/fk33_fjar_80pipe_token3_350mhz.bit
test -s hardware/prebuilt/fk33_fjar_80pipe_token3_350mhz.ltx

printf '\nChecking known private identifiers...\n'
if grep -RInE \
    'rmann|Host[[:space:]]*:[[:space:]]*RGB|153300001064|153300000286|153300000354|153300000267|153300000731|bc1qwcusej0umav5dw9k9f6cuy6mhzsdj9su4rayqu' \
    . \
    --binary-files=without-match \
    --exclude=SHA256SUMS \
    --exclude=verify-release.sh; then
    printf 'Private identifier audit failed.\n' >&2
    exit 1
fi

printf '\nRelease verification passed.\n'
