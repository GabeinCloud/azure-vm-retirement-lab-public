# Azure VM Retirement — Operational Guide

> Temp disk, SCSI vs NVMe controller, Windows licensing and Azure-SSIS Integration
> Runtime — everything you need to know **before** you move a single VM.
>
> *Based on Microsoft Learn documentation and the validated [Azure VM Retirement
> Lab](README.md). May 2026.*

---

## Table of contents

- [Part 1 — Technical article](#part-1--technical-article)
  - [Why Microsoft is retiring VM series (and what it means for you)](#why-microsoft-is-retiring-vm-series-and-what-it-means-for-you)
  - [Affected series and official replacements](#affected-series-and-official-replacements)
  - [Per-family migration guides](#per-family-migration-guides)
  - [Critical operational considerations](#critical-operational-considerations)
- [Part 2 — L1 runbook](#part-2--l1-runbook)
  - [Per-VM execution sheet](#per-vm-execution-sheet)
  - [Stop conditions](#stop-conditions)
  - [Four-phase resize procedure](#four-phase-resize-procedure)
  - [VMSS mini-runbook](#vmss-mini-runbook)
  - [Closeout checklist](#closeout-checklist)
- [Official sources](#official-sources)

---

# Part 1 — Technical article

## Why Microsoft is retiring VM series (and what it means for you)

Over the last twelve months Microsoft has published an unusually high number of
VM-series retirement announcements. The reasoning is structural: the hardware
running those families has reached end of life, the CPU vendors no longer offer
extended support, and the performance / € gap versus current generations has
become hard to justify.

The operational consequence is sharp: **the day a series enters `Retired`,
existing VMs are deallocated, stop running, lose their SLA and stop billing —
but the data on managed disks is preserved**. If you do not act before the cut-off
date, your workloads stop without warning.

This guide answers one concrete question: **how do I perform the resize safely?**
At least four traps can break an apparently simple migration:

1. The presence (or absence) of a **local temp disk**.
2. The switch from **SCSI to NVMe** disk controllers in the `v6` family onwards.
3. The **cost increase** of leaving the B-series.
4. The impact on **Azure Data Factory Integration Runtimes**.

### Key dates

| Series | Retirement date |
|---|---|
| `NVv3`, `NVv4` | 2026-09-30 |
| `Msv2 / Mdsv2` (M192 SKUs) | 2027-03-31 |
| `NP-series`, `HBv2`, `HC-series` | 2027-05-31 |
| `D`, `Ds`, `Dv2`, `Dsv2`, `Ls` | 2028-05-01 |
| `Av2`, `Amv2`, `Bv1`, `F`, `Fs`, `Fsv2`, `G`, `Gs`, `Lsv2` | 2028-11-15 |

Source: [retired-sizes-list](https://learn.microsoft.com/azure/virtual-machines/sizes/retirement/retired-sizes-list).

---

## Affected series and official replacements

State **Announced**: series available with a cut-off date. State **Retired**:
new provisioning is blocked.

> **Note**: the migration guide
> [`d-ds-dv2-dsv2-ls-series-migration-guide`](https://learn.microsoft.com/azure/virtual-machines/migration/sizes/d-ds-dv2-dsv2-ls-series-migration-guide)
> also covers **HBv2** in a dedicated section. **HC-series** has its own
> retirement page:
> [`hc-series-retirement`](https://learn.microsoft.com/azure/virtual-machines/sizes/retirement/hc-series-retirement).

---

## Per-family migration guides

### D, Ds, Dv2, Dsv2, Av2, Amv2, Bv1, F, Fs, Fsv2, G, Gs, Ls, Lsv2 — and HBv2

All of these share the same unified migration guide published on **2026-01-30**,
including HBv2. Recommended process:

1. **Review active RIs**. 1- and 3-year RI purchases for these series **cannot
   be renewed after 2026-07-01**. If you have RIs, you can exchange them or
   convert them to an **Azure Savings Plan for Compute** without penalty.
2. **Identify the target SKU** using the official replacement table. Pay close
   attention to whether the replacement is **v5 (SCSI)** or **v6 / v7 (NVMe)** —
   that decision drives everything else.
3. **Request quota** for the target series before starting.
   `portal.azure.com → Subscription → Usage + quotas`.
4. **Deallocate** the VM.
5. **Change the size** via portal, CLI or PowerShell.
6. **Start and validate.**

> ⚠️ **Watch out for Dv3, Dsv3, Ev3, Esv3**: these are **not retired yet**, but
> 1- and 3-year RIs will stop being available after **2026-07-01**. If you plan
> to keep using them, **Azure Savings Plan for Compute** is the path.

The guide lists as targets:

- **v5 (SCSI)**: Dsv5, Ddsv5, Dasv5, Dadsv5.
- **v6 / v7 (NVMe)**: Dasv6, Dadsv6, Dsv6, Ddsv6, Dasv7, Dadsv7.

> v7 requires **NVMe + Gen2 OS**, same as v6. Check regional availability first.

---

### HBv2 — HPC (retired 2027-05-31)

Affected SKUs: `Standard_HB120rs_v2` and constrained-core variants
(`HB120-96rs_v2`, `HB120-64rs_v2`, `HB120-32rs_v2`, `HB120-16rs_v2`). 120 cores
**AMD EPYC 7V12 (Rome)** + InfiniBand HDR 200 Gb/s. RIs closed on 2026-04-02.

Replacements in order of preference:

| Replacement | Hardware | Fabric | Use case |
|---|---|---|---|
| **HBv5** | AMD EPYC Genoa | InfiniBand NDR | First choice for most workloads |
| **HX** | High memory density | InfiniBand NDR | Molecular dynamics, high-RAM |
| **HBv4** | AMD EPYC Genoa | InfiniBand NDR | Balanced price-performance |
| **HBv3** | AMD EPYC Milan | InfiniBand HDR (same as HBv2) | Lowest-impact migration for InfiniBand-bound workloads |

Validate before migrating:

- MPI / fabric compatibility (**HDR** on HBv2 / HBv3 vs **NDR** on HBv4 / HBv5).
- Memory bandwidth benchmark on the real workload.
- Regional capacity.

The official docs **explicitly recommend an MPI validation test** before
moving to production.

---

### HC-series — HPC (retired 2027-05-31)

SKUs: `Standard_HC44rs`, `HC44-16rs`, `HC44-32rs`. 44 cores **Intel Xeon
Platinum 8168 (Skylake)**, 352 GB RAM, InfiniBand EDR 100 Gb/s. RIs closed on
2026-04-02.

Replacements:

- **HBv5**: higher compute performance and better price-performance than HBv4,
  good fit for most memory-bandwidth-intensive HPC workloads.
- **HX**: HPC-optimized with large memory capacity (~2× HBv4), ideal for large
  EDA and molecular dynamics.

> HC-series does **not** appear in `retired-sizes-list`. Its retirement is
> documented on the series page and on
> [`hc-series-retirement`](https://learn.microsoft.com/azure/virtual-machines/sizes/retirement/hc-series-retirement),
> which is the authoritative source.

---

### Msv2 / Mdsv2 — M192 SKUs (retired 2027-03-31)

Affected SKUs: `Standard_M192is_v2`, `M192ims_v2`, `M192ids_v2`, `M192idms_v2`.
Process complexity rises with AvSet / PPG dependencies:

1. Check whether the VM belongs to an AvSet or PPG (VM properties in the portal).
2. If **none** → direct resize is supported.
3. If **PPG but no AvSet** → stop all VMs in the PPG, resize the M192 VMs, start
   the rest.
4. If **AvSet not anchored** → stop ALL VMs in the AvSet and resize each one.
5. If the **AvSet is anchored to an M-series cluster** (common with Azure
   NetApp Files): **open a support ticket** — Microsoft handles it manually.

Recommended replacement: **Msv3 / Mdsv3 Medium Memory**, Intel Xeon 4th gen,
up to 4 TB of memory and 4 000 MBps to remote storage.

---

### NVv3 and NVv4 — GPU (retired 2026-09-30 — urgent)

RIs have been closed since November 2025.

**NVv3 (NVIDIA Tesla M60):**

- **NVads_A10_v5** — NVIDIA A10, high-performance graphics and VDI.
- **NVads_V710_v5** — AMD Radeon PRO V710, cost-friendly VDI and light graphics.

**NVv4 (AMD Radeon Instinct MI25):**

- **NVads_V710_v5** — Microsoft's recommendation for all NVv4 scenarios.

> ⚠️ There is a **known issue** with direct resize from NVv4 to NVads_V710_v5;
> Microsoft is working on a fix. Workaround: between-VM migration with and
> without temp disk.

---

### NP-series FPGA (retired 2027-05-31)

SKUs `Standard_NP10s`, `NP20s`, `NP40s` with AMD Xilinx Alveo U250 FPGAs.

> ⚠️ Migration to any of the replacements (NDv2, NCads_H100_v5, NCasT4_v3)
> **requires porting workloads from FPGA frameworks (Vitis / XRT) to GPU
> frameworks (CUDA)**. This is **not a transparent resize** — it is an
> application migration that can take weeks. RIs closed on 2026-04-02.

---

## Critical operational considerations

### 1. Temp disk: present or absent?

The **v5** family introduced a split that did not exist before:

| Pattern | Local temp disk |
|---|---|
| SKU **without "d"**: `Dv5`, `Dsv5`, `Dasv5`, `Ev5`, `Esv5`, `Easv5` | ❌ No |
| SKU **with "d"**: `Ddv5`, `Ddsv5`, `Dadsv5`, `Edv5`, `Edsv5`, `Eadsv5` | ✅ Yes (local SCSI SSD) |

If you migrate from a VM that uses `D:` as a temp disk to a SKU without temp disk:

- **Windows**: `pagefile.sys` disappears → potential crash when RAM is exhausted.
- **SQL Server**: `tempdb` on `D:` fails to start → SQL instance down.
- **Apps**: any path hard-coded to `D:\` fails.
- **Linux**: swap on `/dev/sdb` is no longer available.

> 🚫 **Official Windows restriction**: you cannot directly resize between VMs
> with and without a temp disk (in either direction). Only disk-to-disk or
> diskless-to-diskless. Sources:
> [`azure-vms-no-temp-disk`](https://learn.microsoft.com/azure/virtual-machines/azure-vms-no-temp-disk),
> [`resize-vm`](https://learn.microsoft.com/azure/virtual-machines/sizes/resize-vm).

Official Windows workaround when you must cross the boundary:

1. RDP / Bastion into the VM as local admin.
2. Move `pagefile.sys` from `D:` to `C:` following
   [`change-drive-letter`](https://learn.microsoft.com/azure/virtual-machines/windows/change-drive-letter).
3. Take a snapshot of the OS disk.
4. Create the new diskless VM from that snapshot.

**For SQL Server**: before migrating, move `tempdb` files out of `D:` (to a
Premium SSD data disk or to `C:` temporarily). `ALTER DATABASE tempdb MODIFY
FILE` to redirect the paths.

**For Linux**: disable the swap on `/dev/sdb` before the resize and reconfigure
the swap file on the OS disk or a data disk afterwards.

> 💡 **Validated in this lab**: default Ubuntu 22.04 cloud-init leaves `/mnt`
> unused (`ResourceDisk.EnableSwap=n`) and `fstab` uses `nofail`, so the resize
> works directly. See [CORE-S03 README](core-vms/s03-linux-tempdisk/README.md).

---

### 2. SCSI vs NVMe controller — the invisible trap when moving to v6 or v7

Generations up to **Dv5 / Ev5** use **SCSI**. From **Da / Ea / Fav6** and later
(including v7), **NVMe** is the supported mode for remote storage.

From [NVMe overview](https://learn.microsoft.com/azure/virtual-machines/nvme-overview):

> *"older generations (D/Ev5 or Fv2 and older) support SCSI; newer generations
> (Ebsv5, Da/Ea/Fav6 and newer) typically support only NVMe"*.

Implications:

- On **Windows**, SCSI disks appear as `\Device\Harddisk`; under NVMe the
  presentation changes. If the OS does not have NVMe drivers in the boot
  image, the VM may not start.
- **You cannot directly resize from SCSI to remote NVMe.** Workaround in
  [`enable-nvme-remote-faqs`](https://learn.microsoft.com/azure/virtual-machines/enable-nvme-remote-faqs).

v6 / v7 requirements:

| Requirement | Detail |
|---|---|
| **Gen2 image** | Standard or Trusted Launch. Gen1 **does not support NVMe**. |
| **Supported OS** | Win Server 2019 / 2022 / 2025, Win 10 / 11, RHEL 7.9+, Ubuntu 18.04+, SLES 15 SP4+, Debian 11+, Oracle Linux 7.9+. |
| **MANA** (Microsoft Azure Network Adapter) | Required on v6 / v7. See [`accelerated-networking-mana-overview`](https://learn.microsoft.com/azure/virtual-network/accelerated-networking-mana-overview). |
| **Linux**: `nvme_core.io_timeout = 240` | Official recommendation to avoid OS-side timeouts firing before Azure does. |

To enable NVMe on an existing VM **without changing SKU** (only on SKUs that
support both controllers):

```bash
# Azure CLI — switch diskControllerType to NVMe (VM must be deallocated)
az vm deallocate --resource-group <rg> --name <vm>
az vm update     --resource-group <rg> --name <vm> --set storageProfile.diskControllerType=NVMe
az vm start      --resource-group <rg> --name <vm>
```

> ⚠️ If the image is not flagged as NVMe-compatible in Azure Compute Gallery
> or Marketplace, the operation fails with `The selected image is not
> supported for NVMe`. Verify on
> [`enable-nvme-interface`](https://learn.microsoft.com/azure/virtual-machines/enable-nvme-interface).

> 💡 **Validated in this lab**: the **atomic** pattern for SCSI Dsv5 → v6 NVMe is:
>
> ```bash
> az vm deallocate -g $RG -n $VM
> az vm update    -g $RG -n $VM \
>   --set hardwareProfile.vmSize=Standard_D2as_v6 storageProfile.diskControllerType=NVMe
> az vm start     -g $RG -n $VM
> ```
>
> Changing **only one** of the two fields fails with `InvalidParameter`. See
> [ADV-S01 README](advanced-vms/s01-scsi-nvme/README.md).

---

### 3. Windows licensing when leaving the B-series

The **B-series** combines low compute cost (CPU credits) with included Windows
Server licensing. Moving to D / E-series **increases the base compute cost
significantly** — the jump is mostly the compute rate, not the license.

To estimate the real impact use the
[Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/) or
the [Retail Prices API](https://learn.microsoft.com/azure/retail-prices/azure-retail-prices),
specifying region, OS, instance type and pricing model (PAYG, RI, Savings Plan).

**Azure Hybrid Benefit (AHB)** is the main lever to offset the Windows license
cost. Operational rules:

| Item | Rule |
|---|---|
| **Minimum licenses** | 8 core licenses per VM (Datacenter or Standard), **even for 4-vCPU VMs**. |
| **More than 8 cores** | One license per vCPU (e.g. 12 licenses for a 12-core VM). |
| **Validity** | Only while SA or a qualifying subscription is active. |
| **Changing `licenseType`** | **Does not reboot** the VM or interrupt service — it only flips a metadata flag. |

Enable AHB:

```powershell
# PowerShell
$vm = Get-AzVM -ResourceGroupName "my-rg" -Name "my-vm"
$vm.LicenseType = "Windows_Server"
Update-AzVM -ResourceGroupName "my-rg" -VM $vm
```

```bash
# Azure CLI
az vm update --resource-group my-rg --name my-vm --set licenseType=Windows_Server
```

Confirm the agreement covers Windows Server with active SA. Source:
[`hybrid-use-benefit-licensing`](https://learn.microsoft.com/azure/virtual-machines/windows/hybrid-use-benefit-licensing).

> 💡 **Validated in this lab**: AHB **persists across a cross-family resize**
> (`B2ms` → `D2s_v3`). After `az vm create --attach-os-disk` you must pass
> `--license-type Windows_Server` explicitly. See
> [CORE-S04 README](core-vms/s04-ahb-windows/README.md).

---

### 4. Azure-SSIS Integration Runtime and the Dv2 / Av2 retirement

This affects **Azure Data Factory** and **Azure Synapse** customers running
**Azure-SSIS IR**. Affected sizes:

| SKU | Family | Retirement |
|---|---|---|
| `Standard_D1_v2`, `D2_v2`, `D3_v2`, `D4_v2` | Dv2 | 2028-05-01 |
| `Standard_A4_v2`, `A8_v2` | Av2 / Amv2 | 2028-11-15 |

Microsoft explicitly warns: *"v2 nodes for Azure-SSIS IR are not suitable for
custom setup; if you already use them, migrate to v3 nodes as soon as
possible."*

Current recommendation: **Dv3 / Ev3 minimum** (also not eternal: no renewable
RIs after 2026-07). **No live resize** — stop the IR, modify it, restart:

```powershell
$DataFactoryName        = "my-adf"
$ResourceGroupName      = "my-rg"
$IntegrationRuntimeName = "my-ssis-ir"

# 1. Stop the IR
Stop-AzDataFactoryV2IntegrationRuntime `
  -DataFactoryName $DataFactoryName `
  -ResourceGroupName $ResourceGroupName `
  -Name $IntegrationRuntimeName

# 2. Change node size
Set-AzDataFactoryV2IntegrationRuntime `
  -DataFactoryName $DataFactoryName `
  -ResourceGroupName $ResourceGroupName `
  -Name $IntegrationRuntimeName `
  -NodeSize Standard_D8_v3

# 3. Start the IR
Start-AzDataFactoryV2IntegrationRuntime `
  -DataFactoryName $DataFactoryName `
  -ResourceGroupName $ResourceGroupName `
  -Name $IntegrationRuntimeName
```

---

# Part 2 — L1 runbook

## Per-VM execution sheet

Before executing anything, fill this in. **No sheet, no action.**

```text
-- Identity --
Subscription:                  [ID or name]
Resource Group:                [Exact RG name]
VM name:                       [As it appears in Azure]
Region / Zone:                 [e.g. swedencentral / Zone 1]
Current SKU:                   [e.g. Standard_D4_v2]
Target SKU:                    [e.g. Standard_D4s_v5]

-- OS and generation --
OS (Windows/Linux + version):  [e.g. Windows Server 2022]
Generation (Gen1/Gen2):        [e.g. Gen2]
Security type:                 [Standard / TrustedLaunch / Confidential]
Current disk controller:       [SCSI / NVMe — verify with `az vm show`]
Target disk controller:        [SCSI / NVMe — per target family]

-- Temp disk --
Has local temp disk (Y/N):              [Check SKU spec]
Uses D:\ or /mnt/resource (Y/N):        [Inspect the OS]
SQL Server tempdb on temp disk (Y/N):   [sys.master_files]
Pagefile / swap location:               [e.g. C:\pagefile.sys / /dev/sda2]

-- High availability --
Availability Set:              [Name or "None"]
Proximity Placement Group:     [Name or "None"]

-- Backup and rollback --
Backup / snapshot completed (timestamp + ID):
OS disk snapshot ID:
Data disk N snapshot IDs:
Maintenance window:    [e.g. 2026-06-10 02:00–04:00 UTC]
Rollback SKU:          [Original SKU, in case of rollback]
```

---

## Stop conditions

If **any** of these is true, the operation **must not run**. Each has an
official-doc basis. **L1 evaluates each as Y / N** — if uncertain, escalate to L2.

### 🚫 Target SKU is NVMe-only + source VM is Gen1

Gen1 **does not support NVMe**. Requires a new Gen2 VM (recreate, not resize).

```bash
az vm get-instance-view --resource-group <rg> --name <vm> \
  --query "hyperVGeneration" --output tsv
# Returns "V1" or "V2"
```

Source: [`nvme-overview`](https://learn.microsoft.com/azure/virtual-machines/nvme-overview).

> 💡 **Validated in this lab**: Dsv5 **accepts Gen1** — the real boundary is
> v6, not Dsv5. See [ADV-S02 README](advanced-vms/s02-gen1-blocked/README.md).

### 🚫 Windows: crossing the "with temp disk / without temp disk" boundary

There is no direct resize for this case on Windows. Use the official workaround
(snapshot + new VM). If one side has "d" in the SKU name and the other does
not, this is the boundary.

### 🚫 Pagefile / SQL tempdb / swap still on the temp disk

Move them to the OS disk or a data disk first, then resize.

```powershell
# Windows
Get-CimInstance Win32_PageFileSetting
```

```sql
-- SQL Server
SELECT physical_name FROM sys.master_files WHERE database_id = 2
```

```bash
# Linux
swapon --show
```

### 🚫 SCSI → NVMe remote (target v6, v7 or Ebsv5) without the atomic PATCH

There is no direct resize. Use the atomic PATCH or the official
`azure-nvme-VM-update.ps1` script. Source:
[`enable-nvme-remote-faqs`](https://learn.microsoft.com/azure/virtual-machines/enable-nvme-remote-faqs).

### 🚫 OS image not NVMe-compatible (when target requires NVMe)

Verify against the official list:
[`enable-nvme-interface`](https://learn.microsoft.com/azure/virtual-machines/enable-nvme-interface).

### 🚫 MANA driver missing (target v6 / v7)

```powershell
# Windows
Get-NetAdapter | Where-Object { $_.InterfaceDescription -like "*MANA*" }
```

```bash
# Linux
lspci -k | grep -A 3 -i "ethernet"
```

### 🚫 AvSet anchored to an M-series cluster (M192 → Msv3 path)

Open a support ticket — Microsoft handles it manually.

### 🚫 No quota in the target region

```bash
az vm list-usage --location <region> -o table
```

### 🚫 No fresh snapshot / backup (timestamp older than the last data change)

Take it before continuing.

### 🚫 Maintenance window not approved or change ticket not open

L1 escalates to the change manager.

### 🚫 RI / Savings Plan impact not assessed

For migrations from D / Ds / Dv2 / Dsv2: confirm with the cost owner whether to
exchange the RI or move to a Savings Plan.

### 🚫 NP-series → GPU without an application migration plan

L1 escalates: this is not a resize, it is a code port.

### 🚫 Azure-SSIS IR on retired SKU without a maintenance window

Restarting the IR breaks pipelines in flight. L1 schedules with the data team.

---

## Four-phase resize procedure

### Phase 1 — Inventory (read-only · ~minutes)

Use Azure Resource Graph (KQL) to find affected VMs. Three useful queries:

**Wide (any VM still on `Dv2 / Dsv2 / Bv1`):**

```kusto
Resources
| where type =~ 'microsoft.compute/virtualmachines'
| extend sku = tostring(properties.hardwareProfile.vmSize)
| where sku matches regex @'^Standard_(B|D|DS|A)\d+([a-z]*)?(_v[12])?$'
| project name, resourceGroup, location, sku, subscriptionId
| order by sku asc
```

**Strict (named retired SKUs):**

```kusto
Resources
| where type =~ 'microsoft.compute/virtualmachines'
| extend sku = tostring(properties.hardwareProfile.vmSize)
| where sku in~ (
    'Standard_D1_v2','Standard_D2_v2','Standard_D3_v2','Standard_D4_v2','Standard_D5_v2',
    'Standard_DS1_v2','Standard_DS2_v2','Standard_DS3_v2','Standard_DS4_v2','Standard_DS5_v2',
    'Standard_B1ms','Standard_B2s','Standard_B2ms','Standard_B4ms','Standard_B8ms'
  )
| project name, resourceGroup, location, sku, subscriptionId
```

**VMSS:**

```kusto
Resources
| where type =~ 'microsoft.compute/virtualmachinescalesets'
| extend sku = tostring(sku.name)
| where sku startswith 'Standard_D' and sku endswith '_v2'
| project name, resourceGroup, location, sku, capacity = toint(sku.capacity)
```

For each match, complete the **execution sheet** and proceed to Phase 2.

### Phase 2 — Validate (read-only · ~minutes per VM)

```bash
# Generation and security type
az vm get-instance-view -g $RG -n $VM \
  --query "{gen:hyperVGeneration, security:securityProfile.securityType}"

# Disk controller, AHB, AvSet, PPG
az vm show -g $RG -n $VM \
  --query "{controller:storageProfile.diskControllerType, license:licenseType, avset:availabilitySet.id, ppg:proximityPlacementGroup.id}"
```

In-guest:

```bash
# Windows
az vm run-command invoke -g $RG -n $VM --command-id RunPowerShellScript --scripts '
  Get-CimInstance Win32_PageFileSetting | Select-Object Name, InitialSize, MaximumSize;
  Get-NetAdapter | Where-Object { $_.InterfaceDescription -like "*MANA*" }'

# Linux
az vm run-command invoke -g $RG -n $VM --command-id RunShellScript --scripts '
  swapon --show; lsblk -o NAME,SIZE,MOUNTPOINT; lspci -k | grep -A 3 -i ethernet'
```

If everything is green → Phase 3.

### Phase 3 — Execute (destructive · operates inside the change window)

```bash
# 0. Snapshot the OS disk (and data disks if any)
OS_DISK=$(az vm show -g $RG -n $VM --query "storageProfile.osDisk.name" -o tsv)
az snapshot create -g $RG -n "snap-$VM-pre-resize-$(date +%Y%m%d%H%M)" \
  --source $(az disk show -g $RG -n $OS_DISK --query id -o tsv)

# 1. Deallocate
az vm deallocate -g $RG -n $VM

# 2. Resize (path depends on the target family)
# 2a. Same family / v5 (SCSI): single field
az vm update -g $RG -n $VM --set hardwareProfile.vmSize=$TARGET_SKU

# 2b. v6 / v7 (NVMe): atomic PATCH — see ADV-S01
az vm update -g $RG -n $VM \
  --set hardwareProfile.vmSize=$TARGET_SKU storageProfile.diskControllerType=NVMe

# 3. Start
az vm start -g $RG -n $VM
```

### Phase 4 — Validate (read-only · ~minutes)

```bash
# CPU, uptime, basic health
az vm run-command invoke -g $RG -n $VM --command-id RunShellScript --scripts '
  uname -a; cat /proc/cpuinfo | grep "model name" | head -1; uptime; df -h /'

# Application-level: smoke test of your service
```

If degraded → execute **rollback** (deallocate, restore original SKU, optionally
re-mount from snapshot).

---

## VMSS mini-runbook

For VMSS Uniform the procedure depends on `upgrade_mode`:

| Mode | What you do |
|---|---|
| **Manual** | Update the model SKU, then explicitly call `update-instances` on chosen instance IDs (controlled rolling). |
| **Rolling** | Update the model SKU, Azure rolls instances in batches per the rolling-upgrade policy. |
| **Automatic** | Update the model SKU, Azure recycles all instances immediately. |

Manual flow (recommended for production):

```bash
SS_RG=<rg>; SS=<vmss-name>; TARGET=Standard_D2s_v5

# 1. Stage the new model (does not touch instances)
az vmss update -g $SS_RG -n $SS --set sku.name=$TARGET

# 2. Recycle instances in batches
az vmss list-instances -g $SS_RG -n $SS --query "[].instanceId" -o tsv
az vmss update-instances -g $SS_RG -n $SS --instance-ids 0 1
# wait, validate, then continue
az vmss update-instances -g $SS_RG -n $SS --instance-ids 2 3
```

> 💡 **Validated in this lab**: see [ADV-S05 README](advanced-vms/s05-vmss/README.md).

---

## Closeout checklist

- [ ] All in-scope VMs resized successfully (new SKU + healthy CPU model in
      guest).
- [ ] Application smoke tests green.
- [ ] Snapshots retained for the agreed window (e.g. 7 days), then deleted.
- [ ] Cost / RI / Savings Plan impact notified to FinOps.
- [ ] CMDB / inventory updated with the new SKU.
- [ ] Change ticket closed with the execution sheet attached as evidence.
- [ ] Lessons learned added to the runbook (PR welcome).

---

## Official sources

### Retirements and migration guides

- [Retired VM sizes list](https://learn.microsoft.com/azure/virtual-machines/sizes/retirement/retired-sizes-list)
- [D / Ds / Dv2 / Dsv2 / Ls migration guide](https://learn.microsoft.com/azure/virtual-machines/migration/sizes/d-ds-dv2-dsv2-ls-series-migration-guide)
- [HC-series retirement](https://learn.microsoft.com/azure/virtual-machines/sizes/retirement/hc-series-retirement)

### Resize, NVMe and disk controllers

- [Resize VM](https://learn.microsoft.com/azure/virtual-machines/sizes/resize-vm)
- [NVMe overview](https://learn.microsoft.com/azure/virtual-machines/nvme-overview)
- [Enable NVMe interface](https://learn.microsoft.com/azure/virtual-machines/enable-nvme-interface)
- [Enable NVMe remote disks FAQs](https://learn.microsoft.com/azure/virtual-machines/enable-nvme-remote-faqs)

### Temp disk and pagefile

- [Azure VMs without a temp disk](https://learn.microsoft.com/azure/virtual-machines/azure-vms-no-temp-disk)
- [Change drive letter (move pagefile)](https://learn.microsoft.com/azure/virtual-machines/windows/change-drive-letter)

### Networking (MANA)

- [Accelerated networking with MANA](https://learn.microsoft.com/azure/virtual-network/accelerated-networking-mana-overview)

### Licensing

- [Azure Hybrid Benefit for Windows Server](https://learn.microsoft.com/azure/virtual-machines/windows/hybrid-use-benefit-licensing)
- [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/)
- [Azure Retail Prices API](https://learn.microsoft.com/azure/retail-prices/azure-retail-prices)

### High availability primitives

- [Availability Sets overview](https://learn.microsoft.com/azure/virtual-machines/availability-set-overview)
- [Proximity Placement Groups](https://learn.microsoft.com/azure/virtual-machines/co-location)
- [VMSS upgrade modes](https://learn.microsoft.com/azure/virtual-machine-scale-sets/virtual-machine-scale-sets-upgrade-policy)

### Azure-SSIS Integration Runtime

- [Create Azure-SSIS IR (ADF)](https://learn.microsoft.com/azure/data-factory/create-azure-ssis-integration-runtime)
- [Reconfigure Azure-SSIS IR](https://learn.microsoft.com/azure/data-factory/manage-azure-ssis-integration-runtime)

---

## Appendix — Mapping this guide to the lab scenarios

| Guide section | Lab scenario | Folder |
|---|---|---|
| Temp disk (Windows) | CORE-S02 | [core-vms/s02-windows-tempdisk](core-vms/s02-windows-tempdisk/README.md) |
| Temp disk (Linux)   | CORE-S03 | [core-vms/s03-linux-tempdisk](core-vms/s03-linux-tempdisk/README.md) |
| Direct resize       | CORE-S01 | [core-vms/s01-direct-resize-linux](core-vms/s01-direct-resize-linux/README.md) |
| AHB persistence     | CORE-S04 | [core-vms/s04-ahb-windows](core-vms/s04-ahb-windows/README.md) |
| SCSI → NVMe         | ADV-S01  | [advanced-vms/s01-scsi-nvme](advanced-vms/s01-scsi-nvme/README.md) |
| Gen1 boundary       | ADV-S02  | [advanced-vms/s02-gen1-blocked](advanced-vms/s02-gen1-blocked/README.md) |
| AvSet               | ADV-S03  | [advanced-vms/s03-availability-set](advanced-vms/s03-availability-set/README.md) |
| PPG                 | ADV-S04  | [advanced-vms/s04-ppg](advanced-vms/s04-ppg/README.md) |
| VMSS                | ADV-S05  | [advanced-vms/s05-vmss](advanced-vms/s05-vmss/README.md) |
