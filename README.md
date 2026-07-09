# SEW FU Simulation

Modbus-TCP simulation for the SEW gateway interface used by the RCU.

Scope:
- Simulates RCU <-> SEW Gateway communication over Modbus TCP
- Up to 8 drives, each with 3-word write and 3-word read payload
- Optional MQTT control for load/fault overrides
- Optional web dashboard for quick diagnostics
- No CAN bus emulation (intentionally)

## Repository Structure

- `SEW_simulation_start.py` - main entrypoint
- `SEWSim/sew_gateway_sim.py` - core simulator
- `SEWSim/add_sew_gateway_ip.sh` - runtime IP alias helper
- `test_sew_modbus_interface.py` - basic Modbus client test
- `deploy_sew_sim_to_pi.ps1` - deploy helper from Windows to Raspberry Pi
- `service/sew-sim.service` - systemd unit template
- `service/install_service.sh` - systemd installation helper
- `CodeSnippets.st` - reference PLC/ST snippets for mapping

## Modbus Mapping (SEW)

Function profile (as used in ST):
- FC23 read/write multiple registers
- read address: `0x0004`
- write address: `0x0004`
- quantity: `24` words

Per drive write words:
1. word 0: ControlWord
2. word 1: SetPointRPM x5 (signed int16)
3. word 2: RampTime raw (`FC_MasterWrite.RampTimeStart * 2`)

Per drive read words:
1. word 0: StatusWord
2. word 1: OutputCurrent x10
3. word 2: DriveRPM x5 (signed int16)

## Quick Start (Local)

Install dependencies:

```bash
python -m pip install pyModbusTCP paho-mqtt
```

Run simulator:

```bash
python SEW_simulation_start.py --ip 10.150.2.4 --port 502 --motors 8 --web-port 8090 --wait-ip
```

Open dashboard:
- `http://<host>:8090`

Stop:
- `Ctrl+C` in foreground mode

## Start/Stop as Background Process (Linux)

Start in background:

```bash
nohup python3 SEW_simulation_start.py --ip 10.150.2.4 --port 502 --motors 8 --web-port 8090 --wait-ip > sew_sim.log 2>&1 &
```

Stop:

```bash
pkill -f SEW_simulation_start.py
```

## Delayed IP Availability on Boot

Problem:
- On some systems gateway aliases become available late during boot.
- Simulator may fail if it starts before IP exists.

Solution in this repo:
- Use `--wait-ip` in startup command
- For service mode use `Restart=always`

`SEW_simulation_start.py` options:
- `--wait-ip`
- `--wait-ip-timeout 0` (0 means infinite wait)
- `--wait-ip-interval 2`

## Raspberry Pi Deployment

See full step-by-step deployment guide in `DEPLOY_PI.md`.

## Service (Autostart)

See full service setup and troubleshooting in `DEPLOY_PI.md`.

## Validation

Run the included test client:

```bash
python test_sew_modbus_interface.py
```

For signed RPM decode example (`word2`):

```python
rpm_signed = value - 65536 if value > 32767 else value
rpm = rpm_signed / 5.0
```
