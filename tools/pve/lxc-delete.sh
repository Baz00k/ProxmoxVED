#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

function header_info {
  clear
  cat <<"EOF"
    ____                                          __   _  ________   ____       __     __
   / __ \_________  _  ______ ___  ____  _  __   / /  | |/ / ____/  / __ \___  / /__  / /____
  / /_/ / ___/ __ \| |/_/ __ `__ \/ __ \| |/_/  / /   |   / /      / / / / _ \/ / _ \/ __/ _ \
 / ____/ /  / /_/ />  </ / / / / / /_/ />  <   / /___/   / /___   / /_/ /  __/ /  __/ /_/  __/
/_/   /_/   \____/_/|_/_/ /_/ /_/\____/_/|_|  /_____/_/|_\____/  /_____/\___/_/\___/\__/\___/

EOF
}

spinner() {
  local pid=$1
  local delay=0.1
  local spinstr='|/-\'
  while ps -p $pid >/dev/null; do
    printf " [%c]  " "$spinstr"
    spinstr=${spinstr#?}${spinstr%"${spinstr#?}"}
    sleep $delay
    printf "\r"
  done
  printf "    \r"
}

set -eEuo pipefail
YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
GN=$(echo "\033[1;92m")
CL=$(echo "\033[m")
TAB="  "
CM="${TAB}✔️${TAB}${CL}"

header_info
echo "Loading..."
if ! whiptail --backtitle "Proxmox VE Helper Scripts" --title "Proxmox VE LXC Deletion" --yesno "This will delete LXC containers. Proceed?" 10 58; then
  echo -e "${RD}Aborted by user.${CL}"
  exit 0
fi

mapfile -t containers < <(pct list | tail -n +2)

if [ ${#containers[@]} -eq 0 ]; then
  whiptail --title "LXC Container Delete" --msgbox "No LXC containers available!" 10 60
  exit 1
fi

menu_items=("ALL" "Delete ALL containers" "OFF")
FORMAT="%-10s %-10s %-10s %-10s"

for line in "${containers[@]}"; do
  container_id=$(echo "$line" | awk '{print $1}')
  container_name=$(echo "$line" | awk '{print $2}')
  container_status=$(echo "$line" | awk '{print $3}')
  container_os=$(echo "$line" | awk '{print $4}')
  protected=$(pct config "$container_id" | awk '/^protection:/ {print $2}')
  is_protected="No"
  [[ "$protected" == "1" ]] && is_protected="Yes"
  formatted_line=$(printf "$FORMAT" "$container_name" "$container_status" "$container_os" "$is_protected")
  menu_items+=("$container_id" "$formatted_line" "OFF")
done

CHOICES=$(whiptail --title "LXC Container Delete" \
  --checklist "Select LXC containers to delete:\n\nNAME       STATUS     OS         PROTECTED" 25 70 15 \
  "${menu_items[@]}" 3>&2 2>&1 1>&3)

if [ -z "$CHOICES" ]; then
  whiptail --title "LXC Container Delete" --msgbox "No containers selected!" 10 60
  exit 1
fi

read -p "Delete containers manually or automatically? (Default: manual) m/a: " DELETE_MODE
DELETE_MODE=${DELETE_MODE:-m}
selected_ids=$(echo "$CHOICES" | tr -d '"' | tr -s ' ' '\n')

# ALL ausgewählt
if echo "$selected_ids" | grep -q "^ALL$"; then
  selected_ids=$(printf '%s\n' "${containers[@]}" | awk '{print $1}')
fi

for container_id in $selected_ids; do
  status=$(pct status "$container_id")
  protected=$(pct config "$container_id" | awk '/^protection:/ {print $2}')
  is_protected="No"
  [[ "$protected" == "1" ]] && is_protected="Yes"

  if [[ "$is_protected" == "Yes" && "$DELETE_MODE" == "a" ]]; then
    echo -e "${BL}[Info]${RD} Skipping protected container $container_id (auto mode).${CL}"
    continue
  fi

  if [[ "$status" == "status: running" ]]; then
    if [[ "$is_protected" == "Yes" && "$DELETE_MODE" == "m" ]]; then
      read -p "⚠️  Container $container_id is PROTECTED. Delete anyway? (y/N): " CONFIRM_PROTECTED
      [[ ! "$CONFIRM_PROTECTED" =~ ^[Yy]$ ]] && {
        echo -e "${BL}[Info]${RD} Skipping protected container $container_id...${CL}"
        continue
      }
    fi
    echo -e "${BL}[Info]${GN} Stopping container $container_id...${CL}"
    pct stop "$container_id" &
    sleep 5
    echo -e "${BL}[Info]${GN} Container $container_id stopped.${CL}"
  fi

  if [[ "$DELETE_MODE" == "a" ]]; then
    echo -e "${BL}[Info]${GN} Automatically deleting container $container_id...${CL}"
    pct destroy "$container_id" -f &
    pid=$!
    spinner $pid
    if [ $? -eq 0 ]; then
      echo "Container $container_id deleted."
    else
      whiptail --title "Error" --msgbox "Failed to delete container $container_id." 10 60
    fi
  else
    read -p "Delete container $container_id? (y/N): " CONFIRM
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
      if [[ "$is_protected" == "Yes" ]]; then
        read -p "⚠️  Container $container_id is PROTECTED. Delete anyway? (y/N): " CONFIRM_PROTECTED
        [[ ! "$CONFIRM_PROTECTED" =~ ^[Yy]$ ]] && {
          echo -e "${BL}[Info]${RD} Skipping protected container $container_id...${CL}"
          continue
        }
      fi
      echo -e "${BL}[Info]${GN} Deleting container $container_id...${CL}"
      pct destroy "$container_id" -f &
      pid=$!
      spinner $pid
      if [ $? -eq 0 ]; then
        echo "Container $container_id deleted."
      else
        whiptail --title "Error" --msgbox "Failed to delete container $container_id." 10 60
      fi
    else
      echo -e "${BL}[Info]${RD} Skipping container $container_id...${CL}"
    fi
  fi
done

header_info
echo -e "${GN}Deletion process completed.${CL}\n"
