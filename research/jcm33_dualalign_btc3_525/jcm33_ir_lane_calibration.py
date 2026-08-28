#!/usr/bin/env python3
"""Measure the JCM33 JTAG IR chain and map safe USER1/USER2 lanes."""

import argparse
import binascii
import random
import socket
import struct
import sys


EXPECTED_IDCODE = 0x04B69093
IR_CELL_BITS = 6
USER1 = 0x02
USER2 = 0x03
BYPASS = 0x3F
MAGIC = b"FJ"
VERSION = 1
FRAME_JOB = 1
FRAME_SHARE = 2
JOB_PAYLOAD_BYTES = 109
SHARE_PAYLOAD_BYTES = 37
JOBACK_MARKER = b"JCM33JOBACK525"
IDLE_CLOCKS = 256
PREFERRED_READ_SCANS = 96
MIN_READ_SCANS = 48


def recv_exact(sock: socket.socket, length: int) -> bytes:
    result = bytearray()
    while len(result) < length:
        chunk = sock.recv(length - len(result))
        if not chunk:
            raise RuntimeError(
                f"XVC disconnected after {len(result)}/{length} response bytes"
            )
        result.extend(chunk)
    return bytes(result)


def bits_for(value: int, width: int):
    return [(value >> bit) & 1 for bit in range(width)]


def value_from_bits(bits) -> int:
    return sum(value << index for index, value in enumerate(bits))


def pack_bits(bits):
    packed = bytearray((len(bits) + 7) // 8)
    for index, value in enumerate(bits):
        if value:
            packed[index // 8] |= 1 << (index % 8)
    return bytes(packed)


def unpack_bits(packed: bytes, count: int):
    return [
        (packed[index // 8] >> (index % 8)) & 1
        for index in range(count)
    ]


def crc16(payload: bytes) -> int:
    return binascii.crc_hqx(payload, 0xFFFF)


def encode_frame(frame_type: int, payload: bytes) -> bytes:
    header = MAGIC + bytes((VERSION, frame_type)) + len(payload).to_bytes(2, "little")
    return header + payload + crc16(payload).to_bytes(2, "little")


def job_frame(tag: int) -> bytes:
    payload = bytes((tag,)) + bytes(76) + bytes((0xFF,)) * 32
    if len(payload) != JOB_PAYLOAD_BYTES:
        raise AssertionError("internal diagnostic job payload length mismatch")
    return encode_frame(FRAME_JOB, payload)


def diagnostic_ack(tag: int, sequence: int) -> bytes:
    marker = JOBACK_MARKER.ljust(32, b"\x00")
    payload = bytes((tag,)) + sequence.to_bytes(4, "little") + marker
    return encode_frame(FRAME_SHARE, payload)


class XVC:
    def __init__(self, host: str, port: int, timeout: float):
        self.sock = socket.create_connection((host, port), timeout=timeout)
        self.sock.settimeout(timeout)

    def close(self):
        self.sock.close()

    def getinfo(self):
        self.sock.sendall(b"getinfo:")
        response = bytearray()
        while not response.endswith(b"\n"):
            response.extend(recv_exact(self.sock, 1))
            if len(response) > 256:
                raise RuntimeError("XVC getinfo response exceeded 256 bytes")
        text = response.decode("ascii", errors="strict").strip()
        if ":" not in text:
            raise RuntimeError(f"malformed XVC getinfo response: {text!r}")
        return text, int(text.rsplit(":", 1)[1])

    def settck(self, period_ns: int):
        self.sock.sendall(b"settck:" + struct.pack("<I", period_ns))
        return struct.unpack("<I", recv_exact(self.sock, 4))[0]

    def shift(self, tms_bits, tdi_bits):
        if len(tms_bits) != len(tdi_bits):
            raise ValueError("TMS and TDI bit counts differ")
        count = len(tms_bits)
        byte_count = (count + 7) // 8
        self.sock.sendall(
            b"shift:"
            + struct.pack("<I", count)
            + pack_bits(tms_bits)
            + pack_bits(tdi_bits)
        )
        return unpack_bits(recv_exact(self.sock, byte_count), count)

    def tap_reset(self):
        self.shift([1] * 6, [0] * 6)

    def scan_reset_idcodes(self):
        self.tap_reset()
        self.shift([0, 1, 0, 0], [0, 0, 0, 0])
        tdo = self.shift([0] * 63 + [1], [0] * 64)
        self.shift([1, 0], [0, 0])
        packed = pack_bits(tdo)
        return [
            int.from_bytes(packed[0:4], "little"),
            int.from_bytes(packed[4:8], "little"),
        ], packed

    def measure_ir_delay(self):
        """Measure total IR delay while leaving every IR bit at safe BYPASS=1."""
        rng = random.Random(0x4A434D33)
        probe = [rng.getrandbits(1) for _ in range(128)]
        tdi = probe + [1] * 128

        self.tap_reset()
        # TLR -> RTI -> Select-DR -> Select-IR -> Capture-IR -> Shift-IR.
        self.shift([0, 1, 1, 0, 0], [0, 0, 0, 0, 0])
        tdo = self.shift([0] * (len(tdi) - 1) + [1], tdi)
        # Exit1-IR -> Update-IR -> RTI. The trailing ones select BYPASS safely.
        self.shift([1, 0], [0, 0])

        scores = {}
        for delay in range(1, 129):
            scores[delay] = sum(
                tdo[delay + index] == probe[index]
                for index in range(len(probe))
            )
        exact = [delay for delay, score in scores.items() if score == len(probe)]
        if len(exact) != 1:
            best = sorted(scores.items(), key=lambda item: (-item[1], item[0]))[:8]
            raise RuntimeError(
                f"could not determine a unique total IR delay; exact={exact} best={best}"
            )
        delay = exact[0]
        return delay, tdo[:delay], scores


class TapProgram:
    """One atomic XVC shift program, starting from an unknown TAP state."""

    def __init__(self):
        self.tms = []
        self.tdi = []
        self.read_windows = []

    def add(self, tms, tdi=None):
        tms_values = list(tms)
        tdi_values = [0] * len(tms_values) if tdi is None else list(tdi)
        if len(tms_values) != len(tdi_values):
            raise ValueError("TMS/TDI append lengths differ")
        self.tms.extend(tms_values)
        self.tdi.extend(tdi_values)

    def reset_to_idle(self):
        self.add([1] * 6 + [0])

    def set_ir_lane(self, lane_count: int, selected_lane: int, instruction: int):
        instructions = [BYPASS] * lane_count
        instructions[selected_lane] = instruction
        self.add([1, 1, 0, 0])
        ir_stream = []
        for value in instructions:
            ir_stream.extend(bits_for(value, IR_CELL_BITS))
        self.add([0] * (len(ir_stream) - 1) + [1], ir_stream)
        self.add([1, 0])

    def scan_dr(self, bits, record_read=False):
        values = list(bits)
        if not values:
            raise ValueError("empty DR scan")
        self.add([1, 0, 0])
        start = len(self.tms)
        self.add([0] * (len(values) - 1) + [1], values)
        if record_read:
            self.read_windows.append((start, len(values)))
        self.add([1, 0])


def build_lane_job_ack(
    lane_count: int, selected_lane: int, tag: int, max_bits: int
):
    if not 0 <= selected_lane < lane_count:
        raise ValueError("selected lane is outside the measured IR chain")

    for read_scans in range(PREFERRED_READ_SCANS, MIN_READ_SCANS - 1, -1):
        program = TapProgram()
        program.reset_to_idle()
        program.set_ir_lane(lane_count, selected_lane, USER2)
        pre = [0] * selected_lane
        post = [0] * (lane_count - selected_lane - 1)
        for byte in job_frame(tag):
            program.scan_dr(pre + bits_for(byte, 8) + post)
        program.add([0] * IDLE_CLOCKS)
        program.set_ir_lane(lane_count, selected_lane, USER1)
        for _ in range(read_scans):
            program.scan_dr([0] * (lane_count + 8), record_read=True)
        program.reset_to_idle()
        if len(program.tms) <= max_bits:
            return program, read_scans
    raise RuntimeError(
        f"measured lane count {lane_count} cannot fit a diagnostic transaction "
        f"within the XVC limit {max_bits}"
    )


def extract_valid_bytes(tdo, windows, offset: int):
    result = bytearray()
    words = []
    for start, width in windows:
        if offset + 9 > width:
            raise ValueError("read offset extends past full-chain DR width")
        word = value_from_bits(tdo[start + offset : start + offset + 9])
        words.append(word)
        if (word & 0x100) == 0:
            result.append(word & 0xFF)
    return bytes(result), words


def iter_jobacks(data: bytes):
    buffer = bytearray(data)
    while True:
        index = buffer.find(MAGIC)
        if index < 0:
            return
        del buffer[:index]
        if len(buffer) < 6:
            return
        payload_length = int.from_bytes(buffer[4:6], "little")
        if payload_length > 4096:
            del buffer[0]
            continue
        frame_length = 6 + payload_length + 2
        if len(buffer) < frame_length:
            return
        frame = bytes(buffer[:frame_length])
        del buffer[:frame_length]
        payload = frame[6:-2]
        if crc16(payload) != int.from_bytes(frame[-2:], "little"):
            continue
        if frame[2] != VERSION or frame[3] != FRAME_SHARE:
            continue
        if len(payload) != SHARE_PAYLOAD_BYTES:
            continue
        if not payload[5:].startswith(JOBACK_MARKER):
            continue
        yield {
            "tag": payload[0],
            "sequence": int.from_bytes(payload[1:5], "little"),
        }


def capture_markers(capture, cell_bits=IR_CELL_BITS):
    return [
        offset
        for offset in range(0, len(capture), cell_bits)
        if offset + 1 < len(capture) and capture[offset : offset + 2] == [1, 0]
    ]


def simulate_delay(delay: int, tdi, capture):
    register = list(capture)
    result = []
    for value in tdi:
        result.append(register.pop(0))
        register.append(value)
    return result


def infer_delay(tdi, tdo, probe_length):
    probe = tdi[:probe_length]
    exact = []
    for delay in range(1, min(128, len(tdo) - probe_length) + 1):
        if tdo[delay : delay + probe_length] == probe:
            exact.append(delay)
    if len(exact) != 1:
        raise AssertionError(f"self-test delay inference was ambiguous: {exact}")
    return exact[0]


def self_test():
    rng = random.Random(0x4A434D33)
    probe = [rng.getrandbits(1) for _ in range(128)]
    tdi = probe + [1] * 128
    for delay in (12, 24, 36, 48):
        capture = ([1, 0] + [0] * (IR_CELL_BITS - 2)) * (delay // IR_CELL_BITS)
        tdo = simulate_delay(delay, tdi, capture)
        assert infer_delay(tdi, tdo, len(probe)) == delay
    assert len(job_frame(0x20)) == 117
    assert len(diagnostic_ack(0x20, 1)) == 45
    for lanes in (2, 4, 6):
        for lane in (0, lanes - 1):
            program, scans = build_lane_job_ack(lanes, lane, 0x20 + lane, 4096)
            assert len(program.tms) == len(program.tdi) <= 4096
            assert scans >= MIN_READ_SCANS
    print("SELFTEST PASS: IR-delay and lane-program construction verified")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=2542)
    parser.add_argument("--timeout", type=float, default=30.0)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        self_test()
        return 0

    xvc = XVC(args.host, args.port, args.timeout)
    try:
        info, max_bits = xvc.getinfo()
        print(f"XVC_INFO: {info}")
        print(f"XVC_TCK_PERIOD_NS: {xvc.settck(1000)}")
        idcodes, packed = xvc.scan_reset_idcodes()
        print(f"RAW_TDO_64: {packed.hex()}")
        for index, idcode in enumerate(idcodes):
            print(f"DEVICE_{index}_IDCODE: 0x{idcode:08x}")
        if idcodes != [EXPECTED_IDCODE, EXPECTED_IDCODE]:
            raise RuntimeError(
                "unexpected IDCODE chain: "
                + ",".join(f"0x{value:08x}" for value in idcodes)
            )

        total_ir_bits, capture, _ = xvc.measure_ir_delay()
        if total_ir_bits % (2 * IR_CELL_BITS) != 0:
            raise RuntimeError(
                f"total IR delay {total_ir_bits} is not divisible by "
                f"two devices x {IR_CELL_BITS} bits"
            )
        per_device_ir_bits = total_ir_bits // 2
        lane_count = total_ir_bits // IR_CELL_BITS
        markers = capture_markers(capture)
        print(f"TOTAL_IR_BITS: {total_ir_bits}")
        print(f"PER_DEVICE_IR_BITS: {per_device_ir_bits}")
        print(f"SIX_BIT_IR_LANES: {lane_count}")
        print(f"CAPTURE_IR_BITS_TDO_FIRST: {''.join(map(str, capture))}")
        print(f"CAPTURE_01_CELL_MARKERS: {markers}")
        print("PASS: total IR delay measured; all-ones tail left every IR cell in BYPASS")

        lane_results = []
        for lane in range(lane_count):
            tag = 0x20 + lane
            program, read_scans = build_lane_job_ack(
                lane_count, lane, tag, max_bits
            )
            print(
                f"SEND selected_lane={lane} tag={tag:02x} "
                f"atomic_bits={len(program.tms)} read_scans={read_scans}",
                flush=True,
            )
            tdo = xvc.shift(program.tms, program.tdi)
            hits = []
            observed = {}
            for offset in range(lane_count):
                received, _ = extract_valid_bytes(tdo, program.read_windows, offset)
                records = list(iter_jobacks(received))
                if records:
                    observed[offset] = records
                for record in records:
                    if record["tag"] == tag:
                        hits.append(
                            {
                                "read_offset": offset,
                                "sequence": record["sequence"],
                            }
                        )
            print(
                f"LANE_RESULT selected_lane={lane} tag={tag:02x} "
                f"current_tag_hits={hits} observed_by_offset={observed}",
                flush=True,
            )
            lane_results.append(
                {"selected_lane": lane, "tag": tag, "hits": hits}
            )

        xvc.tap_reset()
    finally:
        xvc.close()

    responding = [entry for entry in lane_results if entry["hits"]]
    print(f"RESPONDING_LANES: {[entry['selected_lane'] for entry in responding]}")
    print(f"LANE_MATRIX: {lane_results}")
    print("RESULT: IR_DELAY_AND_SAFE_USER_LANE_MATRIX_CAPTURED")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError, AssertionError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
