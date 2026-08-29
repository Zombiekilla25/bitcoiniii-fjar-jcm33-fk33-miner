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
    Path("runtime/btc3_bridge.py"),
    Path("third_party/sqrl/patch_rawjtag.py"),
    Path("research/jcm33_dualalign_btc3_525/jcm33_btc3_dual_miner.py"),
    Path("research/jcm33_dualalign_btc3_525/jcm33_ir_lane_calibration.py"),
    Path("research/jcm33_dualalign_btc3_525/test_jcm33_dualalign_btc3_canary.py"),
    Path("research/jcm33_dualalign_btc3_550/jcm33_btc3_dual_miner.py"),
    Path("research/jcm33_dualalign_btc3_550/jcm33_ir_lane_calibration.py"),
    Path("research/jcm33_dualalign_btc3_550/test_jcm33_dualalign_btc3_550_canary.py"),
    Path("research/jcm33_dualalign_btc3_650/jcm33_btc3_dual_miner.py"),
    Path("research/jcm33_dualalign_btc3_650/jcm33_ir_lane_calibration.py"),
    Path("research/jcm33_dualalign_btc3_650/test_jcm33_dualalign_btc3_650_canary.py"),
    *sorted(Path("tests").glob("*.py")),
]
for path in paths:
    compile(path.read_text(), str(path), "exec")
print(f"Python syntax passed: {len(paths)} files")
PY
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v

printf '\nChecking shell syntax...\n'
for script in ./*.sh runtime/*.sh hardware/source/*.sh hardware/source/*/*.sh \
    research/jcm33_dualalign_btc3_525/*.sh \
    research/jcm33_dualalign_btc3_550/*.sh \
    research/jcm33_dualalign_btc3_650/*.sh; do
    bash -n "$script"
done

printf '\nChecking Tcl completeness...\n'
if command -v tclsh >/dev/null 2>&1; then
    tclsh <<'TCL'
set files [concat \
    [glob -nocomplain hardware/source/*.tcl] \
    [glob -nocomplain hardware/source/*/*.tcl] \
    [glob -nocomplain research/jcm33_dualalign_btc3_525/*.tcl] \
    [glob -nocomplain research/jcm33_dualalign_btc3_550/*.tcl] \
    [glob -nocomplain research/jcm33_dualalign_btc3_650/*.tcl] \
]
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
[[ $(<VERSION) == 0.5.0-beta ]]
grep -Fq 'VERSION="0.5.0-beta"' install.sh
grep -Fq 'USER_WALLET = os.environ.get("FJAR_WALLET", "").strip()' \
    runtime/fjar_bridge.py
grep -Fq 'FJAR_WORK_ROLL_SECONDS' runtime/fjar_bridge.py

EXPECTED_DEV_WALLET='fjarcode:qq5daj4gl6q7t7hpwm2e5vu84gn4p3h7huu4h64z9l'
EMBEDDED_ADDRESSES=$(grep -Eo 'fjarcode:[a-z0-9]{20,120}' \
    runtime/fjar_bridge.py | sort -u)
if [[ "$EMBEDDED_ADDRESSES" != "$EXPECTED_DEV_WALLET" ]]; then
    printf 'Unexpected embedded FJAR address set:\n%s\n' \
        "$EMBEDDED_ADDRESSES" >&2
    exit 1
fi

EXPECTED_BTC3_DEV_WALLET='bc1qwcusej0umav5dw9k9f6cuy6mhzsdj9su4rayqu'
for MINER in \
    runtime/btc3_bridge.py \
    research/jcm33_dualalign_btc3_525/jcm33_btc3_dual_miner.py \
    research/jcm33_dualalign_btc3_550/jcm33_btc3_dual_miner.py \
    research/jcm33_dualalign_btc3_650/jcm33_btc3_dual_miner.py; do
    grep -Fq "DEV_WALLET = \"$EXPECTED_BTC3_DEV_WALLET\"" "$MINER"
    grep -Fq 'DEV_FEE_BPS = 100' "$MINER"
    grep -Fq 'DEV_WORKER_SUFFIX = "-DEVFEE"' "$MINER"
done

EXPECTED_BIT_500_SHA='efe740723b4ef4d93b29339cdeea32416495aabea8f78cb15f3456c44a354ecb'
printf '%s  %s\n' "$EXPECTED_BIT_500_SHA" \
    hardware/prebuilt/fk33_fjar_bscan_500.bit | sha256sum --check

EXPECTED_BIT_525_SHA='64e0a7d21a10b4aa04b340c826af7d75363b5d5ba5e39330fe28c42ff103821c'
printf '%s  %s\n' "$EXPECTED_BIT_525_SHA" \
    hardware/prebuilt/fk33_fjar_bscan_525.bit | sha256sum --check

EXPECTED_BIT_650_SHA='bd494ba2ea697a5e916b51caf4bdab8e5c620cd121bfd4b2e9a806deb5596c39'
printf '%s  %s\n' "$EXPECTED_BIT_650_SHA" \
    hardware/prebuilt/fk33_native_bscan_650_validated.bit | sha256sum --check
file hardware/prebuilt/fk33_native_bscan_650_validated.bit |
    grep -Fq 'COMPRESS=FALSE'
grep -Fq 'top=miner_top_ii1_bscan_650' \
    evidence/fk33_native_650/bitstream-identity.txt
grep -Fq 'setup_wns_ns=0.002' \
    evidence/fk33_native_650/timing-summary.txt
grep -Fq 'hold_whs_ns=0.007' \
    evidence/fk33_native_650/timing-summary.txt
grep -Fq 'submitted=675' evidence/fk33_native_650/soak-60m-summary.txt
grep -Fq 'accepted=675' evidence/fk33_native_650/soak-60m-summary.txt
grep -Fq 'rejected=0' evidence/fk33_native_650/soak-60m-summary.txt
grep -Fq 'hardware_software_mismatches=0' \
    evidence/fk33_native_650/soak-60m-summary.txt
grep -Fq 'rollback_525=pass' evidence/fk33_native_650/soak-60m-summary.txt

EXPECTED_BIT_550_SHA='de9621edb8fdb1df35270ac601668b0b30ada110c5ed446114755c7093a2e8db'
printf '%s  %s\n' "$EXPECTED_BIT_550_SHA" \
    hardware/prebuilt/fk33_fjar_bscan_550_experimental.bit | sha256sum --check
file hardware/prebuilt/fk33_fjar_bscan_550_experimental.bit |
    grep -Fq 'COMPRESS=FALSE'

EXPECTED_JCM33_BIT_SHA='2ef00b41b8b542cf4725336c7754e3b81e5a23aa710993fc0f5f8b2828e05a8d'
printf '%s  %s\n' "$EXPECTED_JCM33_BIT_SHA" \
    hardware/prebuilt/jcm33_bitcoiniii_dualalign_525_validated.bit | sha256sum --check
file hardware/prebuilt/jcm33_bitcoiniii_dualalign_525_validated.bit |
    grep -Fq 'COMPRESS=FALSE'
grep -Fq "$EXPECTED_JCM33_BIT_SHA" \
    research/jcm33_dualalign_btc3_525/PREBUILT_SHA256.txt

EXPECTED_JCM33_BIT_550_SHA='9b75f638459b9c07cc4b36cade5c41d6e45df8f18d9c26020b651f95b52d5e6c'
printf '%s  %s\n' "$EXPECTED_JCM33_BIT_550_SHA" \
    hardware/prebuilt/jcm33_bitcoiniii_dualalign_550_validated.bit | sha256sum --check
file hardware/prebuilt/jcm33_bitcoiniii_dualalign_550_validated.bit |
    grep -Fq 'COMPRESS=FALSE'
grep -Fq "$EXPECTED_JCM33_BIT_550_SHA" \
    research/jcm33_dualalign_btc3_550/PREBUILT_SHA256.txt

EXPECTED_JCM33_BIT_650_SHA='0eacb71eb4cb5f6a43f761d1af64dfe25c8fa22177974082742dc12d6f6cdcf1'
printf '%s  %s\n' "$EXPECTED_JCM33_BIT_650_SHA" \
    hardware/prebuilt/jcm33_bitcoiniii_dualalign_650_validated.bit | sha256sum --check
file hardware/prebuilt/jcm33_bitcoiniii_dualalign_650_validated.bit |
    grep -Fq 'COMPRESS=FALSE'
grep -Fq "$EXPECTED_JCM33_BIT_650_SHA" \
    research/jcm33_dualalign_btc3_650/PREBUILT_SHA256.txt

EXPECTED_JCM33_ROLLBACK_587P5_SHA='2abff6fc716bdea86d7c88865e07dcd380a89564f9267654910b5931a3f2f85b'
printf '%s  %s\n' "$EXPECTED_JCM33_ROLLBACK_587P5_SHA" \
    research/jcm33_dualalign_btc3_650/qualified_587p5/jcm33_dualalign_bscan_587p5.bit | sha256sum --check
grep -Fq 'accepted_A=1181' evidence/jcm33_bitcoiniii_dualalign_650/soak-60m-summary.txt
grep -Fq 'accepted_B=1187' evidence/jcm33_bitcoiniii_dualalign_650/soak-60m-summary.txt
grep -Fq 'hardware_software_mismatches=0' evidence/jcm33_bitcoiniii_dualalign_650/soak-60m-summary.txt
grep -Fq 'FINAL SETUP WNS: 0.010 ns' evidence/jcm33_bitcoiniii_dualalign_650/timing-summary.txt
grep -Fq 'FINAL HOLD  WHS: 0.010 ns' evidence/jcm33_bitcoiniii_dualalign_650/timing-summary.txt

grep -Fq "$EXPECTED_BIT_525_SHA" start.sh
grep -Fq "$EXPECTED_BIT_650_SHA" start.sh
grep -Fq "$EXPECTED_BIT_550_SHA" start.sh
grep -Fq -- '--qualified-650' start.sh
grep -Fq -- '--experimental-550' start.sh
grep -Fq 'readonly VERSION="0.2.0-rc1"' start.sh
grep -Fq '/sys/bus/usb/drivers/ftdi_sio/unbind' start.sh
grep -Fq 'cd "$STATE_DIR"' start.sh
grep -Fq ') 9>&-' start.sh
grep -Fq 'python3 -u "$MINER" 9>&-' start.sh
grep -Fq "$EXPECTED_BIT_525_SHA" start-btc3.sh
grep -Fq "$EXPECTED_BIT_650_SHA" start-btc3.sh
grep -Fq -- '--qualified-650' start-btc3.sh
grep -Fq 'readonly VERSION="0.2.0-rc1"' start-btc3.sh

EXPECTED_RUNTIME_SHA='6578399d1b1d000e46223ee7aef256e1bf081b8540f512261e6b9b06a376322b'
printf '%s  %s\n' "$EXPECTED_RUNTIME_SHA" \
    runtime/fjar_bridge.py | sha256sum --check
grep -Fq 'fk33_fjar_bscan_525.bit' runtime/start-sqrl-fleet.sh
grep -Fq 'fk33_native_bscan_650_validated.bit' runtime/start-sqrl-fleet.sh
grep -Fq 'FJAR_FLEET_BITSTREAM' runtime/start-sqrl-fleet.sh
grep -Fq "$EXPECTED_BIT_650_SHA" runtime/start-sqrl-fleet.sh
grep -Fq 'FJAR_FLEET_BITSTREAM=%s' install.sh

for CLOCK in 500 525; do
    BIT="hardware/prebuilt/fk33_fjar_bscan_${CLOCK}.bit"
    TIMING="hardware/reports/fk33_fjar_bscan_${CLOCK}_timing.rpt"
    ROUTE="hardware/reports/fk33_fjar_bscan_${CLOCK}_route_status.rpt"

    test -s "$BIT"
    grep -Fq 'COMPRESS=FALSE' <(file "$BIT")
    grep -Fq 'All user specified timing constraints are met.' "$TIMING"
    grep -Eq '# of nets with routing errors[^:]*:[[:space:]]+0' "$ROUTE"
done

EXPECTED_BRIDGE_SHA='8c7230f0bf586e9297dc0e568bd19278aeeb7cff8dbb3dde150811f11393218a'
printf '%s  %s\n' "$EXPECTED_BRIDGE_SHA" \
    third_party/sqrl/sqrl_bridge_rawjtag_coe | sha256sum --check
file third_party/sqrl/sqrl_bridge_rawjtag_coe |
    grep -Eq 'ELF 64-bit.*x86-64'

mapfile -t BRIDGES < <(
    find . -path './.git' -prune -o -type f -name 'sqrl_bridge*' -print | sort
)
EXPECTED_BRIDGES=(
    ./research/jcm33_dualalign_btc3_525/sqrl_bridge_rawjtag_coe_jcm33_xvc
    ./research/jcm33_dualalign_btc3_550/sqrl_bridge_rawjtag_coe_jcm33_xvc
    ./research/jcm33_dualalign_btc3_650/sqrl_bridge_rawjtag_coe_jcm33_xvc
    ./third_party/sqrl/sqrl_bridge_rawjtag_coe
)
if ! diff -u \
    <(printf '%s\n' "${EXPECTED_BRIDGES[@]}") \
    <(printf '%s\n' "${BRIDGES[@]}"); then
    printf 'Unexpected SQRL bridge artifact set.\n' >&2
    exit 1
fi

EXPECTED_JCM33_BRIDGE_SHA='fd1a550af5eb5dab475071a8f08f181c0b0d308233cbca805c52e3a96f342141'
printf '%s  %s\n' "$EXPECTED_JCM33_BRIDGE_SHA" \
    research/jcm33_dualalign_btc3_525/sqrl_bridge_rawjtag_coe_jcm33_xvc | sha256sum --check
file research/jcm33_dualalign_btc3_525/sqrl_bridge_rawjtag_coe_jcm33_xvc |
    grep -Eq 'ELF 64-bit.*x86-64'
printf '%s  %s\n' "$EXPECTED_JCM33_BRIDGE_SHA" \
    research/jcm33_dualalign_btc3_550/sqrl_bridge_rawjtag_coe_jcm33_xvc | sha256sum --check
file research/jcm33_dualalign_btc3_550/sqrl_bridge_rawjtag_coe_jcm33_xvc |
    grep -Eq 'ELF 64-bit.*x86-64'
printf '%s  %s\n' "$EXPECTED_JCM33_BRIDGE_SHA" \
    research/jcm33_dualalign_btc3_650/sqrl_bridge_rawjtag_coe_jcm33_xvc | sha256sum --check
file research/jcm33_dualalign_btc3_650/sqrl_bridge_rawjtag_coe_jcm33_xvc |
    grep -Eq 'ELF 64-bit.*x86-64'

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
    'rmann|Host[[:space:]]*:[[:space:]]*RGB|153300000[0-9]{3}|153300001064' \
    . --binary-files=without-match --exclude-dir=.git --exclude=.git \
    --exclude=SHA256SUMS --exclude=verify-release.sh; then
    printf 'Private identifier audit failed.\n' >&2
    exit 1
fi

printf '\nRelease verification passed.\n'
