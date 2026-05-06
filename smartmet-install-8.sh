#!/usr/bin/env bash
# Install the SmartMet Open server stack on AlmaLinux 8 / Rocky 8 / RHEL 8.
#
# Resumable: each step writes a marker in /var/lib/smartmet-install/. If the
# script fails or is interrupted, just re-run it — completed steps are
# skipped. Pass --force to redo every step from scratch.
#
# RHEL 8 maintenance support runs until 2029-05-31. New deployments should
# prefer smartmet-install-9.sh or smartmet-install-10.sh.

set -euo pipefail

log()  { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run as root."

FORCE=0
case "${1:-}" in
  --force) FORCE=1 ;;
  -h|--help)
    sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  "") ;;
  *) die "Unknown argument: $1 (use --force or --help)" ;;
esac

# shellcheck disable=SC1091
. /etc/os-release || die "Cannot read /etc/os-release."
case "${ID}:${VERSION_ID%%.*}" in
  almalinux:8|rocky:8|rhel:8|centos:8) ;;
  *) die "This script targets RHEL 8 family. Detected: ${ID} ${VERSION_ID}." ;;
esac

STATE_DIR=/var/lib/smartmet-install
mkdir -p "$STATE_DIR"

step() {
  local id=$1 fn=$2
  local marker="$STATE_DIR/${id}.done"
  if [ -f "$marker" ] && [ "$FORCE" -eq 0 ]; then
    log "[skip] ${id} (already done — pass --force to redo)"
    return 0
  fi
  log "[run]  ${id}"
  "$fn"
  touch "$marker"
}

check_smartmet_mount() {
  if ! mountpoint -q /smartmet; then
    warn "/smartmet is not a separate mountpoint. Forecast model packages can fill"
    warn "the root volume. Mount a dedicated partition at /smartmet and re-run."
    read -r -p "Continue anyway? [y/N] " ans
    [[ "${ans:-}" =~ ^[Yy]$ ]] || die "Aborted."
  fi
}

add_smartmet_repo() {
  dnf -y install https://download.fmi.fi/smartmet-open/rhel/8/x86_64/smartmet-open-release-latest-8.noarch.rpm
}

install_dnf_utils() {
  dnf -y install dnf-plugins-core yum-utils
}

add_docker_repo() {
  if [ ! -f /etc/yum.repos.d/docker-ce.repo ]; then
    dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
  fi
}

enable_powertools() {
  dnf config-manager --set-enabled powertools
}

install_epel() {
  dnf -y install epel-release
}

exclude_eccodes() {
  dnf config-manager --setopt="epel.exclude=eccodes*" --save
  dnf config-manager --set-disabled epel-source
}

disable_pgsql_module() {
  dnf -y module disable postgresql:12 || true
}

install_smartmet_base() {
  dnf -y install smartmet-base-international
}

system_update() {
  dnf -y update
}

step preflight             check_smartmet_mount
step add-smartmet-repo     add_smartmet_repo
step install-dnf-utils     install_dnf_utils
step add-docker-repo       add_docker_repo
step enable-powertools     enable_powertools
step install-epel          install_epel
step exclude-eccodes       exclude_eccodes
step disable-pgsql-module  disable_pgsql_module
step install-smartmet-base install_smartmet_base
step system-update         system_update

cat <<EOF

---------------------------------------------------------------
SmartMet base install completed.

Next steps:
  1. passwd smartmet                 # set Linux login password
  2. smbpasswd -a smartmet           # set Samba password
  3. \$EDITOR /etc/php.d/smartmet.ini # set date.timezone
  4. (optional) dnf install smartmet-data-{gfs,gem,metar}
  5. systemctl enable --now httpd smb
  6. Reboot, then verify:
       systemctl status httpd smb postgresql
       curl -I http://localhost/

State: $STATE_DIR  (delete this directory or pass --force to redo every step)
---------------------------------------------------------------
EOF
