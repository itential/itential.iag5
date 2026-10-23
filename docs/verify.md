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
  - [Connectivity Checks](#connectivity-checks)
  - [Proxy Checks](#proxy-checks)
  - [TLS File Checks](#tls-file-checks)
- [Non-Fatal Design](#non-fatal-design)
- [Variables Reference](#variables-reference)
- [Relationship to verify\_cert](#relationship-to-certify)

---

## Overview

`verify` catches environment problems before they surface during an install or upgrade:

| Category | What is checked | Where it runs |
|----------|----------------|---------------|
| OS | Distribution, version, and architecture | Managed node |
| Hardware | CPU, RAM, and disk against documented minimums | Managed node (servers and runners only) |
| Connectivity | Outbound reachability of required public repositories | Managed node |
| Proxy | Detects HTTP/HTTPS proxy configuration | Managed node |
| TLS files | Cert existence, PEM validity, expiry, cert/key match, CA chain, EKU, SANs | Control node |

The playbook targets three host groups: `iag5_servers`, `iag5_runners`, and `iag5_clients`. Any
group absent from your inventory is silently skipped. A fourth, final play aggregates and
reports the overall result across every host — see [Non-Fatal Design](#non-fatal-design).

---

## Architecture

`verify` follows the same structure as `certify`. Each gateway role has a
`tasks/verify.yml` orchestrator that delegates to shared task files in the
`verify_common` role.

```
itential.iag5/
├── playbooks/
│   └── verify.yml                             4-play standalone playbook (server, runner,
│                                               client, then a final aggregate report play)
└── roles/
    ├── gateway_server/
    │   ├── defaults/main/specs.yml                        Hardware minimums for servers and runners
    │   └── tasks/verify.yml                   Orchestrator — OS, specs, connectivity, proxy, TLS
    ├── gateway_client/
    │   └── tasks/verify.yml                   Orchestrator — OS, proxy, TLS (no specs/connectivity)
    └── verify_common/
        ├── defaults/main.yml
        └── tasks/
            ├── verify-os.yml                              OS distribution, version, architecture
            ├── verify-specs.yml                           CPU, RAM, disk
            ├── verify-connectivity.yml                    Required public repository reachability
            ├── verify-proxy.yml                           HTTP/HTTPS proxy detection
            ├── verify-tls-files.yml                       14 TLS file checks (control node)
            └── verify-results.yml                         Combines every check into one non-fatal
                                                             per-host result + per-component report
```

### How node type is determined

`gateway_application_mode` is set by the playbook (`server` or `runner`). For runner hosts this
directly selects `gateway_runner_hw_specs`. For server hosts it's not that simple: whether a
server is checked against `gateway_server_hw_specs` or `gateway_runner_hw_specs` also depends on
whether the inventory has a separate `iag5_runners` group:

| Inventory has... | `iag5_servers` hosts are checked against | Why |
|-------------------|-------------------------------------------|-----|
| Only `iag5_servers` (single-node all-in-one) | `gateway_runner_hw_specs` | The server also performs runner work locally, so it needs to meet the (higher) runner minimums |
| `iag5_servers` and `iag5_runners` (distributed execution) | `gateway_server_hw_specs` | Runner work happens on the dedicated runner hosts instead |

`roles/gateway_server/tasks/verify.yml` determines this the same way
`roles/gateway_server/tasks/certify-tls.yml` already detects the topology:
`'iag5_runners' in groups and groups['iag5_runners'] | length > 0`. When a server is acting as a
runner this way, its `component_name` in reports/logs is `"Server (acting as Runner)"` rather
than plain `"Server"`, so it's clear from the output which spec set was applied.

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

Which minimums apply to a given `iag5_servers` host is not fixed — see
[How node type is determined](#how-node-type-is-determined): in a single-node all-in-one
inventory (no `iag5_runners` group) servers are checked against the runner minimums instead,
since they perform runner work locally.

Hardware failures are collected across all three dimensions and reported together in a single
final assertion, so all failures are visible in one run. That final assertion is non-fatal —
see [Non-Fatal Design](#non-fatal-design).

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

### Connectivity Checks

Runs on: all node types (`iag5_servers`, `iag5_runners`, `iag5_clients`).

Checks outbound access to the "IAG5" rows of the README
[Required Public Repositories](../README.md#required-public-repositories) table.

For servers and runners, the list is built dynamically in `roles/gateway_server/tasks/verify.yml`
based on which optional features are enabled, so a host with, say, OpenTofu disabled isn't failed
against a repository it doesn't need:

| Repository | Included when |
|------------|---------------|
| `https://registry.aws.itential.com`, `https://itential.jfrog.io` | Always |
| `https://galaxy.ansible.com` | `gateway_server_features_ansible_enabled: true` (default) |
| `https://pypi.org`, `https://python.org`, `https://pythonhosted.org` | `gateway_server_features_python_enabled: true` (default) |
| `https://packages.opentofu.org`, `https://get.opentofu.org` | `gateway_server_features_opentofu_enabled: true` (default) |

For clients, `https://registry.aws.itential.com` and `https://itential.jfrog.io` are checked
(`gateway_client_required_repositories`, a static default — the client has no feature flags
gating additional repositories). This matters because `gateway_client_packages` can be an
`https://` URL rather than a local artifact path, and when it is, it's usually one of these two
Itential registries. A customer-supplied Nexus/GitLab URL is not checked — there's no generic
way to verify reachability of a customer-specific endpoint.

Any real HTTP response counts as reachable; only a connection-level failure (DNS/TCP/TLS/timeout)
counts as unreachable.

---

### Proxy Checks

Runs on: all node types (`iag5_servers`, `iag5_runners`, `iag5_clients`).

Checks the environment variables, `/etc/environment`, and `/etc/profile.d/` for proxy-related
settings. Detection is a warning, not a hard requirement failure — a proxy may be intentional —
but it's surfaced because it can explain otherwise-confusing connectivity or package-download
failures elsewhere in the install.

---

### TLS File Checks

Runs on: all node types when `gateway_pki_upload: true` (default).

All tasks delegate to the control node (`delegate_to: localhost`). Variables required:
`gateway_pki_src_dir`, and the PKI path defaults from the role (`gateway_server_pki_cert_src`,
`gateway_server_pki_key_src`, `gateway_server_pki_ca_cert_src`).

The whole sequence runs inside a `block`/`rescue`: the first "Hard fail? Yes" check that fails
stops the remaining TLS checks for this host (many are sequential — e.g. checking the cert/key
match is pointless if the cert file doesn't exist) and is recorded as this host's TLS failure.
It does not abort the playbook run — see [Non-Fatal Design](#non-fatal-design).

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

## Non-Fatal Design

Ansible aborts the *entire* `ansible-playbook` run — not just the current play — the moment a
play ends with 100% of its hosts failed, even for later, unrelated plays. Since `verify.yml` runs
servers, runners, and clients as three separate plays in sequence, a single bad server host could
otherwise prevent the runner and client plays from ever running.

To avoid that, every check in `verify_common` is non-fatal:

- `verify-os.yml` and `verify-specs.yml`'s final assertions use `ignore_errors: true` +
  `register:`, following the same collect-then-assert pattern already used for hardware specs.
- `verify-connectivity.yml` and `verify-proxy.yml` follow the identical pattern.
- `verify-tls-files.yml` wraps its whole sequence in a `block`/`rescue` instead — there are 14+
  individually hard-failing assertions, many of them intentionally sequential, so one `rescue`
  is simpler than converting every assertion individually. A failure anywhere in the block jumps
  to `rescue`, which records it via `ansible_failed_result.msg` and does not propagate as a host
  failure.

Each check's result is combined by `verify-results.yml` into a per-host `verification_passed`
fact (ANDed with any prior value, not overwritten — a host can be checked by more than one
component) and a `component_validation_errors` dict keyed by `component_name` (merged via
`combine()`, same reasoning). `playbooks/verify.yml` ends with a fourth play,
`hosts: all`, that prints `component_validation_errors` and then does the one real (non-ignored)
assert on `verification_passed`. Since nothing runs after that play, failing there is safe, and
it's what gives the whole run a genuine non-zero exit code while still letting every component's
checks run against every host regardless of earlier failures.

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

### Connectivity variables (gateway\_server role)

| Variable | Description |
|----------|-------------|
| `gateway_server_required_repositories` | Computed in `roles/gateway_server/tasks/verify.yml` (not a static default) — starts with `https://registry.aws.itential.com` and `https://itential.jfrog.io`, then appends the Ansible/Python/OpenTofu repositories only when the matching `gateway_server_features_*_enabled` flag is `true`. |
| `gateway_client_required_repositories` | Static default in `roles/gateway_client/defaults/main/install.yml` — `https://registry.aws.itential.com` and `https://itential.jfrog.io`. |
| `gateway_server_features_ansible_enabled` | Default `true`. Gates `https://galaxy.ansible.com`. |
| `gateway_server_features_python_enabled` | Default `true`. Gates `https://pypi.org`, `https://python.org`, `https://pythonhosted.org`. |
| `gateway_server_features_opentofu_enabled` | Default `true`. Gates `https://packages.opentofu.org`, `https://get.opentofu.org`. |

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
