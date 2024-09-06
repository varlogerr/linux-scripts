#!/usr/bin/env bash

declare -F ls_linux_func_dummy >/dev/null || {
  # shellcheck disable=SC1090
  . <(set -x; "${DL_TOOL[@]}" "${LS_BASE_URL}/linux/func.sh") || return 2>/dev/null || exit
}

##################################
### CONTAINER CONFIG FUNCTIONS ###
##################################

# USAGE:
#   lxc_do CONAINTER_ID NESTED_FUNC [ARGS...]
# shellcheck disable=SC2317
lxc_do() (
  # USAGE: conf_vpn_ready
  conf_vpn_ready() {
    # https://pve.proxmox.com/wiki/OpenVPN_in_LXC
    _append_to_conf_file \
      "lxc.mount.entry: /dev/net dev/net none bind,create=dir 0 0" \
      "lxc.cgroup2.devices.allow: c 10:200 rwm"
  }

  # USAGE: conf_docker_ready
  conf_docker_ready() {
    # https://gist.github.com/varlogerr/9805998a6ac9ad4fa930a07951e9a3dc
    _append_to_conf_file \
      "lxc.apparmor.profile: unconfined" \
      "lxc.cgroup2.devices.allow: a" \
      "lxc.cap.drop:"
  }

  # Execute a callback in a running container
  # USAGE: exec_callback [-v] CALLBACK
  # OPTIONS:
  #   -v  Verbose
  exec_callback() {
    declare cbk="${1}"
    declare verbose=false
    if [[ ${cbk} == '-v' ]]; then
      verbose=true
      cbk="${2}"
    fi
    declare cbk_txt; cbk_txt="$(declare -f "${cbk}")"

    (
      ${verbose} && set -x
      pct exec "${CT_ID}" -- bash -c "${cbk_txt}; ${cbk}"
    )
  }

  # Ensure container is running wait it to warm up
  # USAGE: ensure_up [WARMUP=0]
  ensure_up() (
    declare warm="${1-0}"

    pct status "${CT_ID}" | grep -q ' running$' || (
      set -x
      pct start "${CT_ID}" || return
      lxc-wait "${CT_ID}" --state="RUNNING" -t 10
    )

    get_uptime() { grep -o "^[0-9]\\+" /proc/uptime 2>/dev/null; }

    # Give it time to warm up the services
    declare uptime; uptime="$(exec_callback -v get_uptime)"
    warm="$(( warm - "${uptime:-0}" ))"

    if [[ "${warm}" -gt 0 ]]; then (set -x; sleep "${warm}" ); fi
  )

  # Ensure container is stopped
  # USAGE: ensure_down
  ensure_down() (
    if pct status "${CT_ID}" | grep -q ' running$'; then
      set -x
      pct stop "${CT_ID}" || return
    fi
  )

  _append_to_conf_file() {
    printf -- '%s\n' "${@}" | (set -x; tee -a -- "${CONF_FILE}" >/dev/null)
  }

  declare CT_ID="${1}"
  declare FUNC="${2}"
  declare CONF_FILE=/etc/pve/lxc/${CT_ID}.conf

  "${FUNC}" "${@:3}"
)

##################################
### CONTAINER CREATE FUNCTIONS ###
##################################

lxc_create_ct() {
  declare storage; storage="$(lxc_automanage_container_storage)" || return
  declare template_url; template_url="$(lxc_detect_template_url "${CT[template]}")" || return
  declare template_path; template_path="$(lxc_download_template "${template_url}")" || return

  declare net="name=eth0,bridge=${CT[net_bridge]},ip=${CT[net_ip]}"
  net+="${CT[net_gate]:+,gw=${CT[net_gate]}}"

  declare -a create_cmd=(
    pct create "${CT[id]}" "${template_path}"
    -password "${CT[root_pass]}"
    -storage "${storage}"
    -unprivileged "$("${CT[privileged]}" &>/dev/null; echo $?)"
    -onboot "$(! "${CT[onboot]}" &>/dev/null; echo $?)"
    -net0 "${net}"
  )

  [[ -n "${CT[hostname]}" ]] && create_cmd+=(-hostname "${CT[hostname]}")
  [[ -n "${CT[ram]}" ]] && create_cmd+=(-memory "${CT[ram]}")
  [[ -n "${CT[cores]}" ]] && create_cmd+=(-cores "${CT[cores]}")
  [[ -n "${CT[disk]}" ]] && create_cmd+=(-rootfs "${storage}:${CT[disk]}")

  (set -o pipefail
    (set -x; "${create_cmd[@]}") 3>&1 1>&2 2>&3 \
    | sed -e 's/\( -password \)\(.\+\)\( -storage .\+\)/\1*****\3/'
  ) 3>&1 1>&2 2>&3
  declare rc=${?}

  (set -x; rm "${template_path}")
  return ${rc}
}

# USAGE:
#   lxc_detect_template_url TEMPLATE_NAME_HINT || { ERR BLOCK }
#   # => TEMPLATE_URL
lxc_detect_template_url() {
  declare base_templates_url=http://download.proxmox.com/images/system

  declare template_rex; template_rex="$(escape_sed_expr "${1}")"
  declare templates_page; templates_page="$(set -x; "${DL_TOOL[@]}" "${base_templates_url}")" || return

  declare template_file; template_file="$(
    sed -n 's/.*href="\('"${template_rex}"'[^"]*\.tar\.\(gz\|xz\|zst\)\)".*/\1/p' <<< "${templates_page}" \
    | sort -V | tail -n 1 | grep '.\+'
  )" || {
    echo "Can't detect template: ${1}"
    return 1
  }

  printf -- '%s/%s\n' "${base_templates_url}" "${template_file}"
}

# USAGE:
#   lxc_download_template TEMPLATE_URL || { ERR BLOCK }
#   # => TEMPLATE_TMP_FILE_PATH
lxc_download_template() {
  declare template_url="${1}"
  declare ext
  declare template_path

  ext="$(grep -o '\.tar\.[^\.]\+$' <<< "${template_url}")"
  template_path="$(set -x; mktemp --suffix "${ext}")" || return

  (set -x; "${DL_TOOL[@]}" "${template_url}" > "${template_path}") || return
  echo "${template_path}"
}

# USAGE:
#   lxc_automanage_container_storage || { ERR BLOCK }
#   # => CONTAINER_STORAGE
lxc_automanage_container_storage() {
  pvesm status -content rootdir | tail -n +2 | cut -d' ' -f1 | grep '.\+' || {
    echo "Can't automanage storage"
    return 1
  }
}

# USAGE:
#   lxc_automanage_id || { ERR BLOCK }
#   # => CONTAINER_ID
lxc_automanage_id() { pvesh get /cluster/nextid; }
