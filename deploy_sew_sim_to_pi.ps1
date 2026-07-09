param(
    [string]$PiHost = "10.150.2.2",
    [string]$PiUser = "gea",
    [string]$TargetDir = "/home/gea/SEW_FU_Simulation",
    [string]$GatewayIp = "10.150.2.4",
    [string]$Netmask = "16",
    [string]$Interface = "eth0",
    [switch]$InstallService,
    [switch]$StartService,
    [switch]$StopService
)

$ErrorActionPreference = "Stop"

Write-Host "[DEPLOY] Copy files to ${PiUser}@${PiHost}:${TargetDir}"
ssh "${PiUser}@${PiHost}" "mkdir -p ${TargetDir}"

scp -r .\SEWSim .\service "${PiUser}@${PiHost}:${TargetDir}/"
scp .\SEW_simulation_start.py .\test_sew_modbus_interface.py .\README.md .\README_SEW.md "${PiUser}@${PiHost}:${TargetDir}/"

Write-Host "[DEPLOY] Create venv and install dependencies"
ssh "${PiUser}@${PiHost}" "cd ${TargetDir}; python3 -m venv .venv; .venv/bin/pip install pyModbusTCP paho-mqtt"

Write-Host "[DEPLOY] Configure SEW gateway IP alias"
ssh "${PiUser}@${PiHost}" "bash ${TargetDir}/SEWSim/add_sew_gateway_ip.sh ${GatewayIp}/${Netmask} ${Interface}"

if ($InstallService) {
    Write-Host "[DEPLOY] Install systemd service"
    ssh "${PiUser}@${PiHost}" "chmod +x ${TargetDir}/service/install_service.sh; cd ${TargetDir}; bash service/install_service.sh"
}

if ($StopService) {
    Write-Host "[DEPLOY] Stop service"
    ssh "${PiUser}@${PiHost}" "sudo -n systemctl stop sew-sim || true"
}

if ($StartService) {
    Write-Host "[DEPLOY] Start service"
    ssh "${PiUser}@${PiHost}" "sudo -n systemctl start sew-sim; sudo -n systemctl status --no-pager sew-sim | sed -n '1,40p'"
}

if (-not $InstallService -and -not $StartService) {
    Write-Host "[DEPLOY] Start simulator in foreground (Ctrl+C to stop)"
    ssh -t "${PiUser}@${PiHost}" "cd ${TargetDir} && .venv/bin/python SEW_simulation_start.py --ip ${GatewayIp} --port 502 --motors 8 --wait-ip"
}
