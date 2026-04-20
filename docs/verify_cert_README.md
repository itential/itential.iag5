# verify_cert — IAG5 TLS Certificate Verification

An Ansible playbook suite that verifies TLS certificate configuration across all IAG5 node types after deployment. Runs against live nodes, reads actual `gateway.conf` files, and performs live TLS handshakes to confirm that mTLS is working end-to-end — not just that files exist.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Directory Structure](#directory-structure)
- [Inventory](#inventory)
- [Usage](#usage)
- [Check Reference](#check-reference)
  - [cluster\_server\_to\_runner](#cluster_server_to_runner)
  - [cluster\_client\_to\_server](#cluster_client_to_server)
  - [connect\_server\_to\_gwm](#connect_server_to_gwm)
- [Output and Status Codes](#output-and-status-codes)
- [Variables Reference](#variables-reference)
- [Integration with itential.iag5 Deployer](#integration-with-itentialiag5-deployer)

---

## Overview

IAG5 uses three distinct TLS connection paths, each with different certificate requirements:

| Path | Protocol | TLS Type | Cert requirement | Run condition |
|------|----------|----------|-----------------|---------------|
| Server ↔ Runner | gRPC over TCP | Mutual TLS (mTLS) | Both `serverAuth` + `clientAuth` in EKU (Extended Key Usage) | `gateway_server_use_tls: true` |
| Client ↔ Server | gRPC over TCP | Mutual TLS (mTLS) | Both `serverAuth` + `clientAuth` in EKU (Extended Key Usage) | `gateway_client_use_tls: true` |
| Server → Gateway Manager | WebSocket (wss://) | One-way TLS | `clientAuth` in EKU (Extended Key Usage); GWM cert publicly trusted | `gateway_server_use_tls: true` |

> **EKU (Extended Key Usage)** — an X.509 certificate extension that defines the purposes the certificate may be used for. `serverAuth` allows the cert to authenticate a server; `clientAuth` allows it to authenticate a client. mTLS requires both on every node cert.

verify_cert covers all three paths. For each path it runs on both sides of the connection independently, so a misconfiguration on either end is caught.

---

## Architecture

verify_cert is colocated with the roles being verified. Each gateway role has a `tasks/verify_cert.yml` orchestrator that runs the appropriate check suites. A shared `verify_cert_common` role provides the check task files and report template.

```
itential.iag5/
├── playbooks/
│   ├── site.yml                                          Main playbook — imports verify_cert at end
│   └── verify_cert.yml                                   2-play verify_cert playbook
└── roles/
    ├── gateway_server/
    │   └── tasks/verify_cert.yml                         Orchestrator — runs SUITE 1, 2, 3 conditionally
    ├── gateway_client/
    │   └── tasks/verify_cert.yml                         Orchestrator — runs SUITE 1 (client side)
    └── verify_cert_common/
        ├── defaults/main.yml                             Report path defaults and os_ca_bundle
        ├── tasks/
        │   ├── summary.yml                               Shared summary printer and report generator
        │   ├── verify_cert_cluster_server_to_runner.yml  27 checks — server and runner nodes
        │   ├── verify_cert_cluster_client_to_server.yml  26 checks — client and server nodes
        │   └── verify_cert_connect_server_to_gwm.yml    20 checks — server → GWM
        └── templates/verify-cert-report.md.j2           Markdown report template
```

### How node identity is determined

Node type is read from `gateway_application_mode`, which the deployer already sets to `runner` on runner nodes and leaves unset (defaults to `server`) on server nodes. This cleanly replaces the group-membership lookup used in older versions.

```yaml
node_section: "{{ gateway_application_mode | default('server') }}"
```

### Test suite selection

The `gateway_server/tasks/verify_cert.yml` orchestrator targets `iag5_servers:iag5_runners` and selects suites automatically from inventory topology — no extra variables required:

| Suite | Condition |
|-------|-----------|
| SUITE 1 — Cluster server ↔ runner | Always on runner nodes; on server nodes only when `iag5_runners` group has hosts |
| SUITE 2 — Cluster client ↔ server (server side) | Server nodes only when `iag5_clients` group has hosts |
| SUITE 3 — Connect server → GWM | Always on server nodes (GWM is always present) |

The `gateway_client/tasks/verify_cert.yml` orchestrator runs SUITE 1 (client side) on all `iag5_clients` hosts. The play itself only runs when those hosts exist, so no guard is needed.

### EKU gating

The Extended Key Usage check (CHECK 19 in `cluster_server_to_runner`, CHECK 16 in `cluster_client_to_server`) acts as a hard gate. If a cert is missing `clientAuth` or `serverAuth`, the live mTLS handshake checks are skipped rather than run and fail with a misleading error. The gate is set via the `eku_valid` fact:

```yaml
eku_valid: "{{ tls_enabled and
  'Server Authentication' in (node_eku.stdout | default('')) and
  'Client Authentication' in (node_eku.stdout | default('')) }}"
```

Any check that requires a working mTLS connection carries `when: eku_valid | default(false)` on its shell task.

---

## Prerequisites

- Ansible installed on the control node
- SSH access to all IAG5 nodes
- `openssl` available on all target nodes (standard on RHEL/Rocky)
- `curl` available on the server node (for WebSocket check)
- The IAG5 service (`iagctl`) must be running on all nodes

---

## Directory Structure

```
itential.iag5/
├── playbooks/
│   ├── site.yml
│   └── verify_cert.yml
└── roles/
    ├── gateway_server/
    │   └── tasks/
    │       └── verify_cert.yml                            Orchestrator (INIT + 3 suites)
    ├── gateway_client/
    │   └── tasks/
    │       └── verify_cert.yml                            Orchestrator (INIT + 1 suite)
    └── verify_cert_common/
        ├── defaults/main.yml
        ├── tasks/
        │   ├── summary.yml
        │   ├── verify_cert_cluster_server_to_runner.yml
        │   ├── verify_cert_cluster_client_to_server.yml
        │   └── verify_cert_connect_server_to_gwm.yml
        └── templates/verify-cert-report.md.j2
```

---

## Inventory

verify_cert uses the deployer's existing inventory — no separate inventory file is required. The host groups `iag5_servers`, `iag5_runners`, and `iag5_clients` are already defined by the deployer and are used directly by the verify_cert roles.

### Host IP resolution

verify_cert derives each node's IP from `ansible_default_ipv4.address`, which Ansible gathers directly from the host's default route interface. This means `private_ip` does **not** need to be set in the inventory.

The resolved IP is used for:

- SAN validation (CHECK 8a/8b, CHECK 17b, CHECK 12c)
- `no_proxy` validation (CHECK 23, CHECK 24)
- Live connection targets (CHECK 25, CHECK 26, CHECK 27)

If a node's certificate SAN is set to an IP that differs from its default route interface IP (uncommon — typically only when using a bastion host), override `private_ip` per host in your inventory:

```yaml
iag5_servers:
  hosts:
    gateway_server:
      private_ip: 10.1.2.3   # only if cert SAN IP differs from ansible_default_ipv4.address
```

---

## Usage

### Run all checks

```bash
ansible-playbook itential.iag5.verify_cert -i inventories/dev/hosts
```

### Run a specific connection path only

```bash
# Server ↔ Runner mTLS checks
ansible-playbook itential.iag5.verify_cert -i inventories/dev/hosts --tags cluster_server_to_runner

# Client ↔ Server mTLS checks
ansible-playbook itential.iag5.verify_cert -i inventories/dev/hosts --tags cluster_client_to_server

# Server → Gateway Manager WebSocket TLS checks
ansible-playbook itential.iag5.verify_cert -i inventories/dev/hosts --tags connect_server_to_gwm
```

### Run on a single node

```bash
ansible-playbook itential.iag5.verify_cert -i inventories/dev/hosts --limit gateway_runner
```

### Increase verbosity to see raw openssl output

```bash
ansible-playbook itential.iag5.verify_cert -i inventories/dev/hosts -v
```

---

## Check Reference

### cluster\_server\_to\_runner

Runs on: **server node** and **runner node** independently.

TLS type: **Mutual TLS (mTLS)** over gRPC/TCP.

Config file read: `/etc/gateway/gateway.conf` (both server and runner use the same path).

| Check | Description | Node | Hard fail? |
|-------|-------------|------|-----------|
| CHECK 1 | `ca_certificate_file` set in `[application]` | Both | Yes |
| CHECK 2 | CA cert file exists on disk | Both | Yes |
| CHECK 3 | CA bundle contains at least 1 cert; PASS if ≥ 2 (root + intermediate), WARN if exactly 1 (root only — valid but no intermediate), FAIL if 0 | Both | Warn if 1, fail if 0 |
| CHECK 4 | CA cert has `CA:TRUE` basic constraint | Both | Yes |
| CHECK 5 | Last cert in CA bundle is self-signed root (subject hash == issuer hash) | Both | Yes |
| CHECK 6 | `use_tls = true` in `[server]` or `[runner]` section | Both | Yes — gates all subsequent cert checks |
| CHECK 7 | `distributed_execution = true` in `[server]` (server); `listen_address` set in `[runner]` (runner) | Split | Yes |
| CHECK 8a | Inventory `private_ip` present on runner's actual network interface | Runner | Yes |
| CHECK 9 | `certificate_file` set in `[server]`/`[runner]` section | Both | Yes |
| CHECK 10 | Certificate file exists on disk | Both | Yes |
| CHECK 10b | Runner cert SAN contains inventory `private_ip` as `IP:` entry | Runner | Yes |
| CHECK 11 | `private_key_file` set in `[server]`/`[runner]` section | Both | Yes |
| CHECK 12 | Private key file exists on disk | Both | Yes |
| CHECK 13 | Cert and key are a matched pair (modulus MD5 comparison) | Both | Yes |
| CHECK 14 | Certificate is not expired | Both | Yes |
| CHECK 15 | Certificate has more than 30 days remaining | Both | Warn if < 30 days |
| CHECK 16 | Certificate is not a self-signed leaf (subject ≠ issuer) | Both | Yes |
| CHECK 17a | Subject Alternative Name extension is present | Both | Yes |
| CHECK 17b | Server cert SAN contains `private_ip` as `IP:` entry | Server | Yes |
| CHECK 17c | Server cert SAN contains `ansible_host` as `DNS:` entry | Server | Warn |
| CHECK 18 | Certificate is signed by the CA (`openssl verify`) | Both | Yes |
| CHECK 19 | EKU contains both `serverAuth` and `clientAuth` | Both | Yes — **gates CHECKs 20 and 27** |
| CHECK 20 | Runner enforces mTLS — rejects connection without client cert | Server | Yes |
| CHECK 21 | `iagctl` service running; GATEWAY env vars visible in process | Both | Warn |
| CHECK 22 | `no_proxy`/`NO_PROXY` set in systemd service | Server | Warn |
| CHECK 23 | Each runner `private_ip` present in `no_proxy` | Server | Yes |
| CHECK 24 | Each runner `ansible_host` present in `no_proxy` | Server | Yes |
| CHECK 25 | Runner IPs resolve via DNS from server | Server | Yes |
| CHECK 26 | TCP connectivity from server to each runner on `runner_port` | Server | Yes |
| CHECK 27 | Live mTLS handshake with IP verification server → each runner | Server | Yes |

---

### cluster\_client\_to\_server

Runs on: **client node** and **server node** independently.

TLS type: **Mutual TLS (mTLS)** over gRPC/TCP.

Config files read:
- Client node: `/home/itential/.gateway.d/gateway.conf` → reads `[client]` section
- Server node: `/etc/gateway/gateway.conf` → reads `[server]` section

| Check | Description | Node | Hard fail? |
|-------|-------------|------|-----------|
| CHECK 1 | `ca_certificate_file` set in `[application]` | Both | Yes |
| CHECK 2 | CA cert file exists on disk | Both | Yes |
| CHECK 3 | CA bundle contains at least 1 cert; PASS if ≥ 2 (root + intermediate), WARN if exactly 1 (root only — valid but no intermediate), FAIL if 0 | Both | Warn if 1, fail if 0 |
| CHECK 4 | CA cert has `CA:TRUE` basic constraint | Both | Yes |
| CHECK 5 | Last cert in CA bundle is self-signed root | Both | Yes |
| CHECK 6 | `use_tls = true` in `[client]` or `[server]` section | Both | Yes — gates all cert checks |
| CHECK 7 | `certificate_file` set in `[client]`/`[server]` section | Both | Yes |
| CHECK 8 | Certificate file exists on disk | Both | Yes |
| CHECK 9 | `private_key_file` set in `[client]`/`[server]` section | Both | Yes |
| CHECK 10 | Private key file exists on disk | Both | Yes |
| CHECK 11 | Cert and key are a matched pair | Both | Yes |
| CHECK 12 | Certificate is not expired | Both | Yes |
| CHECK 13 | Certificate has more than 30 days remaining | Both | Warn if < 30 days |
| CHECK 14 | Certificate is not a self-signed leaf | Both | Yes |
| CHECK 15 | Certificate is signed by the CA (`openssl verify`) | Both | Yes |
| CHECK 16 | EKU contains both `serverAuth` and `clientAuth` | Both | Yes — **gates CHECKs 22 and 26** |
| CHECK 17a | Subject Alternative Name extension is present | Server | Yes |
| CHECK 17b | Server cert SAN contains `private_ip` as `IP:` entry | Server | Yes |
| CHECK 17c | Server cert SAN contains `ansible_host` as `DNS:` entry | Server | Warn |
| CHECK 19 | `no_proxy`/`NO_PROXY` set in systemd service | Client | Warn |
| CHECK 20 | Server `private_ip` present in `no_proxy` | Client | Yes |
| CHECK 21 | Server `ansible_host` present in `no_proxy` | Client | Yes |
| CHECK 22 | Server enforces mTLS — rejects connection without client cert | Client | Yes |
| CHECK 23 | `iagctl` service running; GATEWAY env vars visible in process | Both | Warn |
| CHECK 24 | Server IP resolves via DNS from client | Client | Yes |
| CHECK 25 | TCP connectivity from client to server on `server_port` | Client | Yes |
| CHECK 26 | Live mTLS handshake with IP verification client → server | Client | Yes |

---

### connect\_server\_to\_gwm

Runs on: **server node** only.

TLS type: **One-way TLS** (server authenticates Gateway Manager's cert; GWM does not validate the server cert at the TLS layer — authentication is handled at the application layer).

Config file read: `/etc/gateway/gateway.conf` → reads `[connect]` section.

| Check | Description | Hard fail? |
|-------|-------------|-----------|
| CHECK 1 | `[connect] enabled = true` | Yes — gates all checks |
| CHECK 2 | `[connect] hosts` set (GWM IP:port) | Yes |
| CHECK 3 | `certificate_file` set in `[connect]` section | Yes |
| CHECK 4 | Certificate file exists on disk | Yes |
| CHECK 5 | `private_key_file` set in `[connect]` section | Yes |
| CHECK 6 | Private key file exists on disk | Yes |
| CHECK 7 | Cert and key are a matched pair | Yes |
| CHECK 8 | Certificate is not expired | Yes |
| CHECK 9 | Certificate has more than 30 days remaining | Warn if < 30 days |
| CHECK 10 | Cert type identified (self-signed leaf is valid for connect) | Info |
| CHECK 11 | EKU contains `clientAuth` (required for GWM app-layer auth) | Warn if missing |
| CHECK 12 | Subject Alternative Name extension present | Warn |
| CHECK 13 | Cert SAN contains server `private_ip` as `IP:` entry | Warn |
| CHECK 14 | `no_proxy`/`NO_PROXY` set in systemd service | Warn |
| CHECK 15 | GWM host present in `no_proxy` | Warn |
| CHECK 16 | GWM hostname resolves from server | Yes |
| CHECK 17 | TCP connectivity from server to GWM | Yes |
| CHECK 18 | GWM server cert trusted by OS CA pool (`openssl s_client` against OS bundle) | Yes |
| CHECK 19 | WebSocket handshake to GWM returns HTTP 101 | Warn |
| CHECK 20 | `iagctl` service running; GATEWAY_CONNECT env vars visible in process | Warn |

#### Why `clientAuth` is only a WARN for connect

For the server ↔ runner and client ↔ server paths, missing `clientAuth` in EKU causes a hard TLS handshake rejection. For the connect path, the TLS layer is one-way — GWM validates its own cert but does not require a client cert. The `clientAuth` EKU is needed for GWM's **application-layer** authentication, not the TLS layer, so the absence produces a softer error rather than a hard connection failure.

---

## Output and Status Codes

Each check produces one of five statuses:

| Status | Meaning |
|--------|---------|
| `✅ PASS` | Check passed |
| `❌ FAIL` | Check failed — connection or deployment will not work |
| `⚠️  WARN` | Non-fatal issue — deployment may work but attention is needed |
| `⏭ SKIPPED` | Check was intentionally skipped because a prerequisite failed (e.g., TLS disabled, EKU invalid) |
| `ℹ️  INFO` | Informational — not a pass or fail |

At the end of each play, the summary task prints a table of all check results for that node:

```
============================================================
CLUSTER TLS — SERVER ↔ RUNNER (gRPC mTLS) — SERVER NODE — gateway_server
============================================================
✅ PASS | CHECK 1 — [application] ca_certificate_file is set
         Expected : ca_certificate_file = /path/to/ca-bundle.crt
         Actual   : ca_certificate_file = '/etc/gateway/ssl/ca.crt'
------------------------------------------------------------
✅ PASS | CHECK 19 — [server] cert has both serverAuth and clientAuth in extendedKeyUsage
         Expected : TLS Web Server Authentication, TLS Web Client Authentication
         Actual   : TLS Web Server Authentication, TLS Web Client Authentication
------------------------------------------------------------
❌ FAIL | CHECK 27 — TLS handshake with IP verification SERVER → RUNNER (10.222.1.76)
         Expected : Verify return code: 0 (ok)
         Actual   : Verify return code: 21 (unable to verify the first certificate)
------------------------------------------------------------
```

All plays use `ignore_errors: true` so a failure in one check does not abort the remaining checks. The full picture is always shown.

---

## Variables Reference

### `vars/common.yml`

| Variable | Default | Description |
|----------|---------|-------------|
| `server_gateway_conf` | `/etc/gateway/gateway.conf` | Path to gateway.conf on server and runner nodes |
| `client_gateway_conf` | `/home/itential/.gateway.d/gateway.conf` | Path to gateway.conf on client nodes |
| `service_name` | `iagctl` | systemd service name — used for PID lookup and env var checks |

### `vars/cluster_server_to_runner.yml`

| Variable | Default | Description |
|----------|---------|-------------|
| `runner_port` | `50051` | Port the runner listens on for gRPC from the server |

### `vars/cluster_client_to_server.yml`

| Variable | Default | Description |
|----------|---------|-------------|
| `server_port` | `50051` | Port the server listens on for gRPC from clients |

### `vars/connect_server_to_gwm.yml`

| Variable | Default | Description |
|----------|---------|-------------|
| `os_ca_bundle` | `/etc/pki/tls/certs/ca-bundle.crt` | OS CA bundle used to verify GWM's publicly-signed certificate |

> `gwm_host` and `gwm_port` are derived at runtime from the `hosts` value read out of `[connect]` in `gateway.conf` — they are not configurable defaults.

### Inventory host variables

| Variable | Required | Description |
|----------|----------|-------------|
| `ansible_host` | Yes | Address Ansible uses to SSH into the node |
| `ansible_user` | Yes | SSH user |
| `ansible_ssh_private_key_file` | Yes (or equivalent auth) | SSH key path |
| `private_ip` | No | IP used for SAN validation and connectivity checks. Defaults to `ansible_default_ipv4.address` (gathered from the host). Override only if the cert SAN IP differs from the host's default interface IP. |

---

## Integration with itential.iag5 Deployer

verify_cert can run integrated into the `itential.iag5` deployer so that TLS verification happens automatically after every deployment.

### What changes in the deployer

```
itential.iag5/
├── playbooks/
│   ├── site.yml                                    ← Add verify_cert import at end
│   └── verify_cert.yml                               ← 2-play playbook
└── roles/
    ├── gateway_server/
    │   └── tasks/verify_cert.yml                     ← Orchestrator (INIT + 3 suites)
    ├── gateway_client/
    │   └── tasks/verify_cert.yml                     ← Orchestrator (INIT + 1 suite)
    └── verify_cert_common/
        ├── defaults/main.yml
        ├── tasks/
        │   ├── summary.yml
        │   ├── verify_cert_cluster_server_to_runner.yml
        │   ├── verify_cert_cluster_client_to_server.yml
        │   └── verify_cert_connect_server_to_gwm.yml
        └── templates/verify-cert-report.md.j2
```

### Run conditions

Suites are selected automatically from inventory topology — no variables required:

| Suite | Condition |
|-------|-----------|
| Cluster server ↔ runner | When `iag5_runners` group is non-empty (or the current node is a runner) |
| Cluster client ↔ server | When `iag5_clients` group is non-empty |
| Connect server → GWM | Always on server nodes (GWM is always present) |

If TLS is explicitly disabled in your inventory, the individual cert checks record themselves as `⏭ SKIPPED — TLS disabled` in the summary.

To skip verify_cert entirely:

```bash
# Skip all verify_cert
ansible-playbook itential.iag5.site -i inventories/dev/hosts --skip-tags verify_cert
```

### How deployer variables map to verify_cert variables

| verify_cert variable | Derived from deployer variable |
|--------------------|-------------------------------|
| `gateway_conf` (server/runner) | `{{ gateway_server_config_dir }}/gateway.conf` |
| `gateway_conf` (client) | `{{ gateway_client_working_dir }}/gateway.conf` |
| `runner_port` / `server_port` | `{{ gateway_server_port }}` |
| `gwm_host` / `gwm_port` | Split from `hosts` read out of `[connect]` in `gateway.conf` at runtime |
| `service_name` | `iagctl` (hardcoded — matches deployer systemd unit) |
| `private_ip` | `{{ ansible_default_ipv4.address \| default(ansible_host) }}` — gathered from the host; no inventory entry needed |

### Running verify_cert standalone against the deployer inventory

```bash
ansible-playbook itential.iag5.verify_cert -i inventories/dev/hosts
```

### Running the full deployer with verify_cert

When `verify_cert.yml` is imported at the end of `site.yml`, verify_cert runs automatically after every full deployment:

```bash
ansible-playbook itential.iag5.site -i inventories/dev/hosts
```
