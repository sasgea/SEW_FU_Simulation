#!/usr/bin/env python3
"""
Basic Modbus test client for SEW gateway simulation.
"""

import time
from pyModbusTCP.client import ModbusClient

IP = "10.150.2.4"
PORT = 502
BASE = 4


def motor_triplet(control_word: int, setpoint_rpm: int, ramp_raw: int):
    sp = setpoint_rpm * 5
    if sp < 0:
        sp = (sp + 65536) & 0xFFFF
    return [control_word & 0xFFFF, sp, ramp_raw & 0xFFFF]


def decode_s16(v: int) -> int:
    if v > 32767:
        return v - 65536
    return v


def main():
    c = ModbusClient(host=IP, port=PORT, auto_open=True, auto_close=False)

    # Enable motor 1: bit1 + bit2 set
    words = [0] * 24
    words[0:3] = motor_triplet(control_word=(1 << 1) | (1 << 2), setpoint_rpm=900, ramp_raw=6000)

    ok = c.write_multiple_registers(BASE, words)
    if not ok:
        print("Write failed")
        return

    for _ in range(8):
        rb = c.read_holding_registers(BASE, 24)
        if rb:
            status = rb[0]
            current = rb[1] / 10.0
            rpm = rb[2] / 5.0
            print(f"status=0x{status:04X}, rpm={rpm:.1f}, current={current:.1f}%")
        time.sleep(0.5)

    c.close()


if __name__ == "__main__":
    main()
