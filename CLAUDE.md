# CLAUDE.md

This file provides guidance to Claude Code when working with the `itential.iag5` Ansible collection.

## What This Collection Does

`itential.iag5` deploys **Itential Automation Gateway 5 (IAG5)** — a gRPC-over-mTLS automation
platform. It provisions three component types across four supported topologies:

| Component | Ansible group | Role applied |
|-----------|--------------|--------------|
| Server | `iag5_servers` | `gateway` + `gateway_server` (mode: server) |
| Runner | `iag5_runners` | `gateway` + `gateway_server` (mode: runner) |
| Client (CLI) | `iag5_clients` | `gateway` + `gateway_client` |

**Supported topologies:**

- Single-node all-in-one
- Active/standby HA (all-in-one)
- Distributed execution with single cluster
- HA with distributed execution
- Multiple cluster

**Supported storage backends:** `local`, `etcd`, `dynamodb`, `memory`

**Target OS:** RHEL 8/9, Rocky Linux 8/9 (managed nodes). Control node requires Python ≥ 3.9
and ansible-core ≥ 2.11, < 2.17.

## Directory Structure

```text
itential.iag5/
├── galaxy.yml                     # Collection metadata and version
├── ansible.cfg                    # Ansible config (dev only — not portable)
├── requirements.yml               # Collection dependencies (ansible.posix)
├── .ansible-lint                  # Lint rules
├── .github/workflows/
│   ├── ansible-lint.yml           # CI: lint on push/PR to main
│   └── publish_ansible_collection.yml  # CI: publish to Galaxy on release
├── docs/
│   ├── reference_guide.md         # Full variable reference (100+ vars)
│   └── verify_cert_README.md      # TLS verification guide
├── example_inventories/           # Five reference inventory files
├── playbooks/
│   ├── site.yml                   # Meta playbook — imports all others in order
│   ├── servers.yml
│   ├── runners.yml
│   ├── clients.yml
│   └── verify_cert.yml
├── roles/
│   ├── gateway/                   # Common variables only (no tasks)
│   ├── gateway_client/            # IAG5 client install + configure
│   ├── gateway_server/            # IAG5 server/runner install + configure
│   └── verify_cert_common/        # Shared TLS verification task files
└── scripts/
    └── changelog.py              # Generates CHANGELOG.md from git tags
```

## Roles

### gateway

Variables-only role (no tasks). Centralizes shared defaults consumed by `gateway_client` and
`gateway_server`. Key required variables:

- `gateway_secrets_encrypt_key` — encryption key (must be set in inventory/vault)
- `gateway_pki_src_dir` — local directory containing TLS certificate files
- `repository_username` / `repository_password` — Itential Nexus credentials

### gateway\_server

Deploys server **or** runner depending on `gateway_application_mode`. Task execution order:

1. `validate-vars.yml` — asserts required vars
2. `install_gateway.yml` — creates user/dirs, downloads RPM, installs + enables systemd service
3. `install_python.yml` — optional Python 3.12 install (controlled by `gateway_server_features_python`)
4. `install_tofu.yml` — optional OpenTofu install (controlled by `gateway_server_features_opentofu`)
5. `upload_certs.yml` — uploads TLS cert/key and CA cert
6. `configure_gateway.yml` — renders `server.conf.j2` or `runner.conf.j2` to `/etc/gateway/gateway.conf`
7. `configure_firewalld.yml` — opens ports in firewalld (optional)
8. `verify_cert.yml` — live TLS handshake tests post-deployment

Handler: `restart iagctl` — restarts the `iagctl` systemd service (4 retries, 5s delay,
validates `ActiveState == "active"`).

Defaults are split by domain: `install.yml`, `server.yml`, `store.yml`, `connect.yml`,
`features.yml`, `registry.yml`, `pki.yml`, `secrets.yml`, `log.yml`, `runner.yml`,
`common.yml`, `terminal.yml`.

### gateway\_client

Deploys the IAG5 CLI client. Task execution order:

1. `validate-vars.yml`
2. `install_gateway_client.yml` — creates user/dirs, downloads + unpacks tarball
3. `upload_certs.yml` — uploads TLS material
4. `configure_gateway_client.yml` — renders `gateway.conf.j2` to `~/.gateway.d/gateway.conf`
5. `verify_cert.yml`

Defaults split by domain: `install.yml`, `server.yml`, `pki.yml`, `secrets.yml`, `log.yml`,
`terminal.yml`.

### verify\_cert\_common

Provides shared task files (not called directly) for TLS verification:

- `verify_cert_cluster_server_to_runner.yml`
- `verify_cert_cluster_client_to_server.yml`
- `verify_cert_connect_server_to_gwm.yml`
- `summary.yml` (renders a Markdown report via `verify-cert-report.md.j2`)

## Running the Collection

The collection is designed to be consumed from a separate working directory, not run directly
from the collection root.

### Install

```bash
# From Ansible Galaxy
ansible-galaxy collection install itential.iag5

# Upgrade
ansible-galaxy collection install itential.iag5 --upgrade

# From local build artifact
ansible-galaxy collection install itential-iag5-*.tar.gz
```

### Inventory Minimum Requirements

```yaml
all:
  vars:
    ansible_user: <ssh-user>
    repository_username: <nexus-user>
    repository_password: <nexus-password>
    gateway_secrets_encrypt_key: <encryption-key>
    gateway_pki_src_dir: <local-path-to-cert-files>
  children:
    iag5_servers:
      vars:
        gateway_server_connect_hosts: <gwm-ip>:8080
        gateway_server_packages:
          - <iagctl-rpm-url-or-path>
    iag5_clients:
      vars:
        gateway_client_host: <server-ip>
        gateway_client_packages:
          - <iagctl-tarball-url-or-path>
    iag5_runners: {}
```

See `example_inventories/` for complete topology-specific examples.

### Run Playbooks

```bash
# Full deployment
ansible-playbook itential.iag5.site -i inventories/production

# Component-specific
ansible-playbook itential.iag5.servers  -i inventories/production
ansible-playbook itential.iag5.runners  -i inventories/production
ansible-playbook itential.iag5.clients  -i inventories/production

# Post-deployment TLS verification only
ansible-playbook itential.iag5.verify_cert -i inventories/production
```

### Ansible Tags

Tasks are tagged for selective execution:

| Tag | Scope |
|-----|-------|
| `install` | Package download and installation |
| `configure` | Configuration file rendering |
| `upload_certs` | TLS certificate upload |
| `verify_cert` | Post-deployment TLS verification |

```bash
ansible-playbook itential.iag5.site -i inventories/production --tags configure
```

## Linting

The CI pipeline runs `ansible-lint` on every push and pull request to `main`.

To run locally:

```bash
pip install ansible-lint
ansible-lint
```

The `.ansible-lint` config warns (not errors) on:

- `yaml[line-length]` — long lines are acceptable
- `var-naming[no-role-prefix]` — `repository_*` vars intentionally lack role prefix
- `meta-runtime[unsupported-version]`
- `run-once[task]`

## CI/CD

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `ansible-lint.yml` | push/PR to `main` | Lint validation |
| `publish_ansible_collection.yml` | GitHub release or manual | Bump version, update CHANGELOG, publish to Galaxy |

The publish workflow reads the version from the git tag (`v1.0.1` → `1.0.1`), writes it into
`galaxy.yml`, runs `scripts/changelog.py`, commits, then builds and publishes the `.tar.gz`.

## Key Paths on Managed Nodes

| Component | Config file | Cert dir | Key dir |
|-----------|-------------|----------|---------|
| Server | `/etc/gateway/gateway.conf` | `/etc/gateway/ssl/` | `/etc/gateway/keys/` |
| Runner | `/etc/gateway/gateway.conf` | `/etc/gateway/ssl/` | `/etc/gateway/keys/` |
| Client | `~/.gateway.d/gateway.conf` | `~/.gateway.d/ssl/` | `~/.gateway.d/keys/` |

Systemd service: `iagctl.service`
Logs: `/var/log/gateway/`

## Network Ports

| Traffic | Port | Protocol |
|---------|------|----------|
| Client ↔ Server | 50051 | gRPC / mTLS |
| Server ↔ Runner | 50051 | gRPC / mTLS |
| Server → Gateway Manager | 8080 / 443 | HTTP / WSS |
| Server/Runner → Etcd | 2379 | gRPC |
| Server/Runner → DynamoDB | 443 | HTTPS |

## Variable Reference

The full variable reference (100+ variables with types, defaults, and descriptions) is at
`docs/reference_guide.md`. The most commonly changed variables are:

- `gateway_cluster_id` — cluster name (default: `cluster_1`)
- `gateway_pki_upload` — upload TLS certs (default: `true`)
- `gateway_server_store_type` — storage backend: `local`, `etcd`, `dynamodb`, `memory`
- `gateway_server_features_python` — install Python (default: `false`)
- `gateway_server_features_opentofu` — install OpenTofu (default: `false`)
- `gateway_application_mode` — set by playbook: `server` or `runner`

## Key Conventions

- **Same role, two modes:** `gateway_server` deploys both servers and runners; the playbook
  sets `gateway_application_mode` to branch template selection and behavior.
- **Repository authentication:** The collection supports Nexus/JFrog (basic auth) and GitLab
  (token header) via `gateway_repo_type` + credential vars.
- **Vault-friendly:** All secrets (`gateway_secrets_encrypt_key`, repo credentials, PKI paths)
  are plain inventory vars — wrap them in `ansible-vault` for production.
- **Backup on configure:** All `ansible.builtin.template` tasks set `backup: true`.
- **Idempotent restarts:** The handler validates `ActiveState == "active"` before declaring
  success; it retries up to 4 times with a 5-second delay.
