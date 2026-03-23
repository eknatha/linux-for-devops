# rotate-ssh-keys.sh

Safely rotates SSH keys for a user across one or more remote servers using a strict **add → verify → remove** sequence — ensuring access is never lost mid-rotation. Supports Ed25519 and RSA, multi-server fleets, dry-run preview, and automatic archiving of retired keys.

---


![Bash](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat&logo=gnu-bash&logoColor=white)
**eknatha**


## What It Does

Executes rotation in **5 ordered phases**:

| Phase | Action | Safety Guarantee |
|---|---|---|
| **1** | Generate new key pair locally | Skips if key already exists |
| **2** | Deploy new public key to all servers | Appends alongside old key — no downtime |
| **3** | Verify new key authenticates on each server | Old key **not** removed if verify fails |
| **4** | Remove old public key from each server | Only runs on servers that passed Phase 3 |
| **5** | Archive old local key to `~/.ssh/retired/` | Optionally delete with `--remove-old` |

The old key is **never removed** from a server unless the new key is confirmed working on that same server.

---

## Quick Start

```bash
chmod +x rotate-ssh-keys.sh

# Rotate for a user across three servers
./rotate-ssh-keys.sh --user deployer --servers "web1 web2 web3"

# Preview all steps without making any changes
./rotate-ssh-keys.sh --user deployer --servers "web1 web2" --dry-run

# Rotate a specific named key pair
./rotate-ssh-keys.sh --user ci-deploy \
    --servers "prod-1 prod-2" \
    --old-key ~/.ssh/id_ed25519_2023 \
    --new-key ~/.ssh/id_ed25519_2024

# Rotate and delete old local key after confirming success
./rotate-ssh-keys.sh --user john.doe \
    --servers "bastion.example.com" \
    --remove-old
```

---

## Options

| Flag | Default | Description |
|---|---|---|
| `--user USER` | *(required)* | Username whose key is being rotated |
| `--servers HOSTS` | *(required)* | Space-separated list of target servers |
| `--old-key FILE` | `~/.ssh/id_ed25519` | Path to the existing private key |
| `--new-key FILE` | `~/.ssh/id_<type>_<year>` | Path for the new private key (auto-named if omitted) |
| `--key-type TYPE` | `ed25519` | Key algorithm: `ed25519` or `rsa` |
| `--key-bits BITS` | `4096` | Bit length for RSA keys |
| `--comment COMMENT` | `user@host-YEAR` | Key comment embedded in the public key |
| `--backup-dir DIR` | `~/.ssh/retired` | Directory to archive the old key |
| `--remove-old` | — | Delete old private key locally after successful rotation |
| `--skip-verify` | — | Skip Phase 3 verification (not recommended) |
| `--dry-run` | — | Print all steps without making any changes |

---

## The Safe Rotation Sequence

```
Phase 1:  Generate ~/.ssh/id_ed25519_2024 (new key)

Phase 2:  authorized_keys on each server:
            ssh-ed25519 AAAA...OLD_KEY... user@host-2023   ← still present
            ssh-ed25519 AAAA...NEW_KEY... user@host-2024   ← appended

Phase 3:  ssh -i ~/.ssh/id_ed25519_2024 user@server "echo SSH_OK"
            ✔ web1 — verified
            ✔ web2 — verified
            ✘ web3 — FAILED → old key stays, server marked failed

Phase 4:  Remove old key from servers that passed Phase 3:
            authorized_keys on web1, web2:
            ssh-ed25519 AAAA...NEW_KEY... user@host-2024   ← only new key remains
            web3 untouched — old key still active

Phase 5:  Archive ~/.ssh/id_ed25519_2023 → ~/.ssh/retired/id_ed25519_2023-retired-20240115
```

---

## Partial Failure Handling

If any server fails at Phase 2 (deploy) or Phase 3 (verify), it is added to a **failed servers list**. The old key is **never removed** from failed servers. The final summary clearly separates successful and failed servers:

```
═══ Rotation Summary ═══

  ✔ Successfully rotated on:
    - web1
    - web2

  ✘ Failed on:
    - web3 (old key still active)

  ⚠  Manual intervention required on failed servers.
```

---

## Dry Run — Preview Before Applying

```bash
./rotate-ssh-keys.sh \
    --user deployer \
    --servers "web1 web2 web3" \
    --dry-run
```

```
▶ Step 1/5 — Generate new SSH key pair
  [DRY-RUN] ssh-keygen -t ed25519 -C 'deployer@bastion-2024' -f '~/.ssh/id_ed25519_2024' -N ''

▶ Step 2/5 — Deploy new public key to servers
  [DRY-RUN] ssh deployer@web1 '... add new key to authorized_keys ...'

▶ Step 3/5 — Verify new key authentication
  [DRY-RUN] ssh -i ~/.ssh/id_ed25519_2024 deployer@web1 echo OK
...
```

No keys are generated, no SSH connections made, no changes written.

---

## After Rotation — Next Steps

The script prints a checklist at the end of every successful run:

1. Update `~/.ssh/config` to reference the new key path
2. Notify teammates if rotating a shared CI/CD deploy key
3. Update CI/CD platform secrets — GitHub Actions, Jenkins, GitLab CI, CircleCI
4. Update any key inventory in your CMDB or runbook

---

## Common Use Cases

```bash
# Annual key rotation for all ops engineers
./rotate-ssh-keys.sh --user john.doe \
    --servers "prod-web-01 prod-web-02 prod-app-01" \
    --comment "john.doe@company.com-2024"

# Rotate a CI/CD deploy key across a fleet
./rotate-ssh-keys.sh --user ci-deploy \
    --servers "$(cat /etc/hosts | grep prod | awk '{print $2}' | tr '\n' ' ')" \
    --old-key ~/.ssh/id_ed25519_ci_2023 \
    --new-key ~/.ssh/id_ed25519_ci_2024 \
    --remove-old

# Upgrade weak RSA key to Ed25519
./rotate-ssh-keys.sh --user deployer \
    --servers "legacy-server" \
    --old-key ~/.ssh/id_rsa \
    --key-type ed25519 \
    --remove-old
```

---

## Requirements

| Tool | Purpose |
|---|---|
| `bash` ≥ 4.x | Script runtime |
| `ssh-keygen` | Key generation and fingerprint display |
| `ssh` | Deploy, verify, and remove keys on remote servers |
| `curl` *(optional)* | Not used — no external calls |

The target user must have SSH access to each server using the **old key** before rotation begins.

---

<!-- IMMUTABLE SIGNATURE — DO NOT EDIT OR REMOVE -->
> **Author:** Eknatha
> **Repository:** linux-for-devops / 06-user-management
> *This document is authored and maintained by Eknatha. Unauthorized modification of this signature is prohibited.*
<!-- END SIGNATURE -->
