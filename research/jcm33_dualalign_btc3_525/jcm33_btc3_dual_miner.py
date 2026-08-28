"""BitcoinIII SHA3-256T miner for both FPGAs on one JCM33 carrier."""

import binascii
import hashlib
import json
import os
import re
import socket
import struct
import time

from jcm33_ir_lane_calibration import (
    EXPECTED_IDCODE,
    IDLE_CLOCKS,
    IR_CELL_BITS,
    TapProgram,
    USER1,
    USER2,
    XVC,
    bits_for,
    extract_valid_bytes,
)

# Terminal colors
GREEN = '\033[92m'
RED = '\033[91m'
YELLOW = '\033[93m'
CYAN = '\033[96m'
RESET = '\033[0m'


HOST = os.environ.get("BTC3_POOL_HOST", "stratum.pythonpool.dev")
PORT = int(os.environ.get("BTC3_POOL_PORT", "3357"))
USER_WALLET = os.environ.get("BTC3_WALLET", "").strip()
WORKER = os.environ.get("BTC3_WORKER", "jcm33-dual").strip()
SERIAL = os.environ.get("BTC3_SERIAL", "JCM33-DUAL")
XVC_HOST = os.environ.get("JCM33_XVC_HOST", "127.0.0.1")
XVC_PORT = int(os.environ.get("JCM33_XVC_PORT", "2542"))
# A 500 MH/s engine exhausts the 32-bit nonce field in 8.59 seconds.  Roll
# extranonce2 before that point so every dispatched header has a fresh nonce
# space even when the pool keeps the same stratum job active for longer.
WORK_ROLL_SECONDS = float(os.environ.get("BTC3_WORK_ROLL_SECONDS", "7.5"))

# The BTC3 canary has no developer-wallet rotation.  It submits every share to
# the address supplied by the operator.  Keep the scheduling machinery at 0%
# so the proven worker loop and frame protocol remain unchanged.
DEV_WALLET = USER_WALLET
DEV_FEE_BPS = 0
DEV_FEE_CYCLE_SECONDS = 6000
USER_MODE = "USER"
DEV_MODE = "DEVFEE"

ADDRESS_RE = re.compile(r"^bc1q[023456789acdefghjklmnpqrstuvwxyz]{20,86}$")
WORKER_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")

# Prefix every miner log line with the carrier identity.
_builtin_print = print
def print(*args, **kwargs):
    _builtin_print(f"[JCM33 {SERIAL}]", *args, **kwargs)

FRAME_MAGIC = b"FJ"
FRAME_VERSION = 1
FRAME_JOB = 1
FRAME_SHARE = 2
JOB_PAYLOAD_BYTES = 109
SHARE_PAYLOAD_BYTES = 37
LANE_COUNT = 2
READ_SCANS = 160

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


def job_wire_frame(job):
    payload = (
        bytes((job["tag"],))
        + job["prefix"]
        + job["target"].to_bytes(32, "little")
    )
    if len(payload) != JOB_PAYLOAD_BYTES:
        raise RuntimeError(
            f"internal job payload length {len(payload)} != {JOB_PAYLOAD_BYTES}"
        )
    return encode_frame(FRAME_JOB, payload)


def build_per_byte_write(selected_lane, frame):
    """Build the test02-proven tailpad transport for one complete frame."""
    program = TapProgram()
    program.reset_to_idle()
    program.set_ir_lane(LANE_COUNT, selected_lane, USER2)
    for byte in frame:
        program.scan_dr(bits_for(byte, 8) + [0])
    program.add([0] * IDLE_CLOCKS)
    program.reset_to_idle()
    return program


def build_lane_read(selected_lane):
    program = TapProgram()
    program.reset_to_idle()
    program.set_ir_lane(LANE_COUNT, selected_lane, USER1)
    for _ in range(READ_SCANS):
        program.scan_dr([0] * (LANE_COUNT + 8), record_read=True)
    program.reset_to_idle()
    return program


def concatenate_programs(*programs):
    combined = TapProgram()
    for program in programs:
        combined.add(program.tms, program.tdi)
    return combined


class HardwareTransport:
    """Raw-XVC transport for two independently aligned JCM33 USER lanes."""

    def __init__(self, host, port):
        self.host = host
        self.port = port
        self.xvc = None
        self.max_bits = None
        self.buffers = {"A": bytearray(), "B": bytearray()}

    def close(self):
        if self.xvc is not None:
            try:
                self.xvc.close()
            finally:
                self.xvc = None
                self.max_bits = None
                for buffer in self.buffers.values():
                    buffer.clear()

    def connect(self):
        self.close()
        xvc = None
        try:
            xvc = XVC(self.host, self.port, 15.0)
            info, max_bits = xvc.getinfo()
            tck = xvc.settck(1000)
            idcodes, _ = xvc.scan_reset_idcodes()
            total_ir_bits, _, _ = xvc.measure_ir_delay()
        except Exception:
            if xvc is not None:
                try:
                    xvc.close()
                except Exception:
                    pass
            raise
        if idcodes != [EXPECTED_IDCODE, EXPECTED_IDCODE]:
            xvc.close()
            raise HardwareDisconnected(
                "unexpected JTAG chain: "
                + ",".join(f"0x{value:08x}" for value in idcodes)
            )
        if total_ir_bits != LANE_COUNT * IR_CELL_BITS:
            xvc.close()
            raise HardwareDisconnected(
                f"expected 12 IR bits, measured {total_ir_bits}"
            )
        self.xvc = xvc
        self.max_bits = max_bits
        print(
            f"[*] XVC connected {self.host}:{self.port} info={info} "
            f"tck_ns={tck} devices=2 ir_bits={total_ir_bits}"
        )

    def ensure_connected(self):
        if self.xvc is None:
            self.connect()

    def send_job_pair(self, job_a, job_b):
        """Send independent A then B frames in one atomic XVC request."""
        self.ensure_connected()
        program_a = build_per_byte_write(0, job_wire_frame(job_a))
        program_b = build_per_byte_write(1, job_wire_frame(job_b))
        combined = concatenate_programs(program_a, program_b)
        if len(combined.tms) > self.max_bits:
            raise HardwareDisconnected(
                f"paired job transaction {len(combined.tms)} exceeds "
                f"XVC limit {self.max_bits}"
            )
        try:
            self.xvc.shift(combined.tms, combined.tdi)
        except (OSError, RuntimeError, ValueError) as error:
            self.close()
            raise HardwareDisconnected(
                f"paired hardware job write failed: {error}"
            ) from error

    def _read_lane(self, lane_name, selected_lane):
        self.ensure_connected()
        program = build_lane_read(selected_lane)
        if len(program.tms) > self.max_bits:
            raise HardwareDisconnected(
                f"share read transaction {len(program.tms)} exceeds "
                f"XVC limit {self.max_bits}"
            )
        try:
            tdo = self.xvc.shift(program.tms, program.tdi)
        except (OSError, RuntimeError, ValueError) as error:
            self.close()
            raise HardwareDisconnected(
                f"hardware share read failed on lane {lane_name}: {error}"
            ) from error
        data, _ = extract_valid_bytes(
            tdo, program.read_windows, selected_lane
        )
        self.buffers[lane_name].extend(data)

    def _pop_frame(self, lane_name):
        buffer = self.buffers[lane_name]
        while True:
            magic_index = buffer.find(FRAME_MAGIC)
            if magic_index < 0:
                if buffer[-1:] == FRAME_MAGIC[:1]:
                    del buffer[:-1]
                else:
                    buffer.clear()
                return None
            if magic_index:
                del buffer[:magic_index]
            if len(buffer) < 6:
                return None
            version = buffer[2]
            frame_type = buffer[3]
            payload_length = int.from_bytes(buffer[4:6], "little")
            if version != FRAME_VERSION or payload_length > 4096:
                del buffer[0]
                continue
            frame_length = 6 + payload_length + 2
            if len(buffer) < frame_length:
                return None
            payload = bytes(buffer[6:6 + payload_length])
            received_crc = int.from_bytes(
                buffer[6 + payload_length:frame_length], "little"
            )
            del buffer[:frame_length]
            calculated_crc = crc16(payload)
            if received_crc != calculated_crc:
                print(
                    f"[!] lane={lane_name} frame CRC mismatch "
                    f"received={received_crc:04x} calculated={calculated_crc:04x}"
                )
                continue
            return frame_type, payload

    def pop_shares(self):
        shares = []
        for lane_name, selected_lane in (("A", 0), ("B", 1)):
            self._read_lane(lane_name, selected_lane)
            while True:
                frame = self._pop_frame(lane_name)
                if frame is None:
                    break
                frame_type, payload = frame
                if frame_type != FRAME_SHARE or len(payload) != SHARE_PAYLOAD_BYTES:
                    print(
                        f"[.] ignored lane={lane_name} frame "
                        f"type={frame_type} payload_length={len(payload)}"
                    )
                    continue
                shares.append(
                    (
                        lane_name,
                        payload[0],
                        int.from_bytes(payload[1:5], "little"),
                        payload[5:37].hex(),
                    )
                )
        return shares


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
            "BTC3_WALLET is required and must be a lowercase bc1q address"
        )
    if not WORKER_RE.fullmatch(WORKER):
        raise ValueError(
            "BTC3_WORKER must contain only letters, digits, underscore, or dash"
        )
    if not 1 <= PORT <= 65535:
        raise ValueError("BTC3_POOL_PORT must be between 1 and 65535")
    if not 1 <= XVC_PORT <= 65535:
        raise ValueError("JCM33_XVC_PORT must be between 1 and 65535")
    if not 1.0 <= WORK_ROLL_SECONDS <= 8.0:
        raise ValueError(
            "BTC3_WORK_ROLL_SECONDS must be between 1.0 and 8.0 seconds"
        )


def wallet_for_mode(mode):
    return USER_WALLET


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

def build_job_pair(params, active_wallet, fee_mode, extranonce2_counter):
    job_a = build_job(
        params, active_wallet, fee_mode, extranonce2_counter
    )
    job_a["device"] = "A"
    job_b = build_job(
        params, active_wallet, fee_mode, extranonce2_counter + 1
    )
    job_b["device"] = "B"
    return job_a, job_b


def dispatch_job_pair(hardware, job_a, job_b):
    hardware.send_job_pair(job_a, job_b)
    print(
        f"[>] paired jobs id={job_a['job_id']} "
        f"A_tag={job_a['tag']:02x} A_en2={job_a['extranonce2']} "
        f"B_tag={job_b['tag']:02x} B_en2={job_b['extranonce2']} "
        f"target={job_a['target']:064x} order=A-tailpad,B-tailpad"
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
        "device": job.get("device", "?"),
        "difficulty": job["difficulty"],
        "nonce": nonce_hex,
        "job_id": job["job_id"],
    }
    sock.sendall((json.dumps(msg) + "\n").encode())
    print(
        f"{YELLOW}[$$$][{job['fee_mode']}] SUBMITTED "
        f"nonce={nonce_hex} job={job['job_id']}{RESET}"
    )

def check_one_share(sock, lane, tag, nonce, hw_digest):
    job = jobs.get(tag)
    if job is None:
        print(f"[.] stale share lane={lane} tag={tag:02x}")
        return

    header = job["prefix"] + struct.pack("<I", nonce)
    sw_raw = sha3t(header).hex()

    print(
        f"{CYAN}[SHARE] physical_lane={lane} assigned={job.get('device', '?')} "
        f"tag={tag:02x} nonce={nonce:08x}{RESET}"
    )
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


def check_shares(sock, hardware):
    for lane, tag, nonce, hw_digest in hardware.pop_shares():
        check_one_share(sock, lane, tag, nonce, hw_digest)

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
        print(
            f"[*][{fee_mode}] BitcoinIII JCM33 dual-FPGA SHA3-256T canary "
            f"worker={WORKER} wallet={active_wallet} "
            f"work_roll={WORK_ROLL_SECONDS:.1f}s cwd={os.getcwd()}"
        )

        while True:
            new_mode = schedule.mode_at(time.time())
            if new_mode != fee_mode:
                raise WalletRotation(f"{fee_mode} -> {new_mode}")

            check_shares(sock, hardware)

            monotonic_now = time.monotonic()
            if (
                latest_notify_params is not None
                and next_work_roll is not None
                and monotonic_now >= next_work_roll
            ):
                rolled_a, rolled_b = build_job_pair(
                    latest_notify_params,
                    active_wallet,
                    fee_mode,
                    extranonce2_counter,
                )
                extranonce2_counter += 2
                dispatch_job_pair(hardware, rolled_a, rolled_b)
                print(
                    f"[ROLL] fresh nonce spaces "
                    f"A={rolled_a['extranonce2']} B={rolled_b['extranonce2']}"
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
                    pool_job_a, pool_job_b = build_job_pair(
                        latest_notify_params,
                        active_wallet,
                        fee_mode,
                        extranonce2_counter,
                    )
                    extranonce2_counter += 2
                    dispatch_job_pair(hardware, pool_job_a, pool_job_b)
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
                    response_device = (
                        metadata["device"] if metadata else "?"
                    )
                    if msg.get("result") is True:
                        print(
                            f"{GREEN}[ACCEPTED][{response_mode}] "
                            f"device={response_device} "
                            f"difficulty={response_difficulty} "
                            f"share accepted by pool response={msg}{RESET}"
                        )
                    else:
                        print(
                            f"{RED}[REJECTED][{response_mode}] "
                            f"device={response_device} "
                            f"difficulty={response_difficulty} "
                            f"pool submit response={msg}{RESET}"
                        )


def main():
    validate_configuration()
    schedule = DevFeeSchedule(f"{SERIAL}|{WORKER}")
    hardware = HardwareTransport(XVC_HOST, XVC_PORT)
    effective_fee = 100.0 * schedule.dev_seconds / schedule.cycle_seconds

    print(f"[FEE] external developer-wallet rotation={effective_fee:.2f}%")

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


def self_test():
    sample_job = {
        "tag": 0xA5,
        "prefix": bytes(range(76)),
        "target": int.from_bytes(bytes(range(32)), "little"),
    }
    wire = job_wire_frame(sample_job)
    assert len(wire) == 117
    write_a = build_per_byte_write(0, wire)
    write_b = build_per_byte_write(1, wire)
    paired = concatenate_programs(write_a, write_b)
    assert len(write_a.tms) == len(write_a.tdi) == 1926
    assert len(write_b.tms) == len(write_b.tdi) == 1926
    assert len(paired.tms) == len(paired.tdi) == 3852
    assert len(paired.tms) < 4096
    for lane in (0, 1):
        read = build_lane_read(lane)
        assert len(read.tms) == len(read.tdi) < 4096

    payload = bytes((0xA5,)) + (0x78563412).to_bytes(4, "little") + bytes(range(32))
    share_frame = encode_frame(FRAME_SHARE, payload)
    transport = HardwareTransport("unused", 1)
    transport.buffers["A"].extend(b"noise" + share_frame)
    decoded_type, decoded_payload = transport._pop_frame("A")
    assert decoded_type == FRAME_SHARE
    assert decoded_payload == payload
    assert transport._pop_frame("A") is None
    print(
        "SELFTEST PASS: paired independent A/B tailpad writes, dual-lane read, "
        "and share decoder verified"
    )

if __name__ == "__main__":
    try:
        if os.environ.get("JCM33_SELF_TEST") == "1":
            self_test()
        else:
            main()
    except ValueError as error:
        raise SystemExit(f"configuration error: {error}") from error
