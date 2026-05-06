#!/usr/bin/env bash
# Install the SmartMet Open server stack on AlmaLinux 10 / Rocky 10 / RHEL 10.
#
# Resumable: each step writes a marker in /var/lib/smartmet-install/. If the
# script fails or is interrupted, just re-run it — completed steps are
# skipped. Pass --force to redo every step from scratch.

set -euo pipefail

log()  { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run as root."

FORCE=0
case "${1:-}" in
  --force) FORCE=1 ;;
  -h|--help)
    sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  "") ;;
  *) die "Unknown argument: $1 (use --force or --help)" ;;
esac

# shellcheck disable=SC1091
. /etc/os-release || die "Cannot read /etc/os-release."
case "${ID}:${VERSION_ID%%.*}" in
  almalinux:10|rocky:10|rhel:10|centos:10) ;;
  *) die "This script targets RHEL 10 family. Detected: ${ID} ${VERSION_ID}." ;;
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
  dnf -y install https://download.fmi.fi/smartmet-open/rhel/10/x86_64/smartmet-open-release-latest-10.noarch.rpm
}

install_dnf_utils() {
  dnf -y install dnf-plugins-core yum-utils
}

add_docker_repo() {
  if [ ! -f /etc/yum.repos.d/docker-ce.repo ]; then
    dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
  fi
}

enable_crb() {
  dnf config-manager --set-enabled crb
}

install_epel() {
  dnf -y install epel-release
}

exclude_eccodes() {
  dnf config-manager --setopt="epel.exclude=eccodes*" --save
  dnf config-manager --set-disabled epel-source 2>/dev/null || true
}

disable_pgsql_modules() {
  # RHEL 10 mostly ships plain packages, but disabling streams that may
  # still be present is cheap insurance against version drift.
  for stream in 16 17; do
    dnf -y module disable "postgresql:${stream}" 2>/dev/null || true
  done
}

install_smartmet_base() {
  dnf -y install smartmet-base-international
}

system_update() {
  dnf -y update
}

step preflight              check_smartmet_mount
step add-smartmet-repo      add_smartmet_repo
step install-dnf-utils      install_dnf_utils
step add-docker-repo        add_docker_repo
step enable-crb             enable_crb
step install-epel           install_epel
step exclude-eccodes        exclude_eccodes
step disable-pgsql-modules  disable_pgsql_modules
step install-smartmet-base  install_smartmet_base
step system-update          system_update

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
