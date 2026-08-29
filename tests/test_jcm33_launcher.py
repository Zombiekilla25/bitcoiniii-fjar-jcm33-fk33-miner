import hashlib
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
LAUNCHER = ROOT / "start-jcm33-btc3.sh"
DOC = ROOT / "docs" / "JCM33_PRODUCTION.md"
EXAMPLE = ROOT / "config-jcm33-btc3.env.example"
MINER = (
    ROOT
    / "research"
    / "jcm33_dualalign_btc3_650"
    / "jcm33_btc3_dual_miner.py"
)
BRIDGE = (
    ROOT
    / "research"
    / "jcm33_dualalign_btc3_650"
    / "sqrl_bridge_rawjtag_coe_jcm33_xvc"
)
BITSTREAM = (
    ROOT
    / "hardware"
    / "prebuilt"
    / "jcm33_bitcoiniii_dualalign_650_validated.bit"
)
ROLLBACK = (
    ROOT
    / "research"
    / "jcm33_dualalign_btc3_650"
    / "qualified_587p5"
    / "jcm33_dualalign_bscan_587p5.bit"
)


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


class Jcm33LauncherTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.launcher = LAUNCHER.read_text()
        cls.documentation = DOC.read_text()

    def test_help_and_version_are_offline(self):
        help_result = subprocess.run(
            [str(LAUNCHER), "--help"],
            cwd=ROOT,
            check=True,
            text=True,
            capture_output=True,
        )
        version_result = subprocess.run(
            [str(LAUNCHER), "--version"],
            cwd=ROOT,
            check=True,
            text=True,
            capture_output=True,
        )
        self.assertIn("doctor", help_result.stdout)
        self.assertIn("status", help_result.stdout)
        self.assertIn("logs", help_result.stdout)
        self.assertIn("stop", help_result.stdout)
        self.assertEqual(version_result.stdout.strip(), "jcm33-btc3 0.1.0-rc1")

    def test_invalid_wallet_fails_before_hardware(self):
        result = subprocess.run(
            [str(LAUNCHER), "doctor", "--wallet", "not-a-wallet", "--dry-run"],
            cwd=ROOT,
            check=False,
            text=True,
            capture_output=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("invalid operator wallet", result.stderr)

    def test_stopped_status_and_stop_are_hardware_free(self):
        with tempfile.TemporaryDirectory() as state_dir:
            status_result = subprocess.run(
                [str(LAUNCHER), "status", "--state-dir", state_dir],
                cwd=ROOT,
                check=False,
                text=True,
                capture_output=True,
            )
            stop_result = subprocess.run(
                [str(LAUNCHER), "stop", "--state-dir", state_dir],
                cwd=ROOT,
                check=True,
                text=True,
                capture_output=True,
            )
        self.assertEqual(status_result.returncode, 1)
        self.assertIn("STATUS: STOPPED", status_result.stdout)
        self.assertIn("accepted_A=0", status_result.stdout)
        self.assertIn("hardware_software_mismatches=0", status_result.stdout)
        self.assertIn("is not running", stop_result.stdout)

    def test_exact_qualified_artifact_hashes(self):
        expected = {
            BITSTREAM: "0eacb71eb4cb5f6a43f761d1af64dfe25c8fa22177974082742dc12d6f6cdcf1",
            ROLLBACK: "2abff6fc716bdea86d7c88865e07dcd380a89564f9267654910b5931a3f2f85b",
            BRIDGE: "fd1a550af5eb5dab475071a8f08f181c0b0d308233cbca805c52e3a96f342141",
            MINER: "1d64c8e7d2650e3733a26985f271779dbf5b36fea46e5c6ea7e6c605681c3593",
        }
        for path, expected_hash in expected.items():
            with self.subTest(path=path):
                self.assertEqual(sha256(path), expected_hash)
                self.assertIn(expected_hash, self.launcher)

    def test_production_requires_both_devices_and_rolls_back(self):
        self.assertIn("Device 0 Bitstream Loaded", self.launcher)
        self.assertIn("Device 1 Bitstream Loaded", self.launcher)
        self.assertIn("restore_qualified_587p5", self.launcher)
        self.assertIn("if ((PROGRAM_ATTEMPTED)); then", self.launcher)
        self.assertIn("hardware/software digest mismatch detected", self.launcher)
        self.assertIn("STOP PASS", self.launcher)

    def test_process_control_is_targeted(self):
        self.assertIn('grep -F -- "-c $CARRIER"', self.launcher)
        self.assertIn("unrelated USB/FK bridge processes are preserved", self.launcher)
        self.assertIn("pid_cmdline_contains", self.launcher)
        self.assertNotIn("pkill", self.launcher)
        self.assertNotIn("killall", self.launcher)

    def test_launcher_never_passes_a_voltage_option(self):
        invocation_lines = [
            line for line in self.launcher.splitlines() if '"$BRIDGE"' in line
        ]
        self.assertTrue(invocation_lines)
        for line in invocation_lines:
            with self.subTest(line=line):
                self.assertNotRegex(line, r"(^|\s)-[vV](\s|$)")

    def test_configuration_is_operator_specific(self):
        example = EXAMPLE.read_text()
        self.assertIn("bc1qYOUR_BITCOINIII_ADDRESS", example)
        self.assertNotIn(
            "bc1qwcusej0umav5dw9k9f6cuy6mhzsdj9su4rayqu", example
        )
        self.assertIn("chmod 600", example)

    def test_documentation_marks_launcher_as_release_candidate(self):
        self.assertIn("release-candidate", self.documentation)
        self.assertIn("six-hour burn-in", self.documentation)
        self.assertIn("24-hour unattended soak", self.documentation)
        self.assertIn("sudden host power loss", self.documentation)


if __name__ == "__main__":
    unittest.main(verbosity=2)
