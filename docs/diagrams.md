# Diagrams

This document collects every diagram referenced from the [main
README](../README.md), the [operational guide](../OPERATIONAL-GUIDE.md) and the
nine scenario READMEs. All diagrams are written in Mermaid so they render
natively on GitHub and in most Markdown previewers.

---

## 1. Macro decision tree

The decision tree the L1 operator runs **before** touching any VM.

```mermaid
flowchart TD
    START([VM identified for resize]) --> SHEET[Fill execution sheet<br/>see OPERATIONAL-GUIDE.md]
    SHEET --> Q1{Target SKU requires NVMe?<br/>v6 / v7 / Ebsv5}
    Q1 -- Yes --> Q1a{Source VM<br/>Generation 2?}
    Q1a -- No --> STOP1[["🚫 STOP<br/>Gen1 cannot boot v6<br/>Recreation needed"]]
    Q1a -- Yes --> Q1b{NVMe-capable image?<br/>Driver in initramfs}
    Q1b -- No --> STOP2[["🚫 STOP<br/>Validate & rebuild image"]]
    Q1b -- Yes --> NVME[["✅ ADV-S01 pattern<br/>Atomic PATCH"]]

    Q1 -- No --> Q2{Crossing temp-disk<br/>boundary?}
    Q2 -- Yes, Windows --> Q2a{Pagefile / SQL tempdb<br/>still on D:?}
    Q2a -- Yes --> STOP3[["🚫 STOP<br/>Move pagefile to C:<br/>first, then resize"]]
    Q2a -- No --> WIN[["✅ CORE-S02 pattern<br/>Snapshot + recreate"]]
    Q2 -- Yes, Linux --> Q2b{Swap active on /mnt?}
    Q2b -- No --> LIN[["✅ Direct resize OK<br/>CORE-S03 path"]]
    Q2b -- Yes --> STOP4[["🚫 STOP<br/>Disable swap on /mnt,<br/>move to OS disk"]]

    Q2 -- No --> Q3{VM in AvSet / PPG /<br/>VMSS?}
    Q3 -- AvSet --> AS[["✅ ADV-S03 pattern"]]
    Q3 -- PPG --> PPG[["✅ ADV-S04 pattern"]]
    Q3 -- VMSS --> VMSS[["✅ ADV-S05 pattern"]]
    Q3 -- None --> Q4{AHB-eligible<br/>Windows VM?}
    Q4 -- Yes --> AHB[["✅ CORE-S04 pattern"]]
    Q4 -- No --> DIRECT[["✅ CORE-S01 pattern"]]
```

---

## 2. Standard lab topology

Every scenario shares the same minimal blueprint:

```mermaid
flowchart LR
    subgraph SUB["Azure Subscription"]
        subgraph RG["Resource Group<br/>rg-vm-retirement-&lt;id&gt;"]
            direction TB
            VNET["VNet<br/>10.x.0.0/16"]
            SUBNET["Subnet<br/>10.x.1.0/24"]
            NSG[["NSG<br/>deny-all inbound<br/>+ optional scoped SSH/RDP"]]
            NIC["NIC<br/>dynamic private IP"]
            PIP["Public IP<br/>(opt-in)"]
            WORKLOAD[("VM / VMSS / AvSet / PPG<br/>(varies by scenario)")]

            VNET --> SUBNET
            SUBNET -. associated .-> NSG
            SUBNET --> NIC
            NIC --> WORKLOAD
            NIC -. opt-in .-> PIP
        end
    end
    OPS([Operator<br/>az CLI]) -. run-command<br/>over MGMT plane .-> WORKLOAD
```

---

## 3. L1 runbook phases

The runbook has four phases. Phases 1 and 2 are read-only and idempotent.

```mermaid
sequenceDiagram
    autonumber
    participant Op as L1 Operator
    participant Arg as Azure Resource Graph
    participant Az as Azure Control Plane
    participant Vm as Target VM

    Note over Op,Vm: Phase 1 — Inventory (KQL)
    Op->>Arg: Query Resources where vmSize matches retired SKUs
    Arg-->>Op: List of affected VMs + AvSet / PPG / VMSS context

    Note over Op,Vm: Phase 2 — Validate (read-only)
    Op->>Vm: az vm run-command invoke (collect OS, drivers, pagefile, tempdb)
    Vm-->>Op: Guest inventory
    Op->>Az: az vm show (controller, generation, AHB, AvSet, PPG)
    Az-->>Op: Resource metadata

    Note over Op,Vm: Phase 3 — Execute (destructive window)
    Op->>Az: snapshot OS disk (+ data disks)
    Op->>Vm: deallocate
    Op->>Az: az vm update --set vmSize=...<br/>(+ diskControllerType=NVMe if applicable)
    Op->>Vm: start

    Note over Op,Vm: Phase 4 — Validate post-resize
    Op->>Vm: az vm run-command invoke (CPU, uptime, services, app health)
    Vm-->>Op: Healthy / Degraded
    alt Healthy
        Op->>Az: Delete snapshots after stabilization window
    else Degraded
        Op->>Az: Rollback to original SKU (and snapshot if needed)
    end
```

---

## 4. CORE-S02 — Windows pagefile on temp disk

When the source has a temp disk and the target does not, an in-place resize is
not allowed for Windows. This is the supported workaround:

```mermaid
flowchart LR
    A["Source VM<br/>D2s_v3 (with D:)"] --> B["Move pagefile to C:<br/>via registry"]
    B --> C[Reboot - confirm D: empty]
    C --> D[Deallocate VM]
    D --> E["Snapshot OS disk<br/>(V2-compatible)"]
    E --> F["Create new managed disk<br/>from snapshot"]
    F --> G["az vm create --attach-os-disk<br/>--size D2s_v5 --license-type ..."]
    G --> H[["New VM<br/>D2s_v5 (no D:)"]]
    H --> I[Validate guest health]
    I --> J["Delete old VM + disk<br/>+ snapshot (after window)"]
```

---

## 5. ADV-S01 — Atomic SCSI → NVMe PATCH

The only command shape that works to move a Dsv5 VM to a v6 NVMe SKU in place:

```mermaid
sequenceDiagram
    autonumber
    participant Op
    participant Az as Azure Control Plane
    participant Vm as Target VM (Gen2 Linux)

    Op->>Vm: az vm deallocate
    Vm-->>Op: Deallocated

    Note over Op,Az: ❌ Wrong path A — size only
    Op->>Az: az vm update --set vmSize=Standard_D2as_v6
    Az-->>Op: InvalidParameter: cannot boot with SCSI

    Note over Op,Az: ❌ Wrong path B — controller only
    Op->>Az: az vm update --set diskControllerType=NVMe
    Az-->>Op: InvalidParameter: D2s_v5 cannot boot with NVMe

    Note over Op,Az: ✅ Correct path — atomic PATCH
    Op->>Az: az vm update --set hardwareProfile.vmSize=Standard_D2as_v6 storageProfile.diskControllerType=NVMe
    Az-->>Op: Accepted

    Op->>Vm: az vm start
    Vm-->>Op: Booted on AMD EPYC 9V74<br/>root = /dev/nvme0n1p1
```

---

## 6. ADV-S03 / ADV-S04 — AvSet & PPG conservative runbook

Single-VM resize within an AvSet / PPG works in modern regions, but the supported
runbook is the conservative one:

```mermaid
flowchart LR
    subgraph SET["Availability Set or PPG"]
        VM1[VM1 - D2s_v3]
        VM2[VM2 - D2s_v3]
    end

    SET --> A[Deallocate ALL VMs]
    A --> B[Resize EACH VM to target SKU]
    B --> C[Start ALL VMs - any order]
    C --> D[Validate each guest health]
    D --> E[Verify AvSet / PPG metadata intact]
```

---

## 7. ADV-S05 — VMSS Manual upgrade

The two-step VMSS resize:

```mermaid
sequenceDiagram
    autonumber
    participant Op
    participant SS as VMSS Model
    participant I as Instances

    Op->>SS: az vmss update --set sku.name=Standard_D2s_v5
    SS-->>Op: Model updated · latestModelApplied=False on all instances

    Note over Op,I: Decide batch size for rolling effect

    loop For each batch
        Op->>I: az vmss update-instances --instance-ids 0,1
        I-->>Op: Instances recycled on new SKU
        Op->>I: az vmss run-command invoke (validate)
    end
```

---

## 8. AHB lifecycle (CORE-S04)

Azure Hybrid Benefit survives a resize but **does not** survive a recreate:

```mermaid
stateDiagram-v2
    [*] --> NoAHB: az vm create<br/>(default licenseType=null)
    NoAHB --> AHB: az vm update --set<br/>licenseType=Windows_Server
    AHB --> AHB_resized: az vm resize<br/>(cross-family)
    note right of AHB_resized
        AHB persists ✅
    end note
    AHB_resized --> NoAHB_recreated: az vm create --attach-os-disk<br/>(without --license-type)
    note right of NoAHB_recreated
        AHB lost ❌
        Re-apply explicitly
    end note
    NoAHB_recreated --> AHB: az vm update --set<br/>licenseType=Windows_Server
```
