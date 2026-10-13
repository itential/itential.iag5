# Installing Itential Gateway 5 in an Air-Gapped Environment

## Overview

The IAG5 collection can install Itential Gateway 5 servers, runners and clients on hosts that
have no internet access. The collection contains a playbook that downloads every required
package from a non air-gapped host to the Ansible control node. Those packages are then copied
to the control node in the air-gapped environment, and the install playbooks are run in offline
mode.

| Definitions  | Description |
| :----------- | :---------- |
| Control Node | The Ansible server. This is where the collection and the inventory files are located. |
| Target Node  | The server where Itential Gateway 5 is installed. Also referred to as a managed node. |

## Packages Downloaded

| Component | Package | Condition |
| :-------- | :------ | :-------- |
| Server / Runner | `iagctl` RPM from `gateway_server_packages` | always |
| Server / Runner | Python RPMs from `gateway_server_python_packages` | `gateway_server_features_python_enabled` is true |
| Server / Runner | OpenTofu RPMs from `gateway_server_opentofu_packages` | `gateway_server_features_opentofu_enabled` is true |
| Client | `iagctl` tarball from `gateway_client_packages` | always |

Only entries in `gateway_server_packages` and `gateway_client_packages` that are `https://` URLs
are downloaded. Entries that are local paths are skipped.

## Running the Download Playbook

The download playbook must be run against a server that has internet access. It is critical to
use a server with the same OS image as the target servers in the air-gapped environment,
otherwise the downloaded RPMs will not match and the installation will most likely fail. The
server should not already have the Python or OpenTofu packages installed, unless
`gateway_offline_download_method` is set to `yumdownloader` or `repotrack`.

The packages are first downloaded to the target node and then copied to the control node.

The inventory must define the following variables:

- `offline_control_node_root` - an existing directory on the control node. The packages are
  copied here by the download playbook and installed from here in offline mode. There is no
  default, and the playbooks fail if it is not set or is not a directory on the control node.
- `gateway_offline_release` (for example `5.5.3`) - used to name the package directories, so that
  packages for different releases do not mix.

```yaml
all:
  vars:
    offline_control_node_root: /opt/itential/offline
    gateway_offline_release: 5.5.3
```

```bash
ansible-playbook itential.iag5.download_packages -i <inventory>
```

The download playbook forces `offline_install_enabled` to `false`, so `offline_install_enabled`
can be set to `true` in the inventory without changing it between runs.

### Directory Structure

By default the packages are placed in `/var/tmp/itential_packages` on the target node and in
`itential_packages` under `offline_control_node_root` on the control node.

```bash
<offline_control_node_root>/itential_packages
└── rocky_9
    └── 5.5.3
        └── gateway
            ├── archives
            └── rpms
                ├── gateway
                ├── opentofu
                └── python
```

## Running the Install Playbooks in Offline Mode

### Copy the Packages to the Air-Gapped Environment

After the download playbook completes, archive the entire
`<offline_control_node_root>/itential_packages` directory, copy it to the control node in the
air-gapped environment, and unarchive it under that environment's `offline_control_node_root`.
The directory must exist before the install playbooks are run.

### Define the Inventory

Set `offline_install_enabled` to `true` in the inventory, or pass it with `--extra-vars`.

```yaml
all:
  vars:
    offline_install_enabled: true
    offline_control_node_root: /opt/itential/offline
    gateway_offline_release: 5.5.3
```

### Run the Playbooks

```bash
ansible-playbook itential.iag5.site -i <inventory>
```

or

```bash
ansible-playbook itential.iag5.site -i <inventory> --extra-vars "offline_install_enabled=true"
```

In offline mode the install playbooks:

- validate that `offline_control_node_root` is a directory and that the packages exist on the
  control node before changing anything
- copy the packages to a temporary directory on each target node
- install the RPMs with all YUM/DNF repositories disabled, then delete the temporary directory
- skip adding the OpenTofu YUM repository
- skip the public repository connectivity checks in the `verify` playbook

The `iagctl` RPM and the Python and OpenTofu RPMs must therefore include all of their
dependencies.

## Variable Reference

All variables below work out of the box and rarely need to be overridden.

| Variable | Type | Description | Default |
| :------- | :--- | :---------- | :------ |
| `offline_install_enabled` | Boolean | Install from the packages on the control node. | `false` |
| `offline_target_node_root` | String | Root directory on the target node where the download playbook downloads packages. | `/var/tmp` |
| `offline_control_node_root` | String | Root directory on the control node where packages are downloaded to and installed from. Must be an existing directory. | N/A (must be defined in inventory) |
| `offline_itential_packages_path` | String | Path appended to the root directories. | `itential_packages/{{ ansible_distribution \| lower }}_{{ ansible_distribution_major_version }}` |
| `gateway_offline_release` | String | The Gateway release the packages are for. | N/A (must be defined in inventory) |
| `gateway_offline_download_method` | String | How the Python and OpenTofu RPMs are downloaded: `yum_module`, `yum_install`, `yum_reinstall`, `repotrack` or `yumdownloader`. | `yum_module` |
| `gateway_offline_packages_root` | String | Gateway packages root directory. | `{{ offline_itential_packages_path }}/{{ gateway_offline_release }}/gateway` |
| `gateway_offline_target_node_root` | String | Gateway target node root directory. | `{{ offline_target_node_root }}/{{ gateway_offline_packages_root }}` |
| `gateway_offline_control_node_root` | String | Gateway control node root directory. | `{{ offline_control_node_root }}/{{ gateway_offline_packages_root }}` |
| `gateway_offline_target_node_rpms_dir` | String | Target node RPMs directory. | `{{ gateway_offline_target_node_root }}/rpms` |
| `gateway_offline_target_node_archives_dir` | String | Target node archives directory. | `{{ gateway_offline_target_node_root }}/archives` |
| `gateway_offline_control_node_rpms_dir` | String | Control node RPMs directory. | `{{ gateway_offline_control_node_root }}/rpms` |
| `gateway_offline_control_node_archives_dir` | String | Control node archives directory. | `{{ gateway_offline_control_node_root }}/archives` |

## Limitations

- Python packages that Gateway users install at runtime (for example with `pip` in a service
  virtual environment) and Ansible collections used by Gateway services are not downloaded.
  Those must be provided through an internal mirror.
- TLS certificates are uploaded from the control node and are not affected by offline mode.
