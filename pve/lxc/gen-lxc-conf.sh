#!/usr/bin/env bash

LS_BASE_URL="https://github.com/varlogerr/linux-scripts/raw/${LS_BASE_BRANCH-master}"

# shellcheck disable=SC2034
if curl --version &>/dev/null; then
  DL_TOOL=(curl -sL)
elif wget --version &>/dev/null; then
  DL_TOOL=(wget -qO-)
else
  echo "Can't detect download tool" >&2
  exit 1
fi

if ! (return 0 2>/dev/null); then
  # shellcheck disable=SC2016
  printf -- '%s\n\n%s\n' \
    '#!/usr/bin/env bash' \
    'LS_BASE_URL="https://github.com/varlogerr/linux-scripts/raw/${LS_BASE_BRANCH-master}"'

  echo

  # shellcheck disable=SC1090
  (set -o pipefail
    (set -x; "${DL_TOOL[@]}" "${LS_BASE_URL}/pve/lxc-entrypoint.sh") \
    | grep -Fx -A 9999 '##### {{ CT_DEFAULTS_MARKER }}' | tail -n +2 \
    | grep -Fx -B 9999 '##### {{/ CT_DEFAULTS_MARKER }}' | head -n -1 \
    | sed -e 's/^\(\s*declare\s\+-A\s\+\)CT_DEFAULTS=/\1CT=/' \
          -e 's/^\(\s*\[\)!/\1/'
  )

  echo

  cat <<'EOL'
DL_TOOL=(wget -qO-)
if curl --version &>/dev/null; then
  DL_TOOL=(curl -sL)
elif ! "${DL_TOOL[@]}" --version &>/dev/null; then
  echo "Can't detect download tool" >&2
  exit 1
fi

#
# 'lxc_after_create_hook_' prefixed functions will serve as callbacks
# after container creation. Functions will be ordered by versions.
# Imported to the function CT_ID variable contains container ID.
# Find useful `lxc_do` functions in the pve/func/lxc.sh file
#
{ ### HOOKS BLOCK
  lxc_after_create_hook_500_demo() {
    # lxc_do "${CT_ID}" conf_vpn_ready
    # lxc_do "${CT_ID}" conf_docker_ready
    :
  }
} ### HOOKS BLOCK

if ! (return 0 2>/dev/null); then
  # shellcheck disable=SC1090
  . <(set -x; "${DL_TOOL[@]}" "${LS_BASE_URL}/pve/lxc-entrypoint.sh") || exit
fi
EOL
fi
