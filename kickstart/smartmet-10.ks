# Kickstart for the SmartMet Data Processing Server on AlmaLinux/Rocky 10.
#
# Usage: boot the AlmaLinux/Rocky 10 minimal ISO with kernel arg
#   inst.ks=<URL-to-this-file>
# (See kickstart/README.md for hosting + boot-arg details.)
#
# Disk layout (auto-detected from how many disks the host has):
#   1 disk  → ONE VG vg_smartmet on the disk; lv_root 30G, lv_swap 8G,
#             lv_smartmet uses the rest and is left growable.
#   ≥2 disks → smallest disk is the OS disk (vg_root: lv_root 30G, lv_swap 8G);
#             largest disk is the data disk (vg_smartmet: lv_smartmet, all of it).
# In both cases lv_smartmet is the only LV that grows the underlying VG when
# the disk is enlarged later (lvextend + xfs_growfs).
#
# After OS install the %post stage curls and runs smartmet-install-10.sh from
# this repo, leaving the host ready for `passwd smartmet` / `smbpasswd -a smartmet`.

#--- system identity ---------------------------------------------------------
lang en_US.UTF-8
keyboard --vckeymap=us --xlayouts='us'
timezone Etc/UTC

# Default to DHCP at install time. For a static IP, append boot args at ISO
# boot, e.g.
#   ip=192.0.2.10::192.0.2.1:255.255.255.0:smartmet01:eth0:none nameserver=192.0.2.53
# Anaconda will pick those up over this default.
network --bootproto=dhcp --device=link --activate --hostname=smartmet

#--- accounts ----------------------------------------------------------------
# Root login is locked. Administer via the sudo user below.
rootpw --lock

# REPLACE-BEFORE-USE — operator-customizable admin user and SSH key. The
# kickstart will fail by design if these placeholders aren't replaced, so
# nobody accidentally deploys with the default key.
user --name=admin --groups=wheel --gecos="SmartMet admin" --lock
sshkey --username=admin "REPLACE_WITH_YOUR_SSH_PUBKEY"

#--- security & services -----------------------------------------------------
selinux --enforcing
firewall --enabled --service=ssh
services --enabled=chronyd,sshd,firewalld
authselect --useshadow --passalgo=sha512

#--- partitioning (filled in by %pre) ---------------------------------------
%include /tmp/part-include

bootloader --location=mbr --append="rhgb quiet"

#--- packages ----------------------------------------------------------------
%packages
@^minimal-environment
@core
chrony
vim-enhanced
bash-completion
tar
curl
wget
%end

#--- pre: detect disks and firmware, write part-include ---------------------
%pre --interpreter=/bin/bash --erroronfail --log=/tmp/ks-pre.log
set -e

# Firmware detection
if [ -d /sys/firmware/efi ]; then
  FW=uefi
else
  FW=bios
fi

# Discover non-removable, non-loop disks, sorted ascending by size
mapfile -t SORTED < <(
  lsblk -d -bn -o NAME,TYPE,RM,SIZE \
    | awk '$2=="disk" && $3==0 {print $4, $1}' \
    | sort -n
)

if [ "${#SORTED[@]}" -lt 1 ]; then
  echo "FATAL: no usable disks detected" >&2
  exit 1
fi

OS_DISK=$(awk '{print $2}' <<< "${SORTED[0]}")
if [ "${#SORTED[@]}" -ge 2 ]; then
  DATA_DISK=$(awk '{print $2}' <<< "${SORTED[-1]}")
else
  DATA_DISK=""
fi

# Boot partitions per firmware
case "$FW" in
  uefi)
    BOOT_PARTS=$(cat <<EOB
part /boot/efi --fstype=efi --size=600 --ondisk=${OS_DISK}
part /boot     --fstype=xfs --size=1024 --ondisk=${OS_DISK}
EOB
)
    ;;
  bios)
    BOOT_PARTS=$(cat <<EOB
part biosboot --fstype=biosboot --size=1 --ondisk=${OS_DISK}
part /boot    --fstype=xfs --size=1024 --ondisk=${OS_DISK}
EOB
)
    ;;
esac

if [ -n "$DATA_DISK" ]; then
  cat > /tmp/part-include <<EOF
ignoredisk --only-use=${OS_DISK},${DATA_DISK}
clearpart --all --initlabel --drives=${OS_DISK},${DATA_DISK}
${BOOT_PARTS}
part pv.os   --size=1 --grow --ondisk=${OS_DISK}
part pv.data --size=1 --grow --ondisk=${DATA_DISK}
volgroup vg_root     pv.os
volgroup vg_smartmet pv.data
logvol /         --vgname=vg_root     --name=lv_root     --fstype=xfs  --size=30720
logvol swap      --vgname=vg_root     --name=lv_swap     --fstype=swap --size=8192
logvol /smartmet --vgname=vg_smartmet --name=lv_smartmet --fstype=xfs  --size=1 --grow
EOF
else
  cat > /tmp/part-include <<EOF
ignoredisk --only-use=${OS_DISK}
clearpart --all --initlabel --drives=${OS_DISK}
${BOOT_PARTS}
part pv.all --size=1 --grow --ondisk=${OS_DISK}
volgroup vg_smartmet pv.all
logvol /         --vgname=vg_smartmet --name=lv_root     --fstype=xfs  --size=30720
logvol swap      --vgname=vg_smartmet --name=lv_swap     --fstype=swap --size=8192
logvol /smartmet --vgname=vg_smartmet --name=lv_smartmet --fstype=xfs  --size=1 --grow
EOF
fi

# Refuse to proceed with placeholder SSH key
if grep -q REPLACE_WITH_YOUR_SSH_PUBKEY /run/install/repo/ks.cfg 2>/dev/null \
   || grep -rq REPLACE_WITH_YOUR_SSH_PUBKEY /tmp/ks-script*.sh 2>/dev/null; then
  echo "FATAL: kickstart still has the placeholder SSH key. Replace it before deploying." >&2
  exit 1
fi
%end

#--- post: install SmartMet stack -------------------------------------------
%post --interpreter=/bin/bash --erroronfail --log=/root/ks-post.log
set -euo pipefail

# Mark the install script's preflight step as already done — /smartmet is
# guaranteed mounted by the partitioning above, and the script's interactive
# prompt would otherwise hang inside %post.
mkdir -p /var/lib/smartmet-install
touch /var/lib/smartmet-install/preflight.done

# Pick the install script for this OS major
. /etc/os-release
case "${VERSION_ID%%.*}" in
  10) SCRIPT=smartmet-install-10.sh ;;
  9)  SCRIPT=smartmet-install-9.sh  ;;
  8)  SCRIPT=smartmet-install-8.sh  ;;
  *)  echo "Unsupported OS ${ID} ${VERSION_ID}" >&2; exit 1 ;;
esac

URL="https://raw.githubusercontent.com/fmidev/smartmet-install/master/${SCRIPT}"
curl --fail --location --silent --show-error "$URL" -o "/tmp/${SCRIPT}"
chmod +x "/tmp/${SCRIPT}"
"/tmp/${SCRIPT}"

# Note for the operator: the smartmet user still needs Linux + Samba passwords.
cat > /root/FIRST_BOOT_NOTES.txt <<'NOTE'
SmartMet Data Processing Server install completed via kickstart.

Remaining manual steps (see also the README at fmidev/smartmet-install):

  1. Set the smartmet user's Linux password:
       passwd smartmet
  2. Set the smartmet user's Samba password (for the SMB share):
       smbpasswd -a smartmet
  3. (Optional) Set a static IP if the install used DHCP:
       nmcli con mod "<connection>" ipv4.method manual \
         ipv4.addresses 192.0.2.10/24 ipv4.gateway 192.0.2.1 \
         ipv4.dns 192.0.2.53
       nmcli con up "<connection>"
  4. (Optional) Install forecast model packages:
       dnf install smartmet-data-gfs smartmet-data-gem smartmet-data-metar
NOTE
%end

reboot --eject
