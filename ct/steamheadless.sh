#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/Baz00k/ProxmoxVED/refs/heads/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: Baz00k
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Steam-Headless/docker-steam-headless

APP="SteamHeadless"
var_tags="${var_tags:-gaming}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-0}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
    header_info
    check_container_storage
    check_container_resources

    if [[ ! -f /opt/steam-headless/docker-compose.yml ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi

    msg_info "Updating ${APP}"
    cd /opt/steam-headless
    $STD docker compose pull
    $STD docker compose up -d --force-recreate
    msg_ok "Updated ${APP}"
    exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8083${CL}"
