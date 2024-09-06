#!/usr/bin/env bash

LS_BASE_URL="https://github.com/varlogerr/linux-scripts/raw/${LS_BASE_BRANCH-master}"

#####
# For default values leave fields blank or remove it
#####
# shellcheck disable=SC2034
declare -A CT=(
  # Defaults to automanage
  [id]=131
  # Best guess hint from:
  # * http://download.proxmox.com/images/system
  # Defaults to ubuntu
  [template]='almalinux-8'
  # Defaults to template default. In GB
  [disk]=20
  # Defaults to template default. In MB
  [ram]=2048
  # Example: 2
  # Defaults to template default
  [cores]=2
  # Defaults to false
  [onboot]=true
  # Defaults to false
  [privileged]=false
  # Defaults to empty value
  [root_pass]='changeme'
  # Defaults to unset
  [hostname]='int1.axway.vm'
  # Defaults to 'vmbr0'
  [net_bridge]='vmbr0'
  # Example: 192.0.0.5/24
  # Defaults to 'dhcp'
  [net_ip]="dhcp"
  # For non-dhcp net_ip, normally router IP
  [net_gate]=""
)

DL_TOOL=(wget -qO-)
if curl --version &>/dev/null; then
  DL_TOOL=(curl -sL)
elif ! "${DL_TOOL[@]}" --version &>/dev/null; then
  echo "Can't detect download tool" >&2
  exit 1
fi

# Load hooks
# shellcheck disable=SC1090
. <(set -x; "${DL_TOOL[@]}" "${LS_BASE_URL}/pve/lxc/deploy-axway-int1/hooks.sh") || exit

if ! (return 0 2>/dev/null); then
  # shellcheck disable=SC1090
  . <(set -x; "${DL_TOOL[@]}" "${LS_BASE_URL}/pve/lxc-entrypoint.sh") || exit
fi
