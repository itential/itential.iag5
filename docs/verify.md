# verify — IAG5 Pre-Flight Environment Verification

An Ansible playbook that verifies target hosts are ready for an IAG5 installation or upgrade
before any software is deployed. All checks run either on the control node (TLS file checks) or
against the managed node via SSH (OS and hardware checks). No IAG5 software needs to be installed
for this playbook to run.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Usage](#usage)
- [Check Reference](#check-reference)
  - [OS Checks](#os-checks)
  - [Hardware Spec Checks](#hardware-spec-checks)
  - [TLS File Checks](#tls-file-checks)
- [Variables Reference](#variables-reference)
- [Relationship to verify\_cert](#relationship-to-certify)

---

## Overview

`verify` catches environment problems before they surface during an install or upgrade:

| Category | What is checked | Where it runs |
|----------|----------------|---------------|
| OS | Distribution, version, and architecture | Managed node |
| Hardware | CPU, RAM, and disk against documented minimums | Managed node (servers and runners only) |
| TLS files | Cert existence, PEM validity, expiry, cert/key match, CA chain, EKU, SANs | Control node |

The playbook targets three host groups: `iag5_servers`, `iag5_runners`, and `iag5_clients`. Any
group absent from your inventory is silently skipped.

---

## Architecture

`verify` follows the same structure as `certify`. Each gateway role has a
`tasks/verify.yml` orchestrator that delegates to shared task files in the
`verify_common` role.

```
itential.iag5/
├── playbooks/
│   └── verify.yml                             3-play standalone playbook
└── roles/
    ├── gateway_server/
    │   ├── defaults/main/specs.yml                        Hardware minimums for servers and runners
    │   └── tasks/verify.yml                   Orchestrator — OS, specs, TLS
    ├── gateway_client/
    │   └── tasks/verify.yml                   Orchestrator — OS, TLS (no specs)
    └── verify_common/
        ├── defaults/main.yml
        └── tasks/
            ├── verify-os.yml                              OS distribution, version, architecture
            ├── verify-specs.yml                           CPU, RAM, disk
            └── verify-tls-files.yml                       14 TLS file checks (control node)
```

### How node type is determined

`gateway_application_mode` is set by the playbook (`server` or `runner`) and controls which
hardware spec defaults are used for the specs check.

### TLS check delegation

All tasks in `verify-tls-files.yml` run `delegate_to: localhost` because the TLS source files
reside on the control node (in `gateway_pki_src_dir`) before upload. No SSH connection to the
managed node is needed for TLS checks.

---

## Prerequisites

- Ansible installed on the control node
- SSH access to all IAG5 target nodes
- `openssl` available on the control node (standard on macOS and RHEL/Rocky)
- TLS source files present at `gateway_pki_src_dir` (if `gateway_pki_upload: true`)

---

## Usage

Run before an installation or upgrade:

```bash
ansible-playbook itential.iag5.verify -i inventories/<env>
```

Run against a single node:

```bash
ansible-playbook itential.iag5.verify -i inventories/<env> --limit ip-10-222-0-187.ec2.internal
```

Run only the OS and hardware checks (skip TLS):

```bash
ansible-playbook itential.iag5.verify -i inventories/<env> -e "gateway_pki_upload=false"
```

---

## Check Reference

### OS Checks

Runs on: all node types (`iag5_servers`, `iag5_runners`, `iag5_clients`).

Requires: `gather_facts: true` (default).

| Check | Description | Hard fail? |
|-------|-------------|-----------|
| Supported OS | `ansible_distribution` must be `RedHat` or `Rocky`, major version must be `8` or `9` | Yes |
| Supported architecture | `ansible_architecture` must be `x86_64` | Yes |

---

### Hardware Spec Checks

Runs on: `iag5_servers` and `iag5_runners` only. Clients have no documented hardware minimums
and are skipped.

Hardware failures are collected across all three dimensions and reported together in a single
final assertion, so all failures are visible in one run.

| Check | Server minimum | Runner minimum | Hard fail? |
|-------|---------------|----------------|-----------|
| CPU count | 1 vCPU | 4 vCPUs | Yes (collected) |
| RAM | 2 GB | 8 GB | Yes (collected) |
| Disk (root partition) | 10 GB | 20 GB | Yes (collected) |

Minimums are sourced from the IAG5 hardware documentation and stored in
`roles/gateway_server/defaults/main/specs.yml`. Override per host or group in your inventory:

```yaml
iag5_runners:
  vars:
    gateway_runner_hw_specs:
      cpu_min: 8
      ram_min_gb: 16
      disk_min_gb: 40
```

---

### TLS File Checks

Runs on: all node types when `gateway_pki_upload: true` (default).

All tasks delegate to the control node (`delegate_to: localhost`). Variables required:
`gateway_pki_src_dir`, and the PKI path defaults from the role (`gateway_server_pki_cert_src`,
`gateway_server_pki_key_src`, `gateway_server_pki_ca_cert_src`).

| Check | Description | Hard fail? |
|-------|-------------|-----------|
| Cert file exists | Cert file present at `gateway_pki_src_dir/<hostname>.crt` | Yes |
| Key file exists | Key file present at `gateway_pki_src_dir/<hostname>.key` | Yes |
| CA cert file exists | CA cert present at `gateway_pki_src_dir/ca.crt` | Yes |
| Cert is valid PEM | `openssl x509 -noout -in <cert>` exits 0 | Yes |
| CA cert is valid PEM | `openssl x509 -noout -in <ca>` exits 0 | Yes |
| Key is parseable | `openssl pkey -noout -in <key>` exits 0 | Yes |
| Cert is not expired | `openssl x509 -checkend 0` exits 0 | Yes |
| Cert not expiring within 30 days | `openssl x509 -checkend 2592000` | Warn |
| Cert and key are a matched pair | Public key extracted from cert matches public key derived from private key | Yes |
| CA cert has `CA:TRUE` | Basic Constraints extension includes `CA:TRUE` | Yes |
| Cert is signed by CA | `openssl verify -CAfile <ca> <cert>` returns `OK` | Yes |
| Cert is not self-signed | Subject hash does not equal issuer hash | Yes |
| Cert has `serverAuth` in EKU | Extended Key Usage includes TLS Web Server Authentication | Warn |
| Cert has `clientAuth` in EKU | Extended Key Usage includes TLS Web Client Authentication | Warn |
| SANs present (servers and runners only) | Subject Alternative Name extension present in cert | Yes |
| `inventory_hostname` in SANs (servers and runners only) | Hostname appears in SAN DNS entries | Warn |
| `ansible_host` in SANs (servers and runners only) | Connection address appears in SAN entries | Warn |

> **EKU note:** The `itential.tls` collection does not add Extended Key Usage to generated certs
> by default. EKU checks are warnings rather than hard failures to remain compatible with certs
> generated this way. For best security, update cert generation to include `serverAuth` and
> `clientAuth`.

---

## Variables Reference

### Hardware spec variables (gateway\_server role)

| Variable | Default | Description |
|----------|---------|-------------|
| `gateway_server_hw_specs.cpu_min` | `1` | Minimum vCPUs for server nodes |
| `gateway_server_hw_specs.ram_min_gb` | `2` | Minimum RAM (GB) for server nodes |
| `gateway_server_hw_specs.disk_min_gb` | `10` | Minimum root disk (GB) for server nodes |
| `gateway_runner_hw_specs.cpu_min` | `4` | Minimum vCPUs for runner nodes |
| `gateway_runner_hw_specs.ram_min_gb` | `8` | Minimum RAM (GB) for runner nodes |
| `gateway_runner_hw_specs.disk_min_gb` | `20` | Minimum root disk (GB) for runner nodes |

### Inventory variables

| Variable | Required | Description |
|----------|----------|-------------|
| `gateway_pki_src_dir` | Yes (when `gateway_pki_upload: true`) | Local directory on the control node containing TLS cert files |
| `gateway_pki_upload` | No (default: `true`) | Set to `false` to skip TLS file checks |
| `ansible_host` | Yes | Address Ansible uses to SSH into the node |
| `ansible_user` | Yes | SSH user |
| `ansible_ssh_private_key_file` | Yes (or equivalent auth) | SSH key path |

---

## Relationship to verify\_cert

`verify` and `certify` are complementary, not overlapping:

| | verify\_environment | verify\_cert |
|-|---------------------|-------------|
| When to run | Before install or upgrade | After install or upgrade |
| TLS checks target | Source files on control node | Deployed certs on managed nodes |
| Reads `gateway.conf` | No | Yes |
| Live TLS handshakes | No | Yes |
| Hardware checks | Yes | No |
| OS checks | Yes | No |

Run `verify` first to confirm the environment is ready, then `certify` after
deployment to confirm mTLS is working end-to-end.
