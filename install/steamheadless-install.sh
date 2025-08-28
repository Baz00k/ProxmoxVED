#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Baz00k
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Steam-Headless/docker-steam-headless

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y curl wget gpg
msg_ok "Installed Dependencies"

msg_info "Installing Docker"
$STD apt-get install -y ca-certificates gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
$STD apt-get update
$STD apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable -q --now docker
msg_ok "Installed Docker"

msg_info "Creating Steam Headless Directory Structure"
mkdir -p /opt/steam-headless
mkdir -p /opt/container-data/steam-headless/{home,sockets/{.X11-unix,pulse}}
mkdir -p /opt/container-data/steam-headless/overrides
mkdir -p /mnt/games
chmod -R 755 /opt/container-data/steam-headless
chmod -R 777 /mnt/games
msg_ok "Created Directory Structure"

msg_info "Tuning vm.max_map_count (LXC)"
current=$(cat /proc/sys/vm/max_map_count 2>/dev/null || echo 0)
target=524288
if [ "${current:-0}" -lt "${target}" ]; then
  echo "vm.max_map_count=${target}" >/etc/sysctl.d/60-steamheadless.conf
  sysctl -w vm.max_map_count="${target}" >/dev/null 2>&1 || true
else
  echo "vm.max_map_count=${current}" >/etc/sysctl.d/60-steamheadless.conf
fi
msg_ok "Tuned vm.max_map_count"


msg_info "Creating Docker Compose Configuration"
cat <<'EOF' >/opt/steam-headless/docker-compose.yml
---
version: "3.8"

services:
  steam-headless:
    image: josh5/steam-headless:latest
    restart: unless-stopped
    shm_size: 2G
    ipc: host
    privileged: true
    ulimits:
      nofile:
        soft: 1024
        hard: 524288
    cap_add:
      - NET_ADMIN
      - SYS_ADMIN
      - SYS_NICE
    security_opt:
      - seccomp:unconfined
      - apparmor:unconfined
    network_mode: host
    hostname: SteamHeadless
    entrypoint: ["/bin/bash","-c","if [ -f /etc/cont-init.d/11-setup_sysctl_values.sh ]; then mv /etc/cont-init.d/11-setup_sysctl_values.sh /etc/cont-init.d/11-setup_sysctl_values.sh.disabled 2>/dev/null || true; fi; exec /entrypoint.sh"]
    extra_hosts:
      - "SteamHeadless:127.0.0.1"
    environment:
      # System
      - TZ=${TZ:-UTC}
      - USER_LOCALES=${USER_LOCALES:-en_US.UTF-8 UTF-8}
      - DISPLAY=${DISPLAY:-:55}

      # User
      - PUID=1000
      - PGID=1000
      - UMASK=000
      - USER_PASSWORD=password

      # Mode
      - MODE=primary

      # Web UI
      - WEB_UI_MODE=vnc
      - ENABLE_VNC_AUDIO=true
      - PORT_NOVNC_WEB=8083

      # Steam
      - ENABLE_STEAM=true
      - STEAM_ARGS=-silent

      # Sunshine
      - ENABLE_SUNSHINE=false
      - SUNSHINE_USER=admin
      - SUNSHINE_PASS=admin

      # Xorg
      - ENABLE_EVDEV_INPUTS=true
      - FORCE_X11_DUMMY_CONFIG=true

      # Nvidia specific config
      - NVIDIA_DRIVER_CAPABILITIES=all
      - NVIDIA_VISIBLE_DEVICES=all

    volumes:
      - /opt/container-data/steam-headless/home:/home/default:rw
      - /mnt/games:/mnt/games:rw
      - /opt/container-data/steam-headless/sockets/.X11-unix:/tmp/.X11-unix:rw
      - /opt/container-data/steam-headless/sockets/pulse:/tmp/pulse:rw
EOF
msg_ok "Created Docker Compose Configuration"

msg_info "Starting Steam Headless Service"
cd /opt/steam-headless
$STD docker compose pull
$STD docker compose up -d --force-recreate
msg_ok "Started Steam Headless Service"

msg_info "Creating System Service"
cat <<'EOF' >/etc/systemd/system/steam-headless.service
[Unit]
Description=Steam Headless Service
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=true
WorkingDirectory=/opt/steam-headless
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q steam-headless
msg_ok "Created System Service"

msg_info "Creating Credentials File"
{
    echo "Steam Headless Credentials"
    echo "=========================="
    echo "Web Interface: http://$(hostname -I | awk '{print $1}'):8083"
    echo "Default User Password: password"
    echo ""
    echo "Configuration:"
    echo "- Home Directory: /opt/container-data/steam-headless/home"
    echo "- Games Directory: /mnt/games"
    echo "- Docker Compose: /opt/steam-headless/docker-compose.yml"
    echo ""
    echo "To access Steam:"
    echo "1. Open the web interface"
    echo "2. Click Connect"
    echo "3. Steam will start automatically"
    echo "4. Configure your Steam library path to /mnt/games"
} >> ~/steamheadless.creds
msg_ok "Created Credentials File"

motd_ssh
customize

msg_info "Cleaning Up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned Up"
