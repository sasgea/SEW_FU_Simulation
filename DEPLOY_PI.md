# Deploy Guide (Raspberry Pi)

This guide covers deploy, start/stop, and systemd autostart.

## 1. Requirements

On your Windows machine:
- `ssh`, `scp`, PowerShell

On Raspberry Pi:
- user account with SSH access (default examples use `gea`)
- passwordless sudo for service management and network alias scripts
- Python 3 with `venv`

## 2. One-Command Deploy from Windows

From repository root:

```powershell
.\deploy_sew_sim_to_pi.ps1 -PiHost 10.150.2.2 -PiUser gea -GatewayIp 10.150.2.4 -Interface eth0
```

This does:
- copies code to `/home/gea/SEW_FU_Simulation`
- creates `.venv`
- installs `pyModbusTCP`, `paho-mqtt`
- adds runtime IP alias for gateway IP
- starts simulator in foreground unless service switches are used

## 3. Install and Enable systemd Service

Use deploy helper with service install/start:

```powershell
.\deploy_sew_sim_to_pi.ps1 -PiHost 10.150.2.2 -PiUser gea -InstallService -StartService
```

Or manually on Pi:

```bash
cd /home/gea/SEW_FU_Simulation
chmod +x service/install_service.sh
bash service/install_service.sh
sudo systemctl start sew-sim
```

## 4. Service Operations

Start:

```bash
sudo systemctl start sew-sim
```

Stop:

```bash
sudo systemctl stop sew-sim
```

Restart:

```bash
sudo systemctl restart sew-sim
```

Status:

```bash
sudo systemctl status sew-sim
```

Logs:

```bash
sudo journalctl -u sew-sim -f
```

## 5. Delayed IP Availability (Important)

The service command uses:
- `--wait-ip`
- `--wait-ip-timeout 0`
- `--wait-ip-interval 2`

That means:
- service waits until gateway IP is bindable
- avoids startup failure when aliases appear late
- plus `Restart=always` recovers from transient issues

## 6. Configure Gateway IP Alias

Runtime add:

```bash
bash /home/gea/SEW_FU_Simulation/SEWSim/add_sew_gateway_ip.sh 10.150.2.4/16 eth0
```

Make persistent (depends on distro/network stack):
- classic Debian `/etc/network/interfaces` alias blocks
- `systemd-networkd` `.network` with multiple `Address=`
- NetworkManager profile with additional addresses

## 7. Verification

Check listeners:

```bash
ss -ltn | grep ':502\|:8090'
```

API check:

```bash
curl -s http://127.0.0.1:8090/api/state | head
```

RCU connection check:

```bash
ss -tn | grep '10.150.2.1' | grep ':502'
```
