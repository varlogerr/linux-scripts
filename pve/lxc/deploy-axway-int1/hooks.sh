#!/usr/bin/env bash

#
# 'lxc_after_create_hook_' prefixed functions will serve as callbacks
# after container creation. Functions will be ordered by versions.
# Imported to the function CT_ID variable contains container ID.
# Find useful `lxc_do` functions in the pve/func/lxc.sh file
#

# shellcheck disable=SC2317
# shellcheck disable=SC1091
lxc_after_create_hook_500_centos_like_provision() (
  deploy_sys_clean_tool() (
    declare location=/usr/bin/sys-clean.sh

    sys_clean() (
      set -x
      dnf autoremove -qy
      dnf clean all -qy --enablerepo='*'
      find /tmp /var/tmp /var/cache/dnf -mindepth 1 -maxdepth 1 -exec rm -rf {} \;
      find /var/log/ -type f -exec truncate -s 0 {} \;
    )

    {
      declare -f sys_clean
      echo 'if ! (return 0 2>/dev/null); then sys_clean; fi'
    } | (set -x; tee "${location}" >/dev/null; chmod +x "${location}")
  )

  ensure_almalinux_rpm_gpg() {
    (. /etc/os-release 2>/dev/null; grep -qFx "almalinux-8" <<< "${ID}-${VERSION_ID%%.*}") || return 0

    # https://serverfault.com/a/1160095
    # https://support.cpanel.net/hc/en-us/articles/20661015485463-RPM-GPG-KEY-AlmaLinux-Fail-to-update
    (set -x; rpm --import https://repo.almalinux.org/almalinux/RPM-GPG-KEY-AlmaLinux)
  }

  install_toolbox() {
    declare -ar TOOLBOX=(
      bash-completion
      bind-utils
      curl
      htop
      man
      nano
      neovim
      openssh-server
      tar
      tree
      tmux
      wget
    )

    set -x

    dnf clean all -qy --enablerepo='*'
    dnf install -qy epel-release
    dnf install -qy "${TOOLBOX[@]}"

    # Replace vim with neovim
    ln -sf /usr/bin/nvim /usr/bin/vim
  }

  install_lamp() {
    declare -r PHP_V=8.2

    declare -ar SERVER=(
      httpd mod_ssl
      php php-cli php-gd php-intl php-mbstring php-mcrypt
      php-mysqlnd php-pecl-redis5 php-pecl-zip php-pdo php-xml
    )

    declare -a REPOS; REPOS=(
      epel-release
      "https://rpms.remirepo.net/enterprise/remi-release-$(rpm -E '%{rhel}').rpm"
    )

    (set -x
      dnf install -qy "${REPOS[@]}" \
      && dnf module reset -qy php \
      && dnf module install -qy "php:remi-${PHP_V}" \
      && dnf install -qy "${SERVER[@]}"
    )

    echo "LoadModule mpm_prefork_module modules/mod_mpm_prefork.so" \
    | (set -x; tee /etc/httpd/conf.modules.d/*-mpm.conf >/dev/null)

    (set -x; systemctl enable --now httpd)

    (set -x
      bash <(
        curl --fail -skL https://downloads.mariadb.com/MariaDB/mariadb_repo_setup
      ) --skip-maxscale --skip-tools \
      && dnf install -qy mariadb-server \
      && systemctl enable --now mariadb
    )
  }

  sys_upgrade() { dnf upgrade -qy; }
  sys_clean() { sys-clean.sh; }
  is_centos_like() (. /etc/os-release 2>/dev/null; grep -qF " centos " <<< " ${ID} ${ID_LIKE} ")

  # Start the container
  lxc_do "${CT_ID}" ensure_up 10 || return

  # Provision the container
  lxc_do "${CT_ID}" exec_callback -v is_centos_like || {
    (set -x; pct stop "${CT_ID}")
    return 0
  }
  lxc_do "${CT_ID}" exec_callback deploy_sys_clean_tool
  lxc_do "${CT_ID}" exec_callback ensure_almalinux_rpm_gpg
  lxc_do "${CT_ID}" exec_callback install_toolbox
  pct exec "${CT_ID}" -- sh -c "
    set -x
    mkdir -p /etc/tmux
    curl -sL '${LS_BASE_URL}/linux/assets/tmux/base.conf' -o /etc/tmux/base.conf
    tee /root/.tmux.conf /etc/skel/.tmux.conf <<< 'source-file /etc/tmux/base.conf' >/dev/null
  "
  lxc_do "${CT_ID}" exec_callback install_lamp
  lxc_do "${CT_ID}" exec_callback -v sys_upgrade
  lxc_do "${CT_ID}" exec_callback sys_clean

  lxc_do "${CT_ID}" ensure_down
)

lxc_after_create_hook_900_ensure_booted() {
  "${CT[onboot]:-false}" && lxc_do "${CT_ID}" ensure_up
}
