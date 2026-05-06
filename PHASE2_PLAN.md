# Phase 2 — automating SmartMet VM provisioning

**Status:** plan, awaiting review. Nothing implemented yet.

## Goal

Reduce a SmartMet-server VM from "boot ISO, click through Anaconda, copy
script, hope nothing fails" to one of:

- **good** — a single command that produces a fully-installed VM
- **better** — a Proxmox template that's cloned in <60 s
- **best** — the template is rebuilt by CI weekly so you never deploy a
  stale image

Each tier builds on the previous one. Pick the tier that matches the volume
of SmartMet VMs being deployed.

## Constraints / context

- Target hypervisor is Proxmox (assumed VE 8+, which has cloud-init support
  baked in).
- Target guest OS is AlmaLinux 10 or Rocky 10 (per Phase 1 README).
- The existing `smartmet-base-international-ansible` repo is **stale and
  not to be revived**.
- Phase 1 already produced a resumable `smartmet-install-10.sh`; Phase 2
  builds on top of it rather than replacing it.

## Open questions to settle before building

1. **Network model** — DHCP for new smartmet VMs, or static IPs registered
   in DNS first? (Affects whether cloud-init can fully self-configure.)
2. **Disk layout** — fixed (e.g. 40 GB root + 500 GB `/smartmet`) or
   parameterised per VM?
3. **Credentials** — bake an SSH key into the template, or inject at clone
   time via `qm set --sshkey`? Does the `smartmet` user need a default
   Samba password preset, or is `smbpasswd` mandatory post-clone?
4. **Forecast data API keys** (NOAA, ECMWF, …) — secrets store, or part of
   per-VM cloud-init?
5. **Proxmox API access** — do we have a service account + API token for
   automation, or is everything done from the Proxmox UI today?
6. **Where does the plan live** — this `smartmet-install` repo, or a new
   `smartmet-provision` repo? (Keeping it here is simpler; it's still
   "how to install".)

These need answers from the user before tier 2+ can be built.

## Tier 1 — Kickstart (~1 day, no infra changes)

Drop a single file `kickstart/smartmet-10.ks` into this repo. Anaconda reads
it, does the entire OS install unattended, partitions disk with `/smartmet`
correctly, and in `%post` curls and runs `smartmet-install-10.sh`.

**User flow:**

```
Boot AlmaLinux 10 ISO →
  add kernel arg: inst.ks=https://raw.githubusercontent.com/.../smartmet-10.ks →
  walk away, come back to a fully installed SmartMet VM.
```

**Deliverables:**

- `kickstart/smartmet-10.ks` — partitioning, network (DHCP by default),
  packages (`@^minimal`), root password placeholder, `%post` that fetches
  and runs the install script
- `kickstart/README.md` — how to host the file (Gitea raw URL, web server,
  or attach via virt-iso); how to override defaults

**Wins:**
- No more Anaconda clicking
- Reproducible: every install starts from the same recipe
- Works on any hypervisor, not just Proxmox

**Limits:**
- Still needs an ISO boot per VM
- Doesn't address VM *creation* in Proxmox

## Tier 2 — Cloud-init template in Proxmox (~1–2 days)

Skip ISOs entirely. AlmaLinux/Rocky publish ready-made cloud images
(`AlmaLinux-10-GenericCloud-latest.x86_64.qcow2`). One-time prep:

```
qm create 9000 --name smartmet-template-alma10 --memory 8192 --cores 4 ...
qm importdisk 9000 AlmaLinux-10-GenericCloud-latest.x86_64.qcow2 local-lvm
qm set 9000 --scsi0 local-lvm:vm-9000-disk-0 --ide2 local-lvm:cloudinit ...
qm template 9000
```

After that, every new SmartMet VM is:

```
qm clone 9000 <newid> --name smartmet-<host> --full
qm set <newid> --sshkey ~/.ssh/id_ed25519.pub --ipconfig0 ip=dhcp
qm set <newid> --cicustom "user=local:snippets/smartmet-userdata.yaml"
qm start <newid>
```

The cloud-init `user-data` snippet runs `smartmet-install-10.sh` on first
boot.

**Deliverables:**

- `cloud-init/smartmet-userdata.yaml` — the cloud-init recipe (packages,
  `runcmd:` to fetch + run the install script, optional disk resize for
  `/smartmet`)
- `cloud-init/README.md` — Proxmox template prep, clone command, snippet
  upload (`pvesm` to local snippets store)
- Optionally `cloud-init/new-smartmet-vm.sh` — wrapper that does the full
  `qm clone … qm set … qm start` dance

**Wins:**
- New VM in <60 seconds
- No ISO download per VM
- Cloud-init handles SSH keys, hostname, network — no manual step

**Limits:**
- The install script still runs at boot, so the *first* boot is slow
  (~10 min for `dnf install` + `dnf update`). Subsequent boots are fast.
- Tied to Proxmox (other hypervisors would need their own glue).

## Tier 3 — Packer-built Proxmox template (~1 week initial, ~1 h/week CI)

Move the install script's runtime *into* the template. Packer drives
Proxmox to install AlmaLinux 10, runs `smartmet-install-10.sh` end-to-end
during build, then snapshots the disk as a template. Cloning that template
gives a VM that's ready in ~10 seconds — no first-boot install lag.

**Deliverables:**

- `packer/smartmet-alma10.pkr.hcl` — Packer template using the
  `proxmox-iso` builder + cloud-init for autoinstall
- `packer/README.md` — required env vars (`PROXMOX_URL`, `PROXMOX_TOKEN_*`),
  build command, expected output
- `.github/workflows/build-template.yml` — weekly cron that runs Packer
  against a Proxmox host (via self-hosted runner with VPN access) and
  rotates the template ID

**Wins:**
- Boot-to-ready in seconds
- Weekly CI rebuild absorbs upstream security patches
- Template version is git-traceable

**Limits:**
- Requires self-hosted CI runner with Proxmox API access
- Higher complexity — only worth it if managing more than a handful of VMs

## Tier 4 — Terraform (defer)

Wrap Tier 3 with `terraform apply`. Only justified if managing many SmartMet
servers as a fleet. Skip until Tier 3 is paying off.

## Recommendation

Build **Tier 1 + Tier 2** in Phase 2. Both fit comfortably in this repo and
together cover 95 % of the friction. Document Tier 3 as a future direction
in the README; revisit if VM volume grows.

## Suggested order of work

1. Settle the open questions above (1 conversation with the user).
2. Tier 1 Kickstart — quick win, useful for any hypervisor.
3. Tier 2 cloud-init + Proxmox template — primary deployment path.
4. Update top-level `README.md` with a "Quick install" section pointing to
   Tier 2 as the recommended flow, and demote the manual ISO+script flow.
5. Write a one-page runbook covering common Proxmox cluster operations
   (clone, resize `/smartmet`, snapshot before upgrade).

## Out of scope for Phase 2

- Replacing the shell installer with Ansible/Puppet/Salt — the existing
  shell script works, is now resumable, and rewriting it doesn't move the
  needle on VM provisioning ease.
- Container-only deployment (running SmartMet entirely under Docker on a
  vanilla host without the base RPM). Possible long-term direction but
  needs a separate design.
- Multi-host clustering, HA, shared `/smartmet` storage. Out of scope until
  there's a stated need.
