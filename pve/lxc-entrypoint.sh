#!/usr/bin/env bash

# shellcheck disable=SC1090
. <(set -x; "${DL_TOOL[@]}" "${LS_BASE_URL}/pve/func/lxc.sh") || exit

##### {{ CT_DEFAULTS_MARKER }}
#####
# For default values leave fields blank or remove it
#####
# shellcheck disable=SC2034
declare -A CT_DEFAULTS=(
  # Defaults to automanage
  [!id]=''
  # Best guess hint from:
  # * http://download.proxmox.com/images/system
  # Defaults to ubuntu
  [template]='ubuntu'
  # Defaults to template default. In GB
  [disk]=''
  # Defaults to template default. In MB
  [ram]=''
  # Example: 2
  # Defaults to template default
  [cores]=''
  # Defaults to false
  [onboot]=false
  # Defaults to false
  [privileged]=false
  # Defaults to empty value
  [root_pass]=''
  # Defaults to unset
  [hostname]=''
  # Defaults to 'vmbr0'
  [net_bridge]='vmbr0'
  # Example: 192.0.0.5/24
  # Defaults to 'dhcp'
  [net_ip]="dhcp"
  # For non-dhcp net_ip, normally router IP
  [net_gate]=""
  # DISABLEIP6="no"
  # MTU=""
  # SD=""
  # NS=""
  # MAC=""
  # VLAN=""
  # SSH="no"
  # VERB="no"
)
##### {{/ CT_DEFAULTS_MARKER }}

_iife_merge_defaults() {
  declare -a callback

  declare varname; for varname in "${!CT_DEFAULTS[@]}"; do
    callback=(printf -- '%s\n' "${CT_DEFAULTS[${varname}]}")

    if [[ ${varname:0:1} == '!' ]]; then
      varname="${varname:1}"
      callback=("lxc_automanage_${varname}")
    fi

    [[ -n "${CT[${varname}]}" ]] && continue
    CT["${varname}"]="$("${callback[@]}")"
  done
}; _iife_merge_defaults; unset _iife_merge_defaults

lxc_create_ct || exit

# Collect all after callbacks
_iife_run_after() {
  declare -a _int_callbacks

  mapfile -t _int_callbacks <<< "$(
    set -o pipefail
    declare -F | rev | cut -d' ' -f1 | rev \
    | sort -V | grep '^lxc_after_create_hook_'
  )" || return 0

  echo '[ HOOKS ]' >&2
  declare _int_cbk_ctr=0
  declare _int_cbk; for _int_cbk in "${_int_callbacks[@]}"; do
    [[ ${_int_cbk_ctr} -gt 0 ]] && echo >&2

    { printf -- '##### HOOK START %s\n' "${_int_cbk#lxc_after_create_hook_*}" | sed 's/^/  /'; } >&2

    {
      { CT_ID="${CT[id]}" "${_int_cbk}" | sed 's/^/    /'; } \
      3>&2 2>&1 1>&3 | sed 's/^/    /'
    } 3>&2 2>&1 1>&3

    { printf -- '##### HOOK END %s\n' "${_int_cbk#lxc_after_create_hook_*}" | sed 's/^/  /'; } >&2

    (( _int_cbk_ctr++ ))
  done
  echo '[/ HOOKS ]' >&2
}; _iife_run_after; unset _iife_run_after
