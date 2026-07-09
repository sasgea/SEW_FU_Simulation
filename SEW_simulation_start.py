#!/usr/bin/env python3
"""
SEW Gateway Modbus Simulation start script.
"""

import argparse
import signal
import sys
import time

from SEWSim import SEWGatewaySim, check_ip_available


def main() -> int:
    parser = argparse.ArgumentParser(description="SEW Gateway Modbus Simulation")
    parser.add_argument("--ip", type=str, default="10.150.2.4", help="Gateway IP to bind")
    parser.add_argument("--port", type=int, default=502, help="Modbus TCP port")
    parser.add_argument("--motors", type=int, default=8, help="Number of simulated motors (1..8)")
    parser.add_argument("--base-address", type=int, default=4, help="Register base address")
    parser.add_argument("--broker", type=str, default="localhost", help="MQTT broker")
    parser.add_argument("--mqtt-port", type=int, default=1883, help="MQTT broker port")
    parser.add_argument("--no-mqtt", action="store_true", help="Disable MQTT")
    parser.add_argument("--web-host", type=str, default="0.0.0.0", help="Dashboard bind host")
    parser.add_argument("--web-port", type=int, default=8090, help="Dashboard port")
    parser.add_argument("--no-web", action="store_true", help="Disable dashboard")
    parser.add_argument(
        "--wait-ip",
        action="store_true",
        help="Wait until gateway IP is available before starting (recommended for systemd)",
    )
    parser.add_argument(
        "--wait-ip-timeout",
        type=int,
        default=0,
        help="Maximum seconds to wait for IP (0 = wait forever)",
    )
    parser.add_argument(
        "--wait-ip-interval",
        type=float,
        default=2.0,
        help="Seconds between IP availability checks",
    )
    args = parser.parse_args()

    print("=" * 60)
    print("SEW Gateway Modbus Simulation")
    print("=" * 60)
    print(f"Gateway IP:   {args.ip}")
    print(f"Modbus Port:  {args.port}")
    print(f"Motors:       {args.motors}")
    print(f"Base address: {args.base_address}")
    print(f"MQTT:         {not args.no_mqtt} ({args.broker}:{args.mqtt_port})")
    print(f"Dashboard:    {not args.no_web} ({args.web_host}:{args.web_port})")
    print(f"Wait for IP:  {args.wait_ip} (timeout={args.wait_ip_timeout}s)")
    print("=" * 60)

    if args.wait_ip:
        start_wait = time.time()
        while not check_ip_available(args.ip):
            waited = int(time.time() - start_wait)
            print(f"[SEW] IP {args.ip} not available yet, waiting... ({waited}s)")
            if args.wait_ip_timeout > 0 and waited >= args.wait_ip_timeout:
                print(f"[SEW] Timeout waiting for IP {args.ip}")
                return 1
            time.sleep(max(0.2, args.wait_ip_interval))

    sim = SEWGatewaySim(
        ip_address=args.ip,
        port=args.port,
        motors=args.motors,
        base_address=args.base_address,
        mqtt_broker=args.broker,
        mqtt_port=args.mqtt_port,
        enable_mqtt=not args.no_mqtt,
        web_host=args.web_host,
        web_port=args.web_port,
        enable_web=not args.no_web,
    )

    def _shutdown(sig, frame):
        print("\n[SEW] Shutdown requested")
        sim.stop()
        sys.exit(0)

    signal.signal(signal.SIGINT, _shutdown)
    signal.signal(signal.SIGTERM, _shutdown)

    if not sim.start():
        print("[SEW] Could not start simulator. Is the IP configured on this host?")
        return 1

    print("[SEW] Running. Press Ctrl+C to stop.")
    try:
        while True:
            sim.run()
            time.sleep(0.1)
    except KeyboardInterrupt:
        pass
    finally:
        sim.stop()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
