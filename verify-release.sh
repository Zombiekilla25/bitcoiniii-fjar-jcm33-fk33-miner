#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$ROOT"

printf 'Verifying SHA256SUMS...\n'
sha256sum --check SHA256SUMS

printf '\nChecking Python syntax and tests...\n'
python3 - <<'PY'
from pathlib import Path

paths = [Path("runtime/fjar_bridge.py"), *sorted(Path("tests").glob("*.py"))]
for path in paths:
    compile(path.read_text(), str(path), "exec")
print(f"Python syntax passed: {len(paths)} files")
PY
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v

printf '\nChecking shell syntax...\n'
for script in ./*.sh hardware/source/*.sh; do
    bash -n "$script"
done

printf '\nChecking Tcl completeness...\n'
if command -v tclsh >/dev/null 2>&1; then
    tclsh <<'TCL'
set files [glob -nocomplain hardware/source/*.tcl]
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
fi

printf '\nChecking systemd unit syntax...\n'
if command -v systemd-analyze >/dev/null 2>&1; then
    systemd-analyze verify \
        systemd/fk33-sqrl-bridge@.service \
        systemd/fjar-fk33-standalone@.service
else
    printf 'SKIP: systemd-analyze is unavailable.\n'
fi

printf '\nChecking release invariants...\n'
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

test -s hardware/prebuilt/fk33_fjar_bscan_350.bit
grep -Fq 'COMPRESS=FALSE' <(file hardware/prebuilt/fk33_fjar_bscan_350.bit)
grep -Fq 'All user specified timing constraints are met.' \
    hardware/reports/fk33_fjar_bscan_350_timing.rpt
grep -Eq '# of nets with routing errors[^:]*:[[:space:]]+0' \
    hardware/reports/fk33_fjar_bscan_350_route_status.rpt

if find . -path './.git' -prune -o -type f \
    \( -name 'sqrl_bridge*' -o -name 'libncurses.so*' -o -name 'libtinfo.so*' \) \
    -print | grep .; then
    printf 'Third-party runtime files must not be distributed.\n' >&2
    exit 1
fi

printf '\nChecking private identifiers...\n'
if grep -RInE \
    'rmann|Host[[:space:]]*:[[:space:]]*RGB|153300000[0-9]{3}|153300001064|bc1qwcusej0umav5dw9k9f6cuy6mhzsdj9su4rayqu' \
    . --binary-files=without-match --exclude-dir=.git \
    --exclude=SHA256SUMS --exclude=verify-release.sh; then
    printf 'Private identifier audit failed.\n' >&2
    exit 1
fi

printf '\nRelease verification passed.\n'
