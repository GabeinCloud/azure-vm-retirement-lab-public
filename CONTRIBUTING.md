# Contributing

Thanks for considering a contribution! This lab is small and opinionated; the
goal is to keep it accurate, safe to deploy in any subscription, and easy to
follow.

## Ground rules

1. **Never commit secrets.** Passwords, SSH private keys, subscription IDs,
   tenant IDs and email addresses must not appear in PRs. The CI pipeline (and
   manual review) will reject any PR that introduces one.
2. **Keep scenarios self-contained.** Each scenario folder must work on its own:
   its own RG, VNet, state and README. No cross-scenario imports.
3. **Default to secure.** No `0.0.0.0/0` NSG rules. No public IPs without an
   opt-in variable. No inbound shell required for validation — use
   `az vm run-command invoke`.
4. **English only** in code, comments, READMEs and commit messages.
5. **Tests are manual but reproducible.** If you change a scenario, deploy it
   end-to-end in your own subscription and include the captured outputs (CPU
   family, hostnames, IPs, timings) in the PR description. Redact subscription
   and tenant IDs.

## What we accept gladly

- Bug fixes to existing scenarios.
- New scenarios that demonstrate a documented retirement edge case (e.g. M192
  with ANF-anchored AvSet, NVv4 → NVads_V710_v5 known issue, etc.).
- Improvements to the operational guide backed by an official Microsoft Learn
  reference.
- Updates that track new `azurerm` provider major versions.
- Mermaid diagrams that clarify a flow.

## What we will probably reject

- Cosmetic-only changes (whitespace, reflow).
- Switching to a different IaC tool (Bicep, Pulumi, ARM) — feel free to fork.
- Production hardening as default (it belongs in your own infrastructure
  repository, not in a lab).
- New scenarios without a matching real-world retirement reference.

## Workflow

```bash
# 1. Fork and clone
git clone https://github.com/<your-user>/azure-vm-retirement-lab.git
cd azure-vm-retirement-lab

# 2. Create a feature branch
git checkout -b feat/<short-name>

# 3. Make changes in a single scenario folder when possible

# 4. Validate locally
cd <scenario-folder>
terraform fmt -recursive
terraform init
terraform validate

# 5. Commit and push
git commit -m "feat(<scenario>): <what changed>"
git push -u origin feat/<short-name>

# 6. Open a PR — describe what you tested in your subscription
```

## Commit message convention

Loosely follows [Conventional Commits](https://www.conventionalcommits.org/):

- `feat(<scenario>): <summary>` — new feature or new scenario
- `fix(<scenario>): <summary>` — bug fix
- `docs: <summary>` — documentation only
- `chore: <summary>` — tooling, dependencies, .gitignore, etc.

## Code style

- `terraform fmt -recursive` must produce no diff before you push.
- Resource names follow the patterns already in place (`vnet-<scenario>`,
  `nic-<vm>`, `pip-<vm>`).
- Variables: snake_case, with `type` and (where useful) `default` and
  `description`.
- Comments in code are welcome when they explain *why*, not *what*.
