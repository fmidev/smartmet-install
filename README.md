# Install a SmartMet Data Processing Server

Install scripts and instructions for setting up an FMI **SmartMet Data
Processing Server** on RHEL-family Linux. AlmaLinux 10 or Rocky Linux 10
is recommended for new deployments; 9 and 8 are also supported.

> **Not to be confused with** the *SmartMet API Server* (a separate FMI
> product). This repo provisions the data-processing host that ingests and
> manipulates forecast model data; the API server, if you also run one, is
> a different deployment.

## What you get

After running the installer, the host runs:

- The SmartMet data-processing stack (`smartmet-base-international` meta-package)
- PostgreSQL (FMI build)
- Samba share `smartmet` for editing data files from a workstation
- A `smartmet` system user that owns runtime data under `/smartmet`
- Docker CE engine (enabled in `%post`; the FMI processing services
  themselves run in containers)
- `firewalld` and `fail2ban` for basic hardening

## Choose the right script

| OS                                  | Script                  | Notes                       |
|-------------------------------------|-------------------------|-----------------------------|
| AlmaLinux 10 / Rocky 10 / RHEL 10   | `smartmet-install-10.sh`| **Recommended for new installs** |
| AlmaLinux 9 / Rocky 9 / RHEL 9      | `smartmet-install-9.sh` | Supported until 2032        |
| AlmaLinux 8 / Rocky 8 / RHEL 8      | `smartmet-install-8.sh` | Supported until 2029        |
| RHEL 7                              | `smartmet-install-7.sh` | **EOL 2024-06-30, do not use** |

## Server prerequisites

| Resource    | Minimum   | Recommended            |
|-------------|-----------|------------------------|
| CPU         | 4 cores   | 8+ cores               |
| RAM         | 8 GB      | 16 GB                  |
| Disk (OS)   | 20 GB     | 40 GB                  |
| Disk (data) | 100 GB    | 500 GB+ on `/smartmet` |
| Network     | Static IP, NTP | Static IP, NTP, DNS |

`/smartmet` should be a separate, large partition or LVM volume — forecast
model packages (GFS, GEM, …) write large NetCDF/GRIB files there.

## 1. Install the OS

Boot the *minimal* ISO of one of:

- AlmaLinux 10: <https://almalinux.org/get-almalinux/>
- Rocky Linux 10: <https://rockylinux.org/download>

During Anaconda:

1. **Network & Host Name** → set static IPv4, DNS, hostname.
2. **Time & Date** → enable Network Time, pick the correct timezone.
3. **Installation Destination** → custom partitioning. Suggested layout:
   - `/boot` 1 GB
   - `/` 30–40 GB, xfs
   - `swap` 4–8 GB
   - **`/smartmet`** rest of disk, xfs   ← required mountpoint
4. **Root Password** → set a strong password.
5. **User Creation** — leave empty; the install script creates the
   `smartmet` system user.

Reboot when finished and log in as `root`.

## 2. Run the SmartMet install script

Pick the script matching your OS major version:

```sh
# AlmaLinux/Rocky 10
curl -O https://raw.githubusercontent.com/fmidev/smartmet-install/master/smartmet-install-10.sh
chmod +x smartmet-install-10.sh
./smartmet-install-10.sh
```

(Replace `10` with `9` or `8` for older releases.)

The script:

- detects your OS and refuses to run on the wrong family
- warns if `/smartmet` isn't a separate mountpoint
- adds the SmartMet, EPEL, CRB/PowerTools, and Docker CE repositories
- excludes eccodes from EPEL (FMI ships its own build)
- disables the system-default `postgresql` module (FMI ships its own)
- installs `smartmet-base-international` (PostgreSQL, Samba, Docker CE,
  and the SmartMet data-processing packages)
- runs `dnf update`
- prints a checklist of remaining manual steps

### Resume after a failure

Each step writes a completion marker under `/var/lib/smartmet-install/`. If
the script fails (network blip, mirror outage, dependency conflict), fix the
underlying issue and **just re-run the same script** — completed steps are
skipped, only the failing one is retried.

```sh
./smartmet-install-10.sh           # resumes from the first un-done step
./smartmet-install-10.sh --force   # ignore markers, redo everything
rm -rf /var/lib/smartmet-install   # forget all state, equivalent to --force
```

## 3. Set passwords for the `smartmet` user

```sh
passwd smartmet                # local Linux login password
smbpasswd -a smartmet          # Samba password (used for SMB share access)
```

## 4. Firewall and SELinux

The base package's `%post` already opens HTTP, HTTPS, Samba, NFS, and FTP in
firewalld and labels `/smartmet/www` and `/smartmet/editor/smartalert` with
`httpd_sys_content_t` so a containerised web server can serve them. Review
what's exposed:

```sh
firewall-cmd --list-all
```

If the host is internet-facing, drop services you don't need
(`firewall-cmd --permanent --remove-service=ftp`, etc.).

SELinux runs in enforcing mode by default — the smartmet packages ship the
required contexts, so a stock install needs no manual booleans.

## 5. (Optional) Install forecast data packages

```sh
dnf install smartmet-data-gfs       # NOAA Global Forecast System
dnf install smartmet-data-gem       # Environment Canada GEM
dnf install smartmet-data-metar     # METAR station data
```

Edit the area & schedule for each model:

- `/smartmet/cnf/data/gfs.cnf`
- `/smartmet/cnf/data/gem.cnf`

All SmartMet data-processing work runs as the `smartmet` user under the
cron schedule installed by `smartmet-base-international` (entries in
`/smartmet/cnf/cron/cron.{10min,hourly,daily,weekly,monthly}` and
triggers under `/smartmet/cnf/triggers.d/`). A single `/etc/cron.d/smartmet.cron`
dispatches into those directories — don't drop ad-hoc cron files there
yourself; add scripts to the matching `/smartmet/cnf/cron/...` directory.

## 6. Verify the install

```sh
systemctl status smb postgresql docker     # all should be active (running)
ls /smartmet                               # bin/ cnf/ run/ data/
docker ps                                  # smartmet web container running
curl -I http://localhost/                  # served by the web container
```

The web UI is at `http://<server>/`. The Samba share is reachable as
`\\<server>\smartmet`.

## Troubleshooting

- **`dnf install smartmet-base-international` fails with an `eccodes`
  conflict** — EPEL exclusion didn't apply. Re-run:
  `dnf config-manager --setopt="epel.exclude=eccodes*" --save` and retry.
- **`/smartmet` fills up after a few hours** — the partition is too small
  for the data packages enabled. Move `/smartmet` to a larger volume or
  disable unused data feeds.
- **Samba access denied** — verify `smbpasswd -a smartmet` was run *and*
  that SELinux isn't blocking. If you share user home directories,
  `setsebool -P samba_enable_home_dirs on`.
- **Script aborts on the `/smartmet` mountpoint check** — answer `y` to
  continue without a dedicated volume (only safe for testing).

## Unattended install via Kickstart

For unattended installs (Tier 1 of the automation roadmap):

```
inst.ks=https://your-host/path/smartmet-10.ks
```

The kickstart at [`kickstart/smartmet-10.ks`](kickstart/smartmet-10.ks)
auto-detects single-disk vs two-disk hosts, sets up LVM with a growable
`/smartmet`, and runs the install script in `%post`. Replace the SSH
key placeholder before hosting it. See
[`kickstart/README.md`](kickstart/README.md) for full details.

## Phase 2: more VM provisioning automation

A tiered plan covering cloud-init Proxmox templates and Packer golden
images is in [`PHASE2_PLAN.md`](PHASE2_PLAN.md). Tier 1 (Kickstart) is
implemented above.
