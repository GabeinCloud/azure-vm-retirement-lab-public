# Security Policy

## Supported scope

This repository is a **lab / educational project** intended to be deployed into
short-lived demo subscriptions. It is not a production hardening reference.

The maintainers actively support:

- The latest commit on `main`.
- The Terraform configuration as published, with the documented variables and
  defaults.

## Reporting a vulnerability

If you discover something that looks like a security issue (leaked credential
in a commit, NSG rule wider than documented, default that exposes data, etc.),
please **do not open a public issue**.

Instead, open a private security advisory through GitHub:

1. Go to the repository's **Security** tab.
2. Click **Report a vulnerability**.
3. Provide a clear description and, if possible, a minimal reproduction.

You should receive an acknowledgement within a few business days.

## Security expectations and guarantees

| Item | Status |
|---|---|
| Hard-coded passwords or secrets in committed files | **Forbidden** — `terraform.tfvars.example` files use placeholder strings; real `terraform.tfvars` is gitignored. |
| Inbound `0.0.0.0/0` firewall rules | **Forbidden** — `allowed_source_ip` must be supplied by the user; there is no permissive default. |
| Public IP addresses | Opt-in via the `enable_public_ips` variable. |
| In-guest commands | Executed via `az vm run-command invoke` / `az vmss run-command invoke` (Azure management plane). No inbound shell required. |
| State files (`*.tfstate*`) | Local-only, gitignored. State contains the admin password — protect it accordingly. If you switch to remote state, use an encrypted backend with restricted access (Azure Storage + CMK + Private Endpoint, or Terraform Cloud). |
| `prevent_deletion_if_contains_resources = false` | Set deliberately so demo cleanup works. **Do not copy this provider block into production code.** |

## What this lab is NOT

- Not a hardened baseline. NSGs allow a single management port from a user-supplied
  source IP because the lab is meant to be poked at.
- Not multi-tenant. Each scenario assumes a single subscription / single operator.
- Not for sensitive data. Do not deploy a workload that handles real data into
  these VMs.

## Hardening checklist (for users adapting this lab to production)

If you base a production deployment on this code, at minimum:

- [ ] Move state to a remote, encrypted backend with RBAC.
- [ ] Replace `admin_password` with an SSH key (Linux) or Microsoft Entra ID /
      Azure Bastion (Windows).
- [ ] Use Azure Bastion or Microsoft Entra ID + Just-in-Time access instead of
      public IPs.
- [ ] Apply Azure Policy: deny public IPs, deny `0.0.0.0/0` NSG rules, require
      tags, etc.
- [ ] Enable Microsoft Defender for Cloud on the subscription.
- [ ] Enable Microsoft Defender for Servers on the VMs.
- [ ] Configure diagnostic settings and forward to a Log Analytics workspace.
- [ ] Replace the `Demo` `Environment` tag with the appropriate environment.
- [ ] Set `prevent_deletion_if_contains_resources = true` on the provider.
