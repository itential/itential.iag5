# Day Zero Gateway Server Configuration

A starter configuration for a newly deployed IAG5 server. It registers the default Ansible
Galaxy and PyPI registries and imports a demo repository with two "hello world" services
(Ansible and Python) so you can verify the gateway is working end to end.

---

## Table of Contents

- [Configuration](#configuration)
- [Importing the Configuration](#importing-the-configuration)
  - [Prerequisites](#prerequisites)
  - [Import via Gateway Manager UI](#import-via-gateway-manager-ui)
  - [Import via Platform API](#import-via-platform-api)

---

## Configuration

```json
{
  "registries": [
    {
      "default": true,
      "description": "The default public Ansible Galaxy registry entered into the database if no other default exists",
      "name": "default-galaxy",
      "type": "ansible-galaxy",
      "url": "https://galaxy.ansible.com"
    },
    {
      "default": true,
      "description": "The default public PyPi registry entered into the database if no other default exists",
      "name": "default-pypi",
      "type": "pypi",
      "url": "https://pypi.org/simple"
    }
  ],
  "repositories": [
    {
      "description": "Get started with iagctl",
      "name": "hello-iagctl",
      "reference": "main",
      "tags": [
        "demo",
        "iagctl"
      ],
      "url": "https://github.com/itential/hello-itential.git"
    }
  ],
  "services": [
    {
      "description": "Ansible hello world with two string variables",
      "name": "hello-ansible",
      "playbooks": [
        "hello-ansible.yml"
      ],
      "repository": "hello-iagctl",
      "runtime": {},
      "tags": [
        "demo",
        "ansible"
      ],
      "type": "ansible-playbook",
      "working-directory": "hello-ansible"
    },
    {
      "description": "Python hello world with two string variables",
      "filename": "hello-python.py",
      "name": "hello-python",
      "repository": "hello-iagctl",
      "runtime": {},
      "tags": [
        "demo",
        "python"
      ],
      "type": "python-script",
      "working-directory": "hello-python"
    }
  ]
}
```

---

## Importing the Configuration

Reference: [Import Gateway Configuration](https://docs.itential.com/itential-gateway/gateway-manager/import-gateway-configuration)

### Prerequisites

- The target gateway cluster must be connected, enabled, and not read-only.
- API imports require the `gateway:update` role.

### Import via Gateway Manager UI

1. Open the cluster list in Gateway Manager.
2. Locate the target cluster and select the overflow menu (**...**).
3. Choose **Import Configuration**.
4. Upload `iag5-initial-config.json`, or enter its path.
5. Click **Import** to apply the settings.

The UI accepts both JSON and YAML. By default, existing resources are not overwritten; enable
**Force** to replace them.

### Import via Platform API

Call:

```
POST /v1/gateways/:clusterId/configuration/import
```

Supply the configuration as inline JSON content in the request body, or reference a Git
repository (URL, file path, branch, and credentials).

Optional flags:

| Flag | Purpose |
|------|---------|
| `force` | Overwrite conflicting resources |
| `validate` | Check the configuration without applying it |
| `check` | Preview the changes that would be made |
