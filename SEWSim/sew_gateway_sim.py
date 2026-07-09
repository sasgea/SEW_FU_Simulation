"""
SEW Gateway Modbus simulation.

Simulates an RCU <-> SEW Gateway interface over Modbus TCP for up to 8 motors.
CAN communication is intentionally not modeled.

Interface profile derived from PLC snippets:
- FC23 (Read/Write Multiple Registers)
- Read address:  0x0004
- Write address: 0x0004
- Quantity: 24 words (8 motors x 3 words)

Per motor write words:
- word 0: control word
- word 1: setpoint RPM x 5 (signed)
- word 2: ramp time raw (PLC writes FC_MasterWrite.RampTimeStart * 2)

Per motor read words (simulated):
- word 0: status word
- word 1: output current x 10 (0.1%)
- word 2: drive RPM x 5
"""

from __future__ import annotations

import json
import socket
import threading
import time
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, Dict, List, Optional

from pyModbusTCP.server import DataBank, ModbusServer

try:
    import paho.mqtt.client as mqtt
except Exception:
    mqtt = None


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _decode_s16(value: int) -> int:
    value &= 0xFFFF
    if value > 0x7FFF:
        return value - 0x10000
    return value


def _encode_s16(value: int) -> int:
    value = int(value)
    if value < 0:
        return (value + 0x10000) & 0xFFFF
    return value & 0xFFFF


def check_ip_available(ip_address: str) -> bool:
    """Return True if this host can bind the provided IP."""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.bind((ip_address, 0))
        sock.close()
        return True
    except OSError:
        return False


@dataclass
class MotorState:
    idx: int
    name: str
    control_word: int = 0
    status_word: int = 0
    setpoint_rpm: float = 0.0
    actual_rpm: float = 0.0
    ramp_time_s: float = 3.0
    load_percent: float = 20.0
    current_percent: float = 0.0
    enabled: bool = False
    ready: bool = True
    running: bool = False
    target_reached: bool = False
    fault: bool = False
    manual_override: bool = False
    manual_setpoint_rpm: float = 0.0
    last_update_iso: str = ""

    def to_dict(self) -> Dict[str, Any]:
        out = asdict(self)
        out["setpoint_rpm"] = round(self.setpoint_rpm, 2)
        out["actual_rpm"] = round(self.actual_rpm, 2)
        out["ramp_time_s"] = round(self.ramp_time_s, 2)
        out["load_percent"] = round(self.load_percent, 2)
        out["current_percent"] = round(self.current_percent, 2)
        return out


class SEWGatewayDataBank(DataBank):
    """
    DataBank that intercepts write telegrams and maps them to motor commands.

    For FC23 with same read/write address, we parse incoming command words and
    immediately replace holding registers with simulated readback values.
    """

    def __init__(self, sim: "SEWGatewaySim") -> None:
        super().__init__()
        self._sim = sim

    def set_holding_registers(self, address: int, word_list: List[int], srv_info=None):
        if self._sim.intercepts(address, len(word_list)):
            self._sim.apply_partial_command_write(address, word_list)
            readback = self._sim.get_response_words()
            return super().set_holding_registers(self._sim.base_address, readback, srv_info)
        return super().set_holding_registers(address, word_list, srv_info)


class SEWGatewaySim:
    TOPIC_PREFIX = "gea/sewSim"

    def __init__(
        self,
        ip_address: str,
        port: int = 502,
        motors: int = 8,
        base_address: int = 4,
        mqtt_broker: str = "localhost",
        mqtt_port: int = 1883,
        enable_mqtt: bool = True,
        web_host: str = "0.0.0.0",
        web_port: int = 8090,
        enable_web: bool = True,
    ) -> None:
        self.ip_address = ip_address
        self.port = port
        self.base_address = base_address
        self.max_motors = max(1, min(8, motors))

        self.enable_mqtt = enable_mqtt and mqtt is not None
        self.mqtt_broker = mqtt_broker
        self.mqtt_port = mqtt_port
        self._mqtt_client = None

        self.enable_web = enable_web
        self.web_host = web_host
        self.web_port = web_port
        self._web_server: Optional[ThreadingHTTPServer] = None
        self._web_thread: Optional[threading.Thread] = None

        self._lock = threading.Lock()
        self._running = False
        self._last_run = 0.0
        self.start_time = 0.0

        self.command_words: List[int] = [0] * 24
        self.motors: List[MotorState] = [
            MotorState(idx=i, name=f"Motor{i+1}", last_update_iso=_now_iso()) for i in range(self.max_motors)
        ]

        self.databank = SEWGatewayDataBank(self)
        self.server = ModbusServer(
            host=self.ip_address,
            port=self.port,
            no_block=True,
            data_bank=self.databank,
        )

    def intercepts(self, address: int, quantity: int) -> bool:
        start = address
        end = address + quantity
        range_start = self.base_address
        range_end = self.base_address + 24
        return start < range_end and end > range_start

    def _motor_slice(self, motor_idx: int) -> slice:
        start = motor_idx * 3
        return slice(start, start + 3)

    def apply_partial_command_write(self, address: int, words: List[int]) -> None:
        with self._lock:
            offset = address - self.base_address
            for i, w in enumerate(words):
                pos = offset + i
                if 0 <= pos < len(self.command_words):
                    self.command_words[pos] = int(w) & 0xFFFF
            self._apply_commands_locked()

    def _apply_commands_locked(self) -> None:
        for i, motor in enumerate(self.motors):
            sl = self._motor_slice(i)
            cw, sp_raw, ramp_raw = self.command_words[sl]

            motor.control_word = cw

            reset = bool(cw & (1 << 6))
            run_request = bool(cw & (1 << 1)) and bool(cw & (1 << 2))

            if reset:
                motor.fault = False

            if not motor.fault:
                motor.enabled = run_request
            else:
                motor.enabled = False

            if motor.manual_override:
                setpoint_rpm = motor.manual_setpoint_rpm
            else:
                setpoint_rpm = _decode_s16(sp_raw) / 5.0
            motor.setpoint_rpm = setpoint_rpm

            # PLC writes RampTimeStart * 2. Using /2000 maps 6000 -> 3.0s.
            if ramp_raw > 0:
                motor.ramp_time_s = max(0.2, min(60.0, ramp_raw / 2000.0))

    def _update_motors_locked(self, dt: float) -> None:
        for motor in self.motors:
            if motor.fault:
                target = 0.0
            elif motor.enabled:
                target = motor.setpoint_rpm
            else:
                target = 0.0

            rpm_per_s = 3000.0 / max(0.2, motor.ramp_time_s)
            max_step = rpm_per_s * dt
            diff = target - motor.actual_rpm

            if abs(diff) <= max_step:
                motor.actual_rpm = target
            else:
                motor.actual_rpm += max_step if diff > 0 else -max_step

            motor.running = abs(motor.actual_rpm) > 1.0
            motor.ready = not motor.fault
            motor.target_reached = abs(motor.actual_rpm - target) < 2.0 and motor.enabled and not motor.fault

            base_current = 5.0 if motor.running else 0.0
            speed_part = min(70.0, abs(motor.actual_rpm) / 3000.0 * 60.0)
            motor.current_percent = max(0.0, min(200.0, base_current + speed_part + motor.load_percent))
            motor.last_update_iso = _now_iso()

    def _status_word_for_motor(self, motor: MotorState) -> int:
        word = 0
        if motor.ready:
            word |= (1 << 0)
        if motor.enabled:
            word |= (1 << 1)
        if motor.running:
            word |= (1 << 2)
        if motor.fault:
            word |= (1 << 3)
        if motor.target_reached:
            word |= (1 << 6)
        if motor.actual_rpm < -1.0:
            word |= (1 << 10)
        return word

    def get_response_words(self) -> List[int]:
        with self._lock:
            out: List[int] = [0] * 24
            for i, motor in enumerate(self.motors):
                base = i * 3
                status = self._status_word_for_motor(motor)
                motor.status_word = status
                out[base + 0] = status & 0xFFFF
                # Match productive PLC mapping:
                # FC_SEW_ModbusRead[i,1] -> OutputCurrent, FC_SEW_ModbusRead[i,2] -> DriveRPM
                out[base + 1] = int(round(motor.current_percent * 10.0)) & 0xFFFF
                out[base + 2] = _encode_s16(int(round(motor.actual_rpm * 5.0)))
            return out

    def _write_response_registers(self) -> None:
        readback = self.get_response_words()
        DataBank.set_holding_registers(self.databank, self.base_address, readback)

    def get_state(self) -> Dict[str, Any]:
        with self._lock:
            return {
                "gateway_ip": self.ip_address,
                "modbus_port": self.port,
                "base_address": self.base_address,
                "motors": [m.to_dict() for m in self.motors],
                "uptime_seconds": int(time.time() - self.start_time) if self.start_time else 0,
                "timestamp": _now_iso(),
            }

    def set_motor_override(
        self,
        motor_idx: int,
        load_percent: Optional[float] = None,
        fault: Optional[bool] = None,
        manual_setpoint_rpm: Optional[float] = None,
        name: Optional[str] = None,
    ) -> bool:
        if motor_idx < 0 or motor_idx >= len(self.motors):
            return False
        with self._lock:
            motor = self.motors[motor_idx]
            if load_percent is not None:
                motor.load_percent = max(0.0, min(150.0, float(load_percent)))
            if fault is not None:
                motor.fault = bool(fault)
            if manual_setpoint_rpm is not None:
                motor.manual_override = True
                motor.manual_setpoint_rpm = float(manual_setpoint_rpm)
            if manual_setpoint_rpm is None:
                motor.manual_override = False
            if name:
                motor.name = str(name)
            return True

    def _setup_mqtt(self) -> None:
        if not self.enable_mqtt:
            return

        def on_connect(client, userdata, flags, rc):
            if rc == 0:
                client.subscribe(f"{self.TOPIC_PREFIX}/+/set")
                print(f"[SEW][MQTT] connected {self.mqtt_broker}:{self.mqtt_port}")
            else:
                print(f"[SEW][MQTT] connect failed rc={rc}")

        def on_message(client, userdata, msg):
            try:
                payload = json.loads(msg.payload.decode("utf-8"))
            except Exception:
                return

            parts = msg.topic.split("/")
            if len(parts) < 4:
                return
            motor_name = parts[2]
            motor_idx = None
            for i, m in enumerate(self.motors):
                if m.name == motor_name:
                    motor_idx = i
                    break
            if motor_idx is None:
                return

            self.set_motor_override(
                motor_idx,
                load_percent=payload.get("load_percent"),
                fault=payload.get("fault"),
                manual_setpoint_rpm=payload.get("manual_setpoint_rpm"),
                name=payload.get("name"),
            )

        client = mqtt.Client(client_id="sew_gateway_sim")
        client.on_connect = on_connect
        client.on_message = on_message
        client.reconnect_delay_set(min_delay=1, max_delay=20)

        try:
            client.connect(self.mqtt_broker, self.mqtt_port, keepalive=60)
            client.loop_start()
            self._mqtt_client = client
        except Exception as exc:
            print(f"[SEW][MQTT] disabled: cannot connect ({exc})")
            self._mqtt_client = None

    def _publish_mqtt_state(self) -> None:
        if not self._mqtt_client:
            return
        state = self.get_state()
        self._mqtt_client.publish(f"{self.TOPIC_PREFIX}/system/state", json.dumps(state), retain=False)
        for motor in state["motors"]:
            name = motor["name"]
            self._mqtt_client.publish(
                f"{self.TOPIC_PREFIX}/{name}/state",
                json.dumps(motor),
                retain=False,
            )

    def _setup_web(self) -> None:
        if not self.enable_web:
            return

        sim = self

        class Handler(BaseHTTPRequestHandler):
            def _send_json(self, status: int, payload: Dict[str, Any]) -> None:
                raw = json.dumps(payload).encode("utf-8")
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(raw)))
                self.end_headers()
                self.wfile.write(raw)

            def _send_html(self, html: str) -> None:
                raw = html.encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(raw)))
                self.end_headers()
                self.wfile.write(raw)

            def do_GET(self):
                if self.path == "/" or self.path == "/index.html":
                    self._send_html(sim._dashboard_html())
                    return
                if self.path == "/api/state":
                    self._send_json(200, sim.get_state())
                    return
                self._send_json(404, {"error": "not found"})

            def do_POST(self):
                if not self.path.startswith("/api/motor/"):
                    self._send_json(404, {"error": "not found"})
                    return
                try:
                    idx = int(self.path.split("/")[-1])
                except Exception:
                    self._send_json(400, {"error": "invalid motor index"})
                    return

                content_length = int(self.headers.get("Content-Length", "0"))
                payload_raw = self.rfile.read(content_length) if content_length > 0 else b"{}"
                try:
                    payload = json.loads(payload_raw.decode("utf-8"))
                except Exception:
                    self._send_json(400, {"error": "invalid json"})
                    return

                ok = sim.set_motor_override(
                    idx,
                    load_percent=payload.get("load_percent"),
                    fault=payload.get("fault"),
                    manual_setpoint_rpm=payload.get("manual_setpoint_rpm"),
                    name=payload.get("name"),
                )
                if not ok:
                    self._send_json(404, {"error": "motor not found"})
                    return
                self._send_json(200, {"ok": True})

            def log_message(self, format: str, *args):
                return

        self._web_server = ThreadingHTTPServer((self.web_host, self.web_port), Handler)
        self._web_thread = threading.Thread(target=self._web_server.serve_forever, daemon=True)
        self._web_thread.start()

    def _dashboard_html(self) -> str:
        return """<!doctype html>
<html lang=\"en\">
<head>
  <meta charset=\"utf-8\" />
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
  <title>SEW Gateway Sim</title>
  <style>
    :root {
      --bg: #f2efe6;
      --ink: #1a2b3c;
      --accent: #d35400;
      --card: #fffaf2;
      --ok: #1f7a1f;
      --bad: #b22222;
    }
    body {
      margin: 0;
      font-family: "Trebuchet MS", "Segoe UI", sans-serif;
      color: var(--ink);
      background: radial-gradient(circle at 10% 10%, #fff8e8, #e6efe9 55%, #dde8f2 100%);
      min-height: 100vh;
    }
    .wrap {
      max-width: 1100px;
      margin: 0 auto;
      padding: 20px;
    }
    h1 {
      margin: 0 0 12px;
      letter-spacing: 0.04em;
    }
    .meta {
      background: var(--card);
      border: 1px solid #d7d1c4;
      border-radius: 10px;
      padding: 10px 14px;
      margin-bottom: 16px;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      background: var(--card);
      border-radius: 10px;
      overflow: hidden;
    }
    th, td {
      border-bottom: 1px solid #e3ddce;
      padding: 8px;
      text-align: left;
      font-size: 14px;
    }
    th {
      background: #efe8d6;
    }
    .ok { color: var(--ok); font-weight: 700; }
    .bad { color: var(--bad); font-weight: 700; }
    input[type=\"range\"] { width: 100%; }
    button {
      border: 1px solid #bd6e2e;
      background: #fff;
      color: #5b2f0e;
      border-radius: 8px;
      padding: 5px 8px;
      cursor: pointer;
    }
    button:hover { background: #fff0de; }
    @media (max-width: 800px) {
      th, td { font-size: 12px; padding: 6px; }
    }
  </style>
</head>
<body>
  <div class=\"wrap\">
    <h1>SEW Gateway Modbus Simulation</h1>
    <div class=\"meta\" id=\"meta\">loading...</div>
    <table>
      <thead>
        <tr>
          <th>#</th><th>Name</th><th>Enable</th><th>Fault</th><th>Set RPM</th><th>Act RPM</th><th>Current %</th><th>Load %</th><th>Action</th>
        </tr>
      </thead>
      <tbody id=\"tbody\"></tbody>
    </table>
  </div>
  <script>
    async function postMotor(idx, body) {
      await fetch(`/api/motor/${idx}`, {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify(body)
      });
    }

    function motorRow(m) {
      const en = m.enabled ? '<span class="ok">ON</span>' : '<span class="bad">OFF</span>';
      const ft = m.fault ? '<span class="bad">FAULT</span>' : '<span class="ok">OK</span>';
      return `<tr>
        <td>${m.idx + 1}</td>
        <td>${m.name}</td>
        <td>${en}</td>
        <td>${ft}</td>
        <td>${m.setpoint_rpm.toFixed(1)}</td>
        <td>${m.actual_rpm.toFixed(1)}</td>
        <td>${m.current_percent.toFixed(1)}</td>
        <td>
          <input type="range" min="0" max="150" value="${m.load_percent.toFixed(0)}" data-load="${m.idx}" />
          ${m.load_percent.toFixed(0)}
        </td>
        <td><button data-fault="${m.idx}">${m.fault ? 'Clear' : 'Inject'} Fault</button></td>
      </tr>`;
    }

    async function refresh() {
      const res = await fetch('/api/state');
      const data = await res.json();
      document.getElementById('meta').textContent = `IP ${data.gateway_ip}:${data.modbus_port} | Base ${data.base_address} | Uptime ${data.uptime_seconds}s`;
      document.getElementById('tbody').innerHTML = data.motors.map(motorRow).join('');

      document.querySelectorAll('input[data-load]').forEach(inp => {
        inp.addEventListener('change', async ev => {
          const idx = Number(ev.target.dataset.load);
          await postMotor(idx, {load_percent: Number(ev.target.value)});
        });
      });
      document.querySelectorAll('button[data-fault]').forEach(btn => {
        btn.addEventListener('click', async ev => {
          const idx = Number(ev.target.dataset.fault);
          const row = data.motors.find(x => x.idx === idx);
          await postMotor(idx, {fault: !row.fault});
        });
      });
    }

    refresh();
    setInterval(refresh, 1000);
  </script>
</body>
</html>
"""

    def start(self) -> bool:
        if not check_ip_available(self.ip_address):
            print(f"[SEW] IP {self.ip_address} not available on this host")
            return False

        self.start_time = time.time()
        self._running = True
        self._last_run = time.time()

        self.server.start()
        self._write_response_registers()

        self._setup_mqtt()
        self._setup_web()

        print(f"[SEW] Modbus started on {self.ip_address}:{self.port} (base={self.base_address})")
        if self.enable_web:
            print(f"[SEW] Web dashboard: http://{self.web_host}:{self.web_port}")
        return True

    def stop(self) -> None:
        self._running = False
        try:
            self.server.stop()
        except Exception:
            pass

        if self._mqtt_client:
            try:
                self._mqtt_client.loop_stop()
                self._mqtt_client.disconnect()
            except Exception:
                pass
            self._mqtt_client = None

        if self._web_server:
            try:
                self._web_server.shutdown()
                self._web_server.server_close()
            except Exception:
                pass
            self._web_server = None

    def run(self) -> None:
        if not self._running:
            return

        now = time.time()
        dt = now - self._last_run
        self._last_run = now

        if dt <= 0 or dt > 1.0:
            dt = 0.1

        with self._lock:
            self._update_motors_locked(dt)
        self._write_response_registers()

        if int(now * 2) % 2 == 0:
            self._publish_mqtt_state()
