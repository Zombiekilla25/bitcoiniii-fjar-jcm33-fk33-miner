"""FJARCODE SHA3-256T pool bridge for the SQRL FK33 FPGA miner."""

import hashlib
import json
import os
import re
import socket
import struct
import time

# Use colors only in an interactive terminal. Systemd log files remain plain.
USE_COLOR = os.isatty(1) and "NO_COLOR" not in os.environ
GREEN = '\033[92m' if USE_COLOR else ''
RED = '\033[91m' if USE_COLOR else ''
YELLOW = '\033[93m' if USE_COLOR else ''
CYAN = '\033[96m' if USE_COLOR else ''
RESET = '\033[0m' if USE_COLOR else ''


HOST = os.environ.get("FJAR_POOL_HOST", "stratum.pythonpool.dev")
PORT = int(os.environ.get("FJAR_POOL_PORT", "3358"))
USER_WALLET = os.environ.get("FJAR_WALLET", "").strip()
WORKER = os.environ.get("FJAR_WORKER", "fk33").strip()
SERIAL = os.environ.get("FJAR_SERIAL", "UNKNOWN").strip()

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

JOB_FILE = "job.txt"
CANDIDATE_FILE = "candidate.txt"

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
    if not HOST or any(character.isspace() for character in HOST):
        raise ValueError("FJAR_POOL_HOST must be a non-empty hostname")
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

def split_prefix(prefix):
    assert len(prefix) == 76
    v = int.from_bytes(prefix, "little")
    return (
        f"{v & ((1<<256)-1):064x}",
        f"{(v >> 256) & ((1<<256)-1):064x}",
        f"{(v >> 512) & ((1<<96)-1):024x}"
    )

def atomic_write(path, text):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        f.write(text)
    os.replace(tmp, path)

def build_job(params, active_wallet, fee_mode):
    global tag_counter

    job_id, prevhash, coinb1, coinb2, branches, version, nbits, ntime, clean = params
    extranonce2 = "00" * extranonce2_size

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
        "username": f"{active_wallet}.{WORKER}",
        "fee_mode": fee_mode,
    }
    jobs[tag_counter] = job
    return job

def dispatch_job(job):
    p0, p1, p2 = split_prefix(job["prefix"])
    atomic_write(
        JOB_FILE,
        f"{job['tag']:02x}\n"
        f"{p0}\n"
        f"{p1}\n"
        f"{p2}\n"
        f"{job['target']:064x}\n"
    )
    print(
        f"[>] FPGA job tag={job['tag']:02x} "
        f"id={job['job_id']} target={job['target']:064x}"
    )

def pop_share():
    try:
        with open(CANDIDATE_FILE, "r") as f:
            line = f.read().strip()
        if not line:
            return None
        os.remove(CANDIDATE_FILE)
        tag_s, nonce_s, digest = line.split(":")
        return int(tag_s, 16), int(nonce_s, 16), digest.lower()
    except FileNotFoundError:
        return None

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
        "nonce": nonce_hex,
        "job_id": job["job_id"],
    }
    sock.sendall((json.dumps(msg) + "\n").encode())
    print(
        f"{YELLOW}[$$$][{job['fee_mode']}] SUBMITTED "
        f"nonce={nonce_hex} job={job['job_id']}{RESET}"
    )

def check_share(sock):
    c = pop_share()
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

def run_session(active_wallet, fee_mode, schedule):
    global extranonce1, extranonce2_size, difficulty

    extranonce1 = None
    extranonce2_size = None
    difficulty = 1.0
    jobs.clear()
    submitted_shares.clear()
    pending_submits.clear()

    for p in [JOB_FILE, CANDIDATE_FILE]:
        try: os.remove(p)
        except FileNotFoundError: pass

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
        switch_in = schedule.seconds_until_switch(time.time())
        print(
            f"[*][{fee_mode}] FJAR FK33 80-pipe TOKEN3 350MHz "
            f"worker={WORKER} wallet={active_wallet} "
            f"next_switch={switch_in:.1f}s cwd={os.getcwd()}"
        )

        while True:
            new_mode = schedule.mode_at(time.time())
            if new_mode != fee_mode:
                raise WalletRotation(f"{fee_mode} -> {new_mode}")

            check_share(sock)

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
                    dispatch_job(
                        build_job(msg["params"], active_wallet, fee_mode)
                    )

                elif isinstance(msg.get("id"), int) and msg["id"] >= 100:
                    metadata = pending_submits.pop(msg["id"], None)
                    response_mode = (
                        metadata["fee_mode"] if metadata else fee_mode
                    )
                    if msg.get("result") is True:
                        print(
                            f"{GREEN}[ACCEPTED][{response_mode}] "
                            f"share accepted by pool response={msg}{RESET}"
                        )
                    else:
                        print(
                            f"{RED}[REJECTED][{response_mode}] "
                            f"pool submit response={msg}{RESET}"
                        )


def main():
    validate_configuration()
    schedule = DevFeeSchedule(f"{SERIAL}|{WORKER}")
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
            run_session(active_wallet, fee_mode, schedule)
        except KeyboardInterrupt:
            raise
        except WalletRotation as rotation:
            print(f"[DEVFEE] wallet rotation {rotation}; reconnecting")
        except Exception as error:
            print("[-]", error, "reconnecting in 3s")
            time.sleep(3)

if __name__ == "__main__":
    try:
        main()
    except ValueError as error:
        raise SystemExit(f"configuration error: {error}") from error
