# certcheck — IAG5 TLS Certificate Verification

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
| Server ↔ Runner | gRPC over TCP | Mutual TLS (mTLS) | Both `serverAuth` + `clientAuth` in EKU | `gateway_server_use_tls: true` |
| Client ↔ Server | gRPC over TCP | Mutual TLS (mTLS) | Both `serverAuth` + `clientAuth` in EKU | `gateway_client_use_tls: true` |
| Server → Gateway Manager | WebSocket (wss://) | One-way TLS | `clientAuth` in EKU; GWM cert publicly trusted | `gateway_server_use_tls: true` |

certcheck covers all three paths. For each path it runs on both sides of the connection independently, so a misconfiguration on either end is caught.

---

## Architecture

certcheck is structured as three Ansible roles, one per connection path:

```
certcheck/
├── site.yml                              Main playbook — runs all three roles
├── inventory.yml                         Standalone inventory (not used with deployer)
├── vars/
│   ├── common.yml                        Shared variables (conf paths, service name)
│   ├── cluster_server_to_runner.yml      Port and IP vars for server↔runner checks
│   ├── cluster_client_to_server.yml      Port and IP vars for client↔server checks
│   └── connect_server_to_gwm.yml         GWM host/port and OS CA bundle path
└── roles/
    ├── cluster_server_to_runner/         27 checks — server and runner nodes (runs when gateway_server_use_tls: true)
    ├── cluster_client_to_server/         26 checks — client and server nodes (runs when gateway_client_use_tls: true)
    ├── connect_server_to_gwm/            19 checks — server node only (runs when gateway_server_use_tls: true)
    └── common/
        └── tasks/summary.yml             Shared summary printer
```

Each role runs on two host groups in separate plays so that each node produces its own independent summary. This matters because a problem on the runner side is not the same as a problem on the server side, and they need to be diagnosed separately.

### How node identity is determined

The roles do not rely on separate play-level inventory groups to determine what config section to read. Each role determines its own identity at runtime:

```yaml
# cluster_server_to_runner
node_section: "{{ 'server' if inventory_hostname in groups['server'] else 'runner' }}"

# cluster_client_to_server  
node_section: "{{ 'client' if inventory_hostname in groups['client'] else 'server' }}"
```

This means the same role file runs on both sides of a connection — the `when:` conditions on individual tasks control what runs where.

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
certcheck/
├── site.yml
├── inventory.yml
├── vars/
│   ├── common.yml
│   ├── cluster_server_to_runner.yml
│   ├── cluster_client_to_server.yml
│   └── connect_server_to_gwm.yml
└── roles/
    ├── cluster_server_to_runner/
    │   └── tasks/main.yml
    ├── cluster_client_to_server/
    │   └── tasks/main.yml
    ├── connect_server_to_gwm/
    │   └── tasks/main.yml
    └── common/
        └── tasks/summary.yml
```

---

## Inventory

The standalone inventory (`inventory.yml`) defines four host groups:

```yaml
all:
  children:
    client:
      hosts:
        gateway_client:
          ansible_host: <client-ip>
          private_ip: <client-private-ip>
          ansible_user: ec2-user
          ansible_ssh_private_key_file: ~/.ssh/your-key.pem

    server:
      hosts:
        gateway_server:
          ansible_host: <server-ip>
          private_ip: <server-private-ip>
          ansible_user: ec2-user
          ansible_ssh_private_key_file: ~/.ssh/your-key.pem

    runner:
      hosts:
        gateway_runner:
          ansible_host: <runner-ip>
          private_ip: <runner-private-ip>
          ansible_user: ec2-user
          ansible_ssh_private_key_file: ~/.ssh/your-key.pem

    gateway_manager:
      hosts:
        gwm:
          ansible_host: <gwm-ip>
          private_ip: <gwm-private-ip>
          ansible_user: rocky
          ansible_ssh_private_key_file: ~/.ssh/your-key.pem
```

### `private_ip` vs `ansible_host`

`ansible_host` is the address Ansible uses to SSH into a node. `private_ip` is the IP that the node advertises to other IAG5 nodes for gRPC connections, and is what must appear in the certificate's Subject Alternative Name.

In most deployments these are the same. If they differ — for example when using a bastion host — set `private_ip` explicitly per host. certcheck uses `private_ip` for:

- SAN validation (CHECK 8a/8b, CHECK 17b, CHECK 12c)
- `no_proxy` validation (CHECK 23, CHECK 24)
- Live connection targets (CHECK 25, CHECK 26, CHECK 27)

---

## Usage

### Run all checks

```bash
ansible-playbook site.yml -i inventory.yml
```

### Run a specific connection path only

```bash
# Server ↔ Runner mTLS checks
ansible-playbook site.yml -i inventory.yml --tags cluster_server_to_runner

# Client ↔ Server mTLS checks
ansible-playbook site.yml -i inventory.yml --tags cluster_client_to_server

# Server → Gateway Manager WebSocket TLS checks
ansible-playbook site.yml -i inventory.yml --tags connect_server_to_gwm
```

### Run on a single node

```bash
ansible-playbook site.yml -i inventory.yml --limit gateway_runner
```

### Increase verbosity to see raw openssl output

```bash
ansible-playbook site.yml -i inventory.yml -v
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
| CHECK 3 | CA bundle contains exactly 2 certs (intermediate + root) | Both | Yes |
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
| CHECK 3 | CA bundle contains exactly 2 certs (intermediate + root) | Both | Yes |
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
| CHECK 2 | `cluster_id` set and not the default value `cluster_1` | Yes |
| CHECK 3 | `[connect] hosts` set (GWM IP:port) | Yes |
| CHECK 4 | `certificate_file` set in `[connect]` section | Yes |
| CHECK 5 | Certificate file exists on disk | Yes |
| CHECK 6 | `private_key_file` set in `[connect]` section | Yes |
| CHECK 7 | Private key file exists on disk | Yes |
| CHECK 8 | Cert and key are a matched pair | Yes |
| CHECK 9 | Certificate is not expired | Yes |
| CHECK 10 | Certificate has more than 30 days remaining | Warn if < 30 days |
| CHECK 11 | Cert type identified (self-signed leaf is valid for connect) | Info |
| CHECK 12 | EKU contains `clientAuth` (required for GWM app-layer auth) | Warn if missing |
| CHECK 12b | Subject Alternative Name extension present | Warn |
| CHECK 12c | Cert SAN contains server `private_ip` as `IP:` entry | Warn |
| CHECK 13 | `no_proxy`/`NO_PROXY` set in systemd service | Warn |
| CHECK 14 | GWM host present in `no_proxy` | Warn |
| CHECK 15 | GWM hostname resolves from server | Yes |
| CHECK 16 | TCP connectivity from server to GWM | Yes |
| CHECK 17 | GWM server cert trusted by OS CA pool (`openssl s_client` against OS bundle) | Yes |
| CHECK 18 | WebSocket handshake to GWM returns HTTP 101 | Warn |
| CHECK 19 | `iagctl` service running; GATEWAY_CONNECT env vars visible in process | Warn |

#### Why CHECK 2 (`cluster_id`) matters

The default `cluster_id` value is `cluster_1`. If multiple IAG5 deployments connect to the same Gateway Manager with the default cluster ID, they collide and only one cluster's services are visible to GWM. This is a configuration error that does not produce an obvious error message, which is why certcheck catches it explicitly.

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
| `gwm_host` | Derived from `groups['gateway_manager'][0]['ansible_host']` | Gateway Manager hostname or IP |
| `gwm_port` | `8080` | Gateway Manager WebSocket port |
| `os_ca_bundle` | `/etc/pki/tls/certs/ca-bundle.crt` | OS CA bundle used to verify GWM's publicly-signed certificate |

### Inventory host variables

| Variable | Required | Description |
|----------|----------|-------------|
| `ansible_host` | Yes | Address Ansible uses to SSH into the node |
| `private_ip` | Yes | IP address the node advertises to other IAG5 nodes; must appear in the cert's SAN |
| `ansible_user` | Yes | SSH user |
| `ansible_ssh_private_key_file` | Yes (or equivalent auth) | SSH key path |

---

## Integration with itential.iag5 Deployer

certcheck can run integrated into the `itential.iag5` deployer so that TLS verification happens automatically after every deployment.

### What changes in the deployer

```
itential.iag5/
├── playbooks/
│   ├── site.yml                                    ← Add certcheck import at end
│   └── certcheck.yml                               ← New playbook
└── roles/
    ├── certcheck_cluster_server_to_runner/         ← Runs when gateway_server_use_tls: true
    │   ├── defaults/main.yml
    │   └── tasks/main.yml
    ├── certcheck_cluster_client_to_server/         ← Runs when gateway_client_use_tls: true
    │   ├── defaults/main.yml
    │   └── tasks/main.yml
    ├── certcheck_connect_server_to_gwm/            ← Runs when gateway_server_use_tls: true
    │   ├── defaults/main.yml
    │   └── tasks/main.yml
    └── certcheck_common/
        └── tasks/summary.yml
```

> **Note:** `gateway_server_use_tls` and `gateway_client_use_tls` both default to `true` in the deployer. certcheck roles are skipped automatically when TLS is disabled — no inventory changes are needed to control this.

### Run conditions

Each certcheck role is gated on the deployer's TLS enable variables:

| Role | Deployer variable | Default |
|------|------------------|---------|
| `certcheck_cluster_server_to_runner` | `gateway_server_use_tls` | `true` |
| `certcheck_cluster_client_to_server` | `gateway_client_use_tls` | `true` |
| `certcheck_connect_server_to_gwm` | `gateway_server_use_tls` | `true` |

Because both variables default to `true` in the deployer, certcheck runs by default on every deployment that includes the relevant node types. If TLS is explicitly disabled in your inventory, the corresponding certcheck role skips all cert-specific checks and records them as `⏭ SKIPPED — TLS disabled` in the summary.

To disable certcheck for a specific connection path without disabling TLS, use tags:

```bash
# Skip server↔runner checks only
ansible-playbook itential.iag5.site -i inventories/dev/hosts --skip-tags cluster_server_to_runner

# Skip all certcheck entirely
ansible-playbook itential.iag5.site -i inventories/dev/hosts --skip-tags certcheck
```

### Deployer group name mapping

| Standalone certcheck group | Deployer group |
|---------------------------|----------------|
| `server` | `iag5_servers` |
| `runner` | `iag5_runners` |
| `client` | `iag5_clients` |
| `gateway_manager` | `gateway_manager` (add to inventory if using connect checks) |

### How deployer variables map to certcheck variables

| certcheck variable | Derived from deployer variable |
|--------------------|-------------------------------|
| `server_gateway_conf` | `{{ gateway_server_config_dir }}/gateway.conf` |
| `client_gateway_conf` | `{{ gateway_client_working_dir }}/gateway.conf` |
| `runner_port` / `server_port` | `{{ gateway_server_port }}` |
| `gwm_host` / `gwm_port` | Split from `{{ gateway_server_connect_hosts }}` |
| `service_name` | `iagctl` (hardcoded — matches deployer systemd unit) |
| `private_ip` | `{{ ansible_host }}` (deployer does not define `private_ip` separately) |

### Running certcheck standalone against the deployer inventory

```bash
ansible-playbook certcheck.yml -i inventories/dev/hosts
```

### Running a specific check suite

```bash
ansible-playbook certcheck.yml -i inventories/dev/hosts --tags cluster_server_to_runner
ansible-playbook certcheck.yml -i inventories/dev/hosts --tags cluster_client_to_server
ansible-playbook certcheck.yml -i inventories/dev/hosts --tags connect_server_to_gwm
```

### Running the full deployer with certcheck

When `certcheck.yml` is imported at the end of `site.yml`, certcheck runs automatically after every full deployment:

```bash
ansible-playbook itential.iag5.site -i inventories/dev/hosts
```
