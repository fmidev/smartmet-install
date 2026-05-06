# Kickstart for the SmartMet Data Processing Server

Unattended-install recipe for AlmaLinux/Rocky 10. Walks Anaconda through OS
install with a sane disk layout and partitioning, then runs
`smartmet-install-10.sh` in `%post`. The host comes up with the SmartMet
data-processing stack installed, ready for `passwd smartmet`,
`smbpasswd -a smartmet`, and (optionally) a static-IP switchover.

This implements **Tier 1** of [`PHASE2_PLAN.md`](../PHASE2_PLAN.md).

## What it does

| Stage   | Action                                                                         |
|---------|--------------------------------------------------------------------------------|
| `%pre`  | Detects firmware (BIOS vs UEFI) and disk count (1 or ≥2). Writes the partitioning include. Refuses to proceed with the placeholder SSH key. |
| Anaconda | Partitions, installs `@^minimal-environment + @core + chrony, vim, tar, curl, wget`, locks root, creates the `admin` sudo user with your SSH key. |
| `%post` | Curls `smartmet-install-10.sh` from this repo and runs it inside the chroot. Writes `/root/FIRST_BOOT_NOTES.txt` with remaining steps. |
| Reboot  | Ejects ISO and reboots.                                                        |

## Disk layout produced

The `%pre` script picks layout based on how many non-removable disks are
attached:

### Single-disk host (one VG, all in one)

```
disk → /boot/efi (or biosboot) | /boot | LVM PV → vg_smartmet
                                                  ├── lv_root      30 GiB  (xfs, /)
                                                  ├── lv_swap       8 GiB  (swap)
                                                  └── lv_smartmet  rest    (xfs, /smartmet)  ← grows
```

### Two-disk host (OS / data split)

```
smallest disk → /boot/efi | /boot | LVM PV → vg_root      ├── lv_root      30 GiB  (xfs, /)
                                              └── lv_swap       8 GiB  (swap)

largest  disk → LVM PV → vg_smartmet  └── lv_smartmet  100 % of disk  (xfs, /smartmet)  ← grows
```

In both layouts `/smartmet` is the only LV that has `--grow`, and it's the
LV you extend later when adding capacity:

```
# after enlarging the underlying disk in Proxmox
lvextend -l +100%FREE /dev/vg_smartmet/lv_smartmet
xfs_growfs /smartmet
```

## Customize before deploying

Open `smartmet-10.ks` and replace the SSH key placeholder:

```diff
-sshkey --username=admin "REPLACE_WITH_YOUR_SSH_PUBKEY"
+sshkey --username=admin "ssh-ed25519 AAAAC3Nza... admin@laptop"
```

The `%pre` script sanity-checks for the placeholder string and aborts the
install if it's still there, so a forgotten edit can't accidentally produce
a key-less host.

If you want a non-default hostname baked in, change the `network` line:

```diff
-network --bootproto=dhcp --device=link --activate --hostname=smartmet
+network --bootproto=dhcp --device=link --activate --hostname=smartmet01
```

(For per-host hostname without forking the kickstart, leave the default and
override at boot via `inst.ks.sendmac` + a templating service, or set the
hostname after install with `hostnamectl set-hostname`.)

## Host the kickstart

Pick whichever of these is easiest:

| Option | How |
|--------|-----|
| Raw GitHub URL (after PR is merged) | `https://raw.githubusercontent.com/fmidev/smartmet-install/master/kickstart/smartmet-10.ks` — but **only viable if your edits live in a public fork**, since the placeholder check refuses the unedited upstream copy. |
| Internal HTTP(S) server | Drop the edited `smartmet-10.ks` on any web server reachable from the install network. |
| Embedded in a custom ISO | `mkksiso smartmet-10.ks original.iso smartmet-install.iso` — produces a one-shot ISO that boots straight into the kickstart. Good for air-gapped or USB installs. |
| Proxmox snippet | Upload to a Proxmox snippets storage and reference it via PXE/HTTP. |

## Boot the install

At the AlmaLinux/Rocky 10 ISO boot menu, press `e` and append to the
kernel cmdline:

```
inst.ks=https://your-host/path/smartmet-10.ks
```

### Static IP at install time (recommended for production)

Append the standard initrd network args:

```
inst.ks=https://your-host/path/smartmet-10.ks ip=192.0.2.10::192.0.2.1:255.255.255.0:smartmet01:eth0:none nameserver=192.0.2.53
```

Format is `ip=<client>::<gw>:<netmask>:<hostname>:<dev>:<autoconf>`. These
override the kickstart's default DHCP `network` line.

### DHCP at install time, fixed IP after install

Acceptable for first deployment. Boot with just `inst.ks=...`, let DHCP
serve the install, then on first login follow the `nmcli` snippet in
`/root/FIRST_BOOT_NOTES.txt`.

## Proxmox specifics

Two practical options:

1. **ISO + boot args.** Upload the AlmaLinux 10 ISO to the local-iso
   storage, attach to a new VM, and at the GRUB prompt edit the kernel
   line as above. Single-disk and two-disk VMs both work — the kickstart
   auto-detects.

2. **Custom ISO with embedded kickstart.** Run `mkksiso` once on a Linux
   workstation, upload the resulting ISO. New VMs boot it and run end-to-end
   with no manual intervention. Pair with `qm set <id> --boot order=cdrom`.

A future Tier 2 will replace this with a Proxmox cloud-init template that
provisions a VM in <60 s without an ISO; see `PHASE2_PLAN.md`.

## Limits / caveats

- **Filename is `smartmet-10.ks`** — only AlmaLinux/Rocky 10 has been
  exercised. The same kickstart should work on 9 (the `%post` picks
  `smartmet-install-9.sh` automatically), but Anaconda directives drift
  between EL versions; if you target 9, smoke-test first.
- **Disk auto-detection picks by size.** If your host has multiple disks
  and the OS disk isn't the smallest, override by hard-coding `OS_DISK`
  and `DATA_DISK` in the `%pre` script.
- **No LUKS encryption.** Add `--encrypted --passphrase=...` to the
  `logvol` lines if you need it (not unattended without a static
  passphrase, which is its own threat model).
- **Placeholder check is best-effort.** If you somehow ship the unedited
  kickstart and `%pre` fails to find the placeholder string (e.g.
  Anaconda mounts it under a different path), the install bails. Verify
  the resulting system has *only your* admin SSH key before exposing it.
