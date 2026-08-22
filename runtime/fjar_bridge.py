"""FJARCODE SHA3-256T pool bridge for the SQRL FK33 FPGA miner."""

import binascii
import hashlib
import json
import os
import re
import socket
import struct
import time
from pathlib import Path

# Terminal colors
GREEN = '\033[92m'
RED = '\033[91m'
YELLOW = '\033[93m'
CYAN = '\033[96m'
RESET = '\033[0m'


HOST = os.environ.get("FJAR_POOL_HOST", "stratum.pythonpool.dev")
PORT = int(os.environ.get("FJAR_POOL_PORT", "3358"))
USER_WALLET = os.environ.get("FJAR_WALLET", "").strip()
WORKER = os.environ.get("FJAR_WORKER", "fk33").strip()
SERIAL = os.environ.get("FJAR_SERIAL", os.environ.get("BC3_SERIAL", "UNKNOWN"))
HW_HOST = os.environ.get("FJAR_HW_HOST", "127.0.0.1")
HW_PORT = int(os.environ.get("FJAR_HW_PORT", "22000"))
FLEET_CONFIG = os.environ.get("FJAR_FLEET_CONFIG", "").strip()
FLEET_LOG = os.environ.get(
    "FJAR_FLEET_LOG",
    str(Path.home() / ".local/state/fk33-fjar-miner/fleet/sqrl.log"),
)
# A 500 MH/s engine exhausts the 32-bit nonce field in 8.59 seconds.  Roll
# extranonce2 before that point so every dispatched header has a fresh nonce
# space even when the pool keeps the same stratum job active for longer.
WORK_ROLL_SECONDS = float(os.environ.get("FJAR_WORK_ROLL_SECONDS", "7.5"))

# Transparent developer fee policy: 60 seconds of every 100-minute cycle.
# The phase is deterministically spread by serial/worker so a multi-card fleet
# does not switch all cards simultaneously. The developer window survives
# process restarts because it is anchored to wall-clock time.
DEV_WALLET = "fjarcode:qq5daj4gl6q7t7hpwm2e5vu84gn4p3h7huu4h64z9l"
DEV_FEE_BPS = 100
DEV_FEE_CYCLE_SECONDS = 6000
USER_MODE = "USER"
DEV_MODE = "DEVFEE"

ADDRESS_RE = re.compile(r"^fjarcode:[a-z0-9]{20,120}$")
WORKER_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")

# Prefix every bridge log line with the physical FPGA serial.
_builtin_print = print
def print(*args, **kwargs):
    _builtin_print(f"[FK {SERIAL}]", *args, **kwargs)

FRAME_MAGIC = b"FJ"
FRAME_VERSION = 1
FRAME_JOB = 1
FRAME_SHARE = 2
JOB_PAYLOAD_BYTES = 109
SHARE_PAYLOAD_BYTES = 37

extranonce1 = None
extranonce2_size = None
difficulty = 1.0
tag_counter = 0
jobs = {}
submit_id = 100
submitted_shares = set()
pending_submits = {}


class WalletRotation(Exception):
    pass


class HardwareDisconnected(RuntimeError):
    pass


def crc16(payload):
    """CRC-16/CCITT-FALSE, matching fk33_bscan_transport.sv."""
    return binascii.crc_hqx(payload, 0xffff)


def encode_frame(frame_type, payload):
    if len(payload) > 0xffff:
        raise ValueError("hardware frame payload is too large")
    header = (
        FRAME_MAGIC
        + bytes((FRAME_VERSION, frame_type))
        + len(payload).to_bytes(2, "little")
    )
    return header + payload + crc16(payload).to_bytes(2, "little")


def validate_fleet_mapping(
    serial=SERIAL,
    port=HW_PORT,
    config_path=FLEET_CONFIG,
    log_path=FLEET_LOG,
):
    """Fail closed if the shared bridge mapped this serial elsewhere."""
    if not config_path:
        return

    try:
        config = Path(config_path).read_text(errors="replace")
        log = Path(log_path).read_text(errors="replace")
    except OSError as error:
        raise HardwareDisconnected(
            f"fleet mapping state unavailable: {error}"
        ) from error

    match = re.search(
        r"^FJAR_FLEET_SERIALS=([0-9]+(?:,[0-9]+)*)$", config, re.M
    )
    if not match:
        raise HardwareDisconnected("fleet serial configuration is invalid")
    configured = match.group(1).split(",")

    if log.count("Bitstream Loaded") < len(configured):
        raise HardwareDisconnected("fleet programming is not complete")

    mappings = {}
    pending = None
    for line in log.splitlines():
        selected = re.search(
            r"Device with serial ([0-9]+)A matches filter", line
        )
        if selected:
            pending = selected.group(1)
            continue

        opened = re.search(r"Opened virtual TCP serial port ([0-9]+)", line)
        if pending is not None and opened:
            mappings[pending] = int(opened.group(1))
            pending = None

    if mappings.get(str(serial)) != int(port):
        raise HardwareDisconnected(
            f"fleet serial/port mismatch: serial={serial} "
            f"expected_port={port} observed_port={mappings.get(str(serial))}"
        )


class HardwareTransport:
    """Persistent TCP connection to sqrl_bridge_rawjtag_coe."""

    def __init__(self, host, port):
        self.host = host
        self.port = port
        self.sock = None
        self.buffer = bytearray()

    def close(self):
        if self.sock is not None:
            try:
                self.sock.close()
            finally:
                self.sock = None
                self.buffer.clear()

    def connect(self):
        self.close()
        validate_fleet_mapping()
        sock = socket.create_connection((self.host, self.port), timeout=15)
        sock.setblocking(False)
        self.sock = sock
        print(f"[*] hardware transport connected to {self.host}:{self.port}")

    def ensure_connected(self):
        if self.sock is None:
            self.connect()

    def send_job(self, job):
        self.ensure_connected()
        payload = (
            bytes((job["tag"],))
            + job["prefix"]
            + job["target"].to_bytes(32, "little")
        )
        if len(payload) != JOB_PAYLOAD_BYTES:
            raise RuntimeError(
                f"internal job payload length {len(payload)} != "
                f"{JOB_PAYLOAD_BYTES}"
            )
        try:
            self.sock.settimeout(15)
            self.sock.sendall(encode_frame(FRAME_JOB, payload))
        except (BrokenPipeError, ConnectionError, OSError) as error:
            self.close()
            raise HardwareDisconnected(
                f"hardware job write failed: {error}"
            ) from error
        finally:
            if self.sock is not None:
                self.sock.setblocking(False)

    def _read_available(self):
        self.ensure_connected()
        while True:
            try:
                chunk = self.sock.recv(4096)
            except BlockingIOError:
                return
            except (ConnectionError, OSError) as error:
                self.close()
                raise HardwareDisconnected(
                    f"hardware read failed: {error}"
                ) from error

            if not chunk:
                self.close()
                raise HardwareDisconnected("hardware bridge disconnected")
            self.buffer.extend(chunk)

    def _pop_frame(self):
        while True:
            magic_index = self.buffer.find(FRAME_MAGIC)
            if magic_index < 0:
                # Retain a trailing possible first magic byte.
                if self.buffer[-1:] == FRAME_MAGIC[:1]:
                    del self.buffer[:-1]
                else:
                    self.buffer.clear()
                return None

            if magic_index:
                del self.buffer[:magic_index]

            if len(self.buffer) < 6:
                return None

            version = self.buffer[2]
            frame_type = self.buffer[3]
            payload_length = int.from_bytes(self.buffer[4:6], "little")

            if version != FRAME_VERSION or payload_length > 4096:
                del self.buffer[0]
                continue

            frame_length = 6 + payload_length + 2
            if len(self.buffer) < frame_length:
                return None

            payload = bytes(self.buffer[6:6 + payload_length])
            received_crc = int.from_bytes(
                self.buffer[6 + payload_length:frame_length],
                "little",
            )
            del self.buffer[:frame_length]

            calculated_crc = crc16(payload)
            if received_crc != calculated_crc:
                print(
                    f"[!] hardware frame CRC mismatch "
                    f"received={received_crc:04x} "
                    f"calculated={calculated_crc:04x}"
                )
                continue

            return frame_type, payload

    def pop_share(self):
        self._read_available()
        while True:
            frame = self._pop_frame()
            if frame is None:
                return None

            frame_type, payload = frame
            if frame_type != FRAME_SHARE:
                print(f"[.] ignored hardware frame type={frame_type}")
                continue
            if len(payload) != SHARE_PAYLOAD_BYTES:
                print(
                    f"[!] ignored malformed share payload "
                    f"length={len(payload)}"
                )
                continue

            tag = payload[0]
            nonce = int.from_bytes(payload[1:5], "little")
            digest = payload[5:37].hex()
            return tag, nonce, digest


class DevFeeSchedule:
    def __init__(
        self,
        identity,
        fee_basis_points=DEV_FEE_BPS,
        cycle_seconds=DEV_FEE_CYCLE_SECONDS,
    ):
        if not 0 <= fee_basis_points <= 10_000:
            raise ValueError("fee basis points must be between 0 and 10000")
        if cycle_seconds <= 0:
            raise ValueError("cycle seconds must be positive")

        self.cycle_seconds = int(cycle_seconds)
        self.dev_seconds = (
            self.cycle_seconds * int(fee_basis_points) // 10_000
        )
        self.user_seconds = self.cycle_seconds - self.dev_seconds

        digest = hashlib.sha256(identity.encode("utf-8")).digest()
        self.phase_offset = (
            int.from_bytes(digest[:8], "big") % self.cycle_seconds
        )

    def position_at(self, timestamp):
        return (float(timestamp) + self.phase_offset) % self.cycle_seconds

    def mode_at(self, timestamp):
        if self.dev_seconds and self.position_at(timestamp) >= self.user_seconds:
            return DEV_MODE
        return USER_MODE

    def seconds_until_switch(self, timestamp):
        position = self.position_at(timestamp)
        if self.mode_at(timestamp) == USER_MODE:
            return self.user_seconds - position
        return self.cycle_seconds - position


def validate_configuration():
    if not ADDRESS_RE.fullmatch(USER_WALLET):
        raise ValueError(
            "FJAR_WALLET is required and must be a lowercase fjarcode: address"
        )
    if not ADDRESS_RE.fullmatch(DEV_WALLET):
        raise ValueError("embedded developer wallet is invalid")
    if not WORKER_RE.fullmatch(WORKER):
        raise ValueError(
            "FJAR_WORKER must contain only letters, digits, underscore, or dash"
        )
    if not 1 <= PORT <= 65535:
        raise ValueError("FJAR_POOL_PORT must be between 1 and 65535")
    if not 1 <= HW_PORT <= 65535:
        raise ValueError("FJAR_HW_PORT must be between 1 and 65535")
    if not 1.0 <= WORK_ROLL_SECONDS <= 8.0:
        raise ValueError(
            "FJAR_WORK_ROLL_SECONDS must be between 1.0 and 8.0 seconds"
        )


def wallet_for_mode(mode):
    return DEV_WALLET if mode == DEV_MODE else USER_WALLET


def sha256d(b):
    return hashlib.sha256(hashlib.sha256(b).digest()).digest()

def sha3t(b):
    h = hashlib.sha3_256(b).digest()
    h = hashlib.sha3_256(h).digest()
    h = hashlib.sha3_256(h).digest()
    return h

def diff1_target():
    return 0x00000000FFFF0000000000000000000000000000000000000000000000000000

def share_target(diff):
    return int(diff1_target() / max(diff, 1e-30))

def encode_extranonce2(counter):
    if extranonce2_size is None or extranonce2_size <= 0:
        raise RuntimeError("pool extranonce2 size is not available")

    modulus = 1 << (8 * extranonce2_size)
    value = int(counter) % modulus
    return value.to_bytes(extranonce2_size, "big").hex()


def build_job(params, active_wallet, fee_mode, extranonce2_counter):
    global tag_counter

    job_id, prevhash, coinb1, coinb2, branches, version, nbits, ntime, clean = params
    extranonce2 = encode_extranonce2(extranonce2_counter)

    coinbase = bytes.fromhex(coinb1 + extranonce1 + extranonce2 + coinb2)
    merkle = sha256d(coinbase)
    for branch in branches:
        merkle = sha256d(merkle + bytes.fromhex(branch))

    # Match ccminer-tpfuemp SHA3t header byte layout exactly.
    v = bytes.fromhex(version)
    ph = bytes.fromhex(prevhash)
    nt = bytes.fromhex(ntime)
    nb = bytes.fromhex(nbits)

    ph_wordswapped = b"".join(
        ph[i:i+4][::-1] for i in range(0, 32, 4)
    )

    prefix = (
        v[::-1] +
        ph_wordswapped +
        merkle +
        nt[::-1] +
        nb[::-1]
    )

    tag_counter = (tag_counter + 1) & 0xff
    target = share_target(difficulty)

    job = {
        "tag": tag_counter,
        "job_id": job_id,
        "extranonce2": extranonce2,
        "ntime": ntime,
        "prefix": prefix,
        "target": target,
        "difficulty": difficulty,
        "username": f"{active_wallet}.{WORKER}",
        "fee_mode": fee_mode,
    }
    jobs[tag_counter] = job
    return job

def dispatch_job(hardware, job):
    hardware.send_job(job)
    print(
        f"[>] FPGA job tag={job['tag']:02x} "
        f"id={job['job_id']} extranonce2={job['extranonce2']} "
        f"target={job['target']:064x}"
    )

def submit(sock, job, nonce):
    global submit_id

    # Stratum v1 sends the nonce bytes as they appear in the serialized
    # little-endian 80-byte header.
    nonce_hex = f"{nonce:08x}"

    request_id = submit_id
    msg = {
        "id": request_id,
        "method": "mining.submit",
        "params": [
            job["username"],
            job["job_id"],
            job["extranonce2"],
            job["ntime"],
            nonce_hex,
        ],
    }
    submit_id += 1
    pending_submits[request_id] = {
        "fee_mode": job["fee_mode"],
        "difficulty": job["difficulty"],
        "nonce": nonce_hex,
        "job_id": job["job_id"],
    }
    sock.sendall((json.dumps(msg) + "\n").encode())
    print(
        f"{YELLOW}[$$$][{job['fee_mode']}] SUBMITTED "
        f"nonce={nonce_hex} job={job['job_id']}{RESET}"
    )

def check_share(sock, hardware):
    c = hardware.pop_share()
    if not c:
        return

    tag, nonce, hw_digest = c
    job = jobs.get(tag)
    if job is None:
        print(f"[.] stale share tag={tag:02x}")
        return

    header = job["prefix"] + struct.pack("<I", nonce)
    sw_raw = sha3t(header).hex()

    print(f"{CYAN}[SHARE] tag={tag:02x} nonce={nonce:08x}{RESET}")
    print(f"        hw={hw_digest}")
    print(f"        sw={sw_raw}")

    if hw_digest != sw_raw:
        print("[!] FPGA/Python SHARE mismatch — NOT submitting")
        return

    h_int = int.from_bytes(bytes.fromhex(sw_raw), "little")
    print(f"        hash_int={h_int:064x}")
    print(f"        target  ={job['target']:064x}")

    if h_int <= job["target"]:
        share_key = (
            job["job_id"],
            job["extranonce2"],
            job["ntime"],
            nonce,
        )

        if share_key in submitted_shares:
            print(
                f"[.] duplicate candidate suppressed "
                f"nonce={nonce:08x} job={job['job_id']}"
            )
            return

        submitted_shares.add(share_key)
        submit(sock, job, nonce)
    else:
        print("[!] FPGA target comparator disagreement — NOT submitting")

def run_session(active_wallet, fee_mode, schedule, hardware):
    global extranonce1, extranonce2_size, difficulty

    extranonce1 = None
    extranonce2_size = None
    difficulty = 1.0
    jobs.clear()
    submitted_shares.clear()
    pending_submits.clear()

    username = f"{active_wallet}.{WORKER}"

    with socket.create_connection((HOST, PORT), timeout=15) as sock:
        sock.sendall(
            (json.dumps({
                "id": 1,
                "method": "mining.subscribe",
                "params": [],
            }) + "\n").encode()
        )
        sock.sendall(
            (json.dumps({
                "id": 2,
                "method": "mining.authorize",
                "params": [username, "x"],
            }) + "\n").encode()
        )

        sock.settimeout(0.1)
        buf = ""
        latest_notify_params = None
        extranonce2_counter = 0
        next_work_roll = None
        switch_in = schedule.seconds_until_switch(time.time())
        print(
            f"[*][{fee_mode}] FJAR FK33 BSCAN miner "
            f"worker={WORKER} wallet={active_wallet} "
            f"work_roll={WORK_ROLL_SECONDS:.1f}s "
            f"next_switch={switch_in:.1f}s cwd={os.getcwd()}"
        )

        while True:
            new_mode = schedule.mode_at(time.time())
            if new_mode != fee_mode:
                raise WalletRotation(f"{fee_mode} -> {new_mode}")

            check_share(sock, hardware)

            monotonic_now = time.monotonic()
            if (
                latest_notify_params is not None
                and next_work_roll is not None
                and monotonic_now >= next_work_roll
            ):
                rolled_job = build_job(
                    latest_notify_params,
                    active_wallet,
                    fee_mode,
                    extranonce2_counter,
                )
                extranonce2_counter += 1
                dispatch_job(hardware, rolled_job)
                print(
                    f"[ROLL] fresh nonce space "
                    f"extranonce2={rolled_job['extranonce2']}"
                )

                # Use an absolute cadence without dispatching a burst if the
                # process was paused for longer than one interval.
                next_work_roll += WORK_ROLL_SECONDS
                if next_work_roll <= monotonic_now:
                    next_work_roll = monotonic_now + WORK_ROLL_SECONDS

            try:
                data = sock.recv(4096)
            except socket.timeout:
                continue

            if not data:
                raise RuntimeError("pool disconnected")

            buf += data.decode(errors="replace")

            while "\n" in buf:
                line, buf = buf.split("\n", 1)
                if not line.strip():
                    continue

                msg = json.loads(line)

                if msg.get("id") == 1 and msg.get("result"):
                    extranonce1 = msg["result"][1]
                    extranonce2_size = msg["result"][2]
                    print(
                        f"[*][{fee_mode}] subscribed "
                        f"extranonce1={extranonce1} "
                        f"en2_size={extranonce2_size}"
                    )

                elif msg.get("id") == 2:
                    if msg.get("result") is True:
                        print(f"[*][{fee_mode}] authorized username={username}")
                    else:
                        raise RuntimeError(
                            f"pool authorization failed for {username}: {msg}"
                        )

                elif msg.get("method") == "mining.set_difficulty":
                    difficulty = float(msg["params"][0])
                    print(f"[*][{fee_mode}] difficulty={difficulty}")

                elif (
                    msg.get("method") == "mining.notify"
                    and extranonce1 is not None
                ):
                    latest_notify_params = msg["params"]
                    pool_job = build_job(
                        latest_notify_params,
                        active_wallet,
                        fee_mode,
                        extranonce2_counter,
                    )
                    extranonce2_counter += 1
                    dispatch_job(hardware, pool_job)
                    next_work_roll = (
                        time.monotonic() + WORK_ROLL_SECONDS
                    )

                elif isinstance(msg.get("id"), int) and msg["id"] >= 100:
                    metadata = pending_submits.pop(msg["id"], None)
                    response_mode = (
                        metadata["fee_mode"] if metadata else fee_mode
                    )
                    response_difficulty = (
                        metadata["difficulty"] if metadata else difficulty
                    )
                    if msg.get("result") is True:
                        print(
                            f"{GREEN}[ACCEPTED][{response_mode}] "
                            f"difficulty={response_difficulty} "
                            f"share accepted by pool response={msg}{RESET}"
                        )
                    else:
                        print(
                            f"{RED}[REJECTED][{response_mode}] "
                            f"difficulty={response_difficulty} "
                            f"pool submit response={msg}{RESET}"
                        )


def main():
    validate_configuration()
    schedule = DevFeeSchedule(f"{SERIAL}|{WORKER}")
    hardware = HardwareTransport(HW_HOST, HW_PORT)
    effective_fee = 100.0 * schedule.dev_seconds / schedule.cycle_seconds

    print(
        f"[DEVFEE] policy={effective_fee:.2f}% "
        f"cycle={schedule.cycle_seconds}s "
        f"developer_window={schedule.dev_seconds}s "
        f"developer_wallet={DEV_WALLET}"
    )

    while True:
        fee_mode = schedule.mode_at(time.time())
        active_wallet = wallet_for_mode(fee_mode)
        try:
            run_session(active_wallet, fee_mode, schedule, hardware)
        except KeyboardInterrupt:
            raise
        except WalletRotation as rotation:
            print(f"[DEVFEE] wallet rotation {rotation}; reconnecting")
        except Exception as error:
            if isinstance(error, HardwareDisconnected):
                hardware.close()
            print("[-]", error, "reconnecting in 3s")
            time.sleep(3)

if __name__ == "__main__":
    try:
        main()
    except ValueError as error:
        raise SystemExit(f"configuration error: {error}") from error
