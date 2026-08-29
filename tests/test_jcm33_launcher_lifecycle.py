import hashlib
import os
from pathlib import Path
import socket
import stat
import subprocess
import tempfile
import threading
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE_LAUNCHER = ROOT / "start-jcm33-btc3.sh"


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def unused_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


class PoolStub:
    def __init__(self, port):
        self.port = port
        self.stop_event = threading.Event()
        self.ready_event = threading.Event()
        self.thread = threading.Thread(target=self.run, daemon=True)

    def run(self):
        with socket.socket() as server:
            server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            server.bind(("127.0.0.1", self.port))
            server.listen()
            server.settimeout(0.1)
            self.ready_event.set()
            while not self.stop_event.is_set():
                try:
                    connection, _ = server.accept()
                except TimeoutError:
                    continue
                connection.close()

    def __enter__(self):
        self.thread.start()
        if not self.ready_event.wait(timeout=2):
            raise RuntimeError("isolated pool stub did not start")
        return self

    def __exit__(self, *_):
        self.stop_event.set()
        self.thread.join(timeout=2)


class Jcm33LauncherLifecycleTests(unittest.TestCase):
    def test_isolated_start_status_and_confirmed_rollback(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            package = root / "research" / "jcm33_dualalign_btc3_650"
            prebuilt = root / "hardware" / "prebuilt"
            rollback_dir = package / "qualified_587p5"
            reports = package / "reports"
            state = root / "state"
            test_bin = root / "test-bin"
            for directory in (prebuilt, rollback_dir, reports, test_bin):
                directory.mkdir(parents=True, exist_ok=True)

            bitstream = prebuilt / "jcm33_bitcoiniii_dualalign_650_validated.bit"
            rollback = rollback_dir / "jcm33_dualalign_bscan_587p5.bit"
            bridge = package / "sqrl_bridge_rawjtag_coe_jcm33_xvc"
            miner = package / "jcm33_btc3_dual_miner.py"
            launcher = root / "start-jcm33-btc3.sh"

            bitstream.write_bytes(b"isolated-qualified-650")
            rollback.write_bytes(b"isolated-qualified-587p5")
            (reports / "timing-gate.pass").write_text("TIMING GATE PASS\n")

            bridge.write_text(
                """#!/usr/bin/env python3
import signal
import socket
import sys
import time

args = sys.argv[1:]
log = args[args.index('-f') + 1]
programming = '-b' in args
running = True

def stop(*_):
    global running
    running = False

signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)

if programming:
    with open(log, 'a', encoding='utf-8') as handle:
        handle.write('SQRL JTAG Board 0 Device 0 Bitstream Loaded\\n')
        handle.write('SQRL JTAG Board 0 Device 1 Bitstream Loaded\\n')
        handle.flush()
    while running:
        time.sleep(0.05)
else:
    port = int(args[args.index('-j') + 1])
    with socket.socket() as server:
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind(('127.0.0.1', port))
        server.listen()
        server.settimeout(0.05)
        while running:
            try:
                connection, _ = server.accept()
            except TimeoutError:
                continue
            connection.close()
"""
            )
            miner.write_text(
                """#!/usr/bin/env python3
import os
import signal
import time

if os.environ.get('JCM33_SELF_TEST') == '1':
    print('SELFTEST PASS: isolated launcher miner')
    raise SystemExit(0)

running = True
def stop(*_):
    global running
    running = False

signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)
print('[*] XVC connected 127.0.0.1:2542 devices=2', flush=True)
while running:
    time.sleep(0.05)
"""
            )
            bridge.chmod(bridge.stat().st_mode | stat.S_IXUSR)
            miner.chmod(miner.stat().st_mode | stat.S_IXUSR)

            launcher_source = SOURCE_LAUNCHER.read_text()
            replacements = {
                "0eacb71eb4cb5f6a43f761d1af64dfe25c8fa22177974082742dc12d6f6cdcf1": sha256(bitstream),
                "2abff6fc716bdea86d7c88865e07dcd380a89564f9267654910b5931a3f2f85b": sha256(rollback),
                "fd1a550af5eb5dab475071a8f08f181c0b0d308233cbca805c52e3a96f342141": sha256(bridge),
                "1d64c8e7d2650e3733a26985f271779dbf5b36fea46e5c6ea7e6c605681c3593": sha256(miner),
            }
            for original, replacement in replacements.items():
                launcher_source = launcher_source.replace(original, replacement)
            launcher.write_text(launcher_source)
            launcher.chmod(launcher.stat().st_mode | stat.S_IXUSR)

            ping = test_bin / "ping"
            ping.write_text("#!/usr/bin/env bash\nexit 0\n")
            ping.chmod(ping.stat().st_mode | stat.S_IXUSR)

            ldd = test_bin / "ldd"
            ldd.write_text(
                "#!/usr/bin/env bash\n"
                "printf '%s\\n' 'libncurses.so.5 => /isolated/libncurses.so.5'\n"
                "printf '%s\\n' 'libtinfo.so.5 => /isolated/libtinfo.so.5'\n"
            )
            ldd.chmod(ldd.stat().st_mode | stat.S_IXUSR)

            ss = test_bin / "ss"
            ss.write_text(
                """#!/usr/bin/env python3
import os
import socket

port = int(os.environ['FAKE_XVC_PORT'])
try:
    with socket.create_connection(('127.0.0.1', port), timeout=0.05):
        pass
except OSError:
    raise SystemExit(0)
print(f'LISTEN 0 5 127.0.0.1:{port} 0.0.0.0:*')
"""
            )
            ss.chmod(ss.stat().st_mode | stat.S_IXUSR)

            base_port = unused_port()
            while base_port >= 65535:
                base_port = unused_port()
            xvc_port = unused_port()
            while xvc_port in {base_port, base_port + 1}:
                xvc_port = unused_port()
            pool_port = unused_port()
            while pool_port in {base_port, base_port + 1, xvc_port}:
                pool_port = unused_port()
            env = os.environ.copy()
            env["PATH"] = f"{test_bin}:{env['PATH']}"
            env["FAKE_XVC_PORT"] = str(xvc_port)
            common = [
                "--wallet",
                "bc1q0000000000000000000000000000000000000000",
                "--worker",
                "isolated-jcm33",
                "--carrier",
                "127.0.0.1",
                "--base-port",
                str(base_port),
                "--xvc-port",
                str(xvc_port),
                "--pool-host",
                "127.0.0.1",
                "--pool-port",
                str(pool_port),
                "--state-dir",
                str(state),
            ]

            with PoolStub(pool_port):
                start = subprocess.run(
                    [str(launcher), "start", *common],
                    cwd=root,
                    env=env,
                    check=False,
                    text=True,
                    capture_output=True,
                    timeout=30,
                )
                self.assertEqual(start.returncode, 0, start.stdout + start.stderr)
                self.assertIn("START PASS", start.stdout)

                status_result = subprocess.run(
                    [str(launcher), "status", "--state-dir", str(state)],
                    cwd=root,
                    env=env,
                    check=False,
                    text=True,
                    capture_output=True,
                    timeout=10,
                )
                self.assertEqual(
                    status_result.returncode,
                    0,
                    status_result.stdout + status_result.stderr,
                )
                self.assertIn("STATUS: RUNNING", status_result.stdout)
                self.assertIn("xvc=LISTENING", status_result.stdout)

                stop = subprocess.run(
                    [str(launcher), "stop", "--state-dir", str(state)],
                    cwd=root,
                    env=env,
                    check=False,
                    text=True,
                    capture_output=True,
                    timeout=30,
                )
                self.assertEqual(stop.returncode, 0, stop.stdout + stop.stderr)
                self.assertIn("STOP PASS", stop.stdout)
                self.assertTrue((state / "rollback.ok").exists())

                stopped = subprocess.run(
                    [str(launcher), "status", "--state-dir", str(state)],
                    cwd=root,
                    env=env,
                    check=False,
                    text=True,
                    capture_output=True,
                    timeout=10,
                )
                self.assertEqual(stopped.returncode, 1)
                self.assertIn("STATUS: STOPPED", stopped.stdout)
                self.assertIn("rollback_587p5=PASS", stopped.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
