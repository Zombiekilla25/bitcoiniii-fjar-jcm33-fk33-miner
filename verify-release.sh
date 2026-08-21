#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$ROOT"

printf 'Verifying SHA256SUMS...\n'
sha256sum --check SHA256SUMS

printf '\nChecking manifest coverage...\n'
MANIFEST_PATHS=$(mktemp)
TREE_PATHS=$(mktemp)
trap 'rm -f "$MANIFEST_PATHS" "$TREE_PATHS"' EXIT
awk '{sub(/^\*/, "", $2); print $2}' SHA256SUMS | sort >"$MANIFEST_PATHS"
find . -path './.git' -prune -o -type f ! -name SHA256SUMS -print |
    sort >"$TREE_PATHS"
if ! diff -u "$MANIFEST_PATHS" "$TREE_PATHS"; then
    printf 'SHA256SUMS does not exactly cover the release tree.\n' >&2
    exit 1
fi

printf '\nChecking Python syntax and tests...\n'
python3 - <<'PY'
from pathlib import Path

paths = [
    Path("runtime/fjar_bridge.py"),
    Path("third_party/sqrl/patch_rawjtag.py"),
    *sorted(Path("tests").glob("*.py")),
]
for path in paths:
    compile(path.read_text(), str(path), "exec")
print(f"Python syntax passed: {len(paths)} files")
PY
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v

printf '\nChecking shell syntax...\n'
for script in ./*.sh runtime/*.sh hardware/source/*.sh; do
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
    UNIT_TEST_DIR=$(mktemp -d)
    for UNIT in fk33-sqrl-fleet.service fjar-fk33-fleet@.service; do
        sed -E \
            's#^(ExecStartPre|ExecStart)=.*$#\1=/bin/true#' \
            "systemd/$UNIT" >"$UNIT_TEST_DIR/$UNIT"
    done
    systemd-analyze verify \
        "$UNIT_TEST_DIR/fk33-sqrl-fleet.service" \
        "$UNIT_TEST_DIR/fjar-fk33-fleet@.service"
    rm -r "$UNIT_TEST_DIR"
else
    printf 'SKIP: systemd-analyze is unavailable.\n'
fi

printf '\nChecking release invariants...\n'
[[ $(<VERSION) == 0.2.1-beta ]]
grep -Fq 'VERSION="0.2.1-beta"' install.sh
grep -Fq 'USER_WALLET = os.environ.get("FJAR_WALLET", "").strip()' \
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

EXPECTED_BRIDGE_SHA='8c7230f0bf586e9297dc0e568bd19278aeeb7cff8dbb3dde150811f11393218a'
printf '%s  %s\n' "$EXPECTED_BRIDGE_SHA" \
    third_party/sqrl/sqrl_bridge_rawjtag_coe | sha256sum --check
file third_party/sqrl/sqrl_bridge_rawjtag_coe |
    grep -Eq 'ELF 64-bit.*x86-64'

mapfile -t BRIDGES < <(
    find . -path './.git' -prune -o -type f -name 'sqrl_bridge*' -print
)
if (("${#BRIDGES[@]}" != 1)) ||
   [[ "${BRIDGES[0]}" != ./third_party/sqrl/sqrl_bridge_rawjtag_coe ]]; then
    printf 'Unexpected SQRL bridge artifact set:\n%s\n' \
        "$(printf '%s\n' "${BRIDGES[@]}")" >&2
    exit 1
fi

if find . -path './.git' -prune -o -type f \
    \( -name 'libncurses.so*' -o -name 'libtinfo.so*' \) -print |
    grep .; then
    printf 'Legacy ABI libraries must not be distributed.\n' >&2
    exit 1
fi

if find systemd -type f \
    \( -name 'fk33-sqrl-bridge@.service' \
       -o -name 'fjar-fk33-standalone@.service' \) -print |
    grep .; then
    printf 'Legacy per-card bridge units remain in the release.\n' >&2
    exit 1
fi

grep -Fq 'Requires=fk33-sqrl-fleet.service' \
    systemd/fjar-fk33-fleet@.service
grep -Fq 'wait-fleet-card.sh' systemd/fjar-fk33-fleet@.service
grep -Fq 'release-ftdi-fleet.sh' systemd/fk33-sqrl-fleet.service
grep -Fq 'REDISTRIBUTION_PERMISSION.md' THIRD_PARTY.md
grep -Fq '4381283543d0c39650463f7ad8a91874eaeb0c5b2884be263fc4f9ab7bd19ec5' \
    third_party/sqrl/PATCH_NOTES.md

printf '\nChecking private identifiers...\n'
if grep -RInE \
    'rmann|Host[[:space:]]*:[[:space:]]*RGB|153300000[0-9]{3}|153300001064|bc1qwcusej0umav5dw9k9f6cuy6mhzsdj9su4rayqu' \
    . --binary-files=without-match --exclude-dir=.git \
    --exclude=SHA256SUMS --exclude=verify-release.sh; then
    printf 'Private identifier audit failed.\n' >&2
    exit 1
fi

printf '\nRelease verification passed.\n'
