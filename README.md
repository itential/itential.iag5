# Ansible Collection - itential.iag5

## Table of contents

1. [Overview](#overview)
2. [Supported Architectures](#supported-architectures)
3. [Collection Prerequisites](#collection-prerequisites)
    1. [Required Python, Ansible, and Ansible modules](#required-python-ansible-and-ansible-modules)
    2. [Required Public Repositories](#required-public-repositories)
    3. [Ports and Networking](#ports-and-networking)
    4. [TLS Certificates](#tls-certificates)
    6. [Obtaining the Itential Binaries](#obtaining-the-itential-artifacts)
4. [Installing and Upgrading the IAG5 Ansible Collection](#installing-and-upgrading-the-iag5-ansible-collection)
    1. [Online Installation](#online-installation)
    2. [Offline Installation](#offline-installation)
5. [Running the Playbooks](#running-the-playbooks)
    1. [Confirm Requirements](#confirm-requirements)
    2. [Determine the Working and IAG5 Collection Directories](#determine-the-working-and-iag5-collection-directories)
    3. [Create the Inventories Directory](#create-the-inventories-directory)
    4. [Download Installation Artifacts](#download-installation-artifacts)
    5. [Copy Installation Artifacts into the Files Directory](#copy-installation-artifacts-into-the-files-directory)
    6. [Create a Symlink to the Files Directory](#create-a-symlink-to-the-files-directory)
    7. [Create the Inventory File](#create-the-inventory-file)
    8. [Run the IAG5 Site Playbook](#run-the-iag5-site-playbook)
    9. [Confirm Successful Installation](#confirm-successful-installation)
    10. [Running the IAG5 Component Playbooks](#running-the-iag5-component-playbooks)
        1. [Clients Playbook](#clients-playbook)
        2. [Servers Playbook](#servers-playbook)
        3. [Runners Playbook](#runners-playbook)
6. [Sample Inventories](#sample-inventories)
    1. [All-in-one Single Node Inventory](#all-in-one-single-node-inventory)
    2. [All-in-one Active/Standby High Availability Inventory](#all-in-one-activestandby-high-availability-inventory)
    3. [Distributed Service Execution with Single Cluster Inventory](#distributed-service-execution-with-single-cluster-inventory)
    4. [High Availability with Distributed Execution Inventory](#high-availability-with-distributed-execution-inventory)
    5. [Multiple Cluster Architecture Inventories](#multiple-cluster-architecture-inventories)
7. [Reference Guide](#reference-guide)
8. [Patching IAG5](#patching-iag5)

## Overview

An IAG5 environment is composed of several applications working in conjunction with one another.

- IAG5
  - Client
  - Server
  - Runners
- Etcd
- DynamoDB

The Itential IAG5 collection can deploy all supported Itential IAG5 architectures. It will only
install and configure the IAG5 components listed above; it does not handle installing/configuring
Etcd or DynamoDB.

## Supported Architectures

- [All-in-one Single Node](https://docs.itential.com/docs/architecture-deployment-models#1-allinone-singlenode-deployment)
- [All-in-one Active/Standby High Availability](https://docs.itential.com/docs/architecture-deployment-models#2-allinone-activestandby-high-availability-deployment)
- [Distributed Service Execution with Single Cluster](https://docs.itential.com/docs/architecture-deployment-models#3-distributed-service-execution-with-single-cluster)
- [High Availability with Distributed Execution](https://docs.itential.com/docs/architecture-deployment-models#4-high-availability-with-distributed-execution)
- [Multiple Cluster Architecture](https://docs.itential.com/docs/architecture-deployment-models#5-multiple-cluster-architecture)

## Collection Prerequisites

The Itential IAG5 collection is an Ansible collection and as such requires running on a control
node. That node has its own set of dependencies.

### Control Node Server Specifications

Itential recommends using a dedicated node running the requirements listed below as the Ansible
control node. That node should meet or exceed the following specifications:

| Component | Value                |
|-----------|----------------------|
| OS        | RHEL8/9 or Rocky 8/9 |
| RAM       | 4 GB                 |
| CPUs      | 2                    |
| Disk      | 20 GB                |

### Required Python, Ansible, and Ansible modules

The **Ansible Control Node** must have the following installed:

- **Python**
  - python >= 3.9

- **Ansible**
  - ansible-core >= 2.11, < 2.17
  - ansible: >=9.x.x

To see which Ansible version is currently installed, execute the `ansible --version` command as
shown below.

#### Example: Confirming Ansible Version

  ```bash
  ansible [core 2.15.13]
    config file = None
    configured module search path = ['/home/<USER>/.ansible/plugins/modules', '/usr/share/ansible/plugins/modules']
    ansible python module location = /home/<USER>/.local/lib/python3.9/site-packages/ansible
    ansible collection location = /home/<USER>/.ansible/collections:/usr/share/ansible/collections
    executable location = /home/<USER>/.local/bin/ansible
    python version = 3.9.21 (main, Jun 27 2025, 00:00:00) [GCC 11.5.0 20240719 (Red Hat 11.5.0-5)] (/usr/bin/python3)
    jinja version = 3.1.6
    libyaml = True
  ```

- **Ansible Modules**: The following ansible modules are required on the control node for the
IAG5 collection to run.
  - 'ansible.posix': '>=0.0.1'

**&#9432; Note:**
The Itential IAG5 project is an Ansible collection. As such, a familiarity with basic Ansible
concepts is suggested before proceeding.

### Required Public Repositories

On the Ansible control node, the Ansible Python module and the IAG5 collection
will need to be installed.

On the target servers, the IAG5 collection will install RPM packages using the standard YUM
repositories. When packages are not available for the distribution, the IAG collection will either
install the required repository or download the packages.

| Component | Location | Protocol | Notes |
| :-------- | :------- | :------- | :---- |
| Ansible Control Node | <https://pypi.org> | TCP | |
| Ansible Control Node | <https://galaxy.ansible.com> | TCP | |
| IAG5 | <https://galaxy.ansible.com> | TCP | |
| IAG5 | <https://registry.aws.itential.com> | TCP | |

> [! WARNING]
> Neither the IAG5 collection nor the maintainers of the project can not know if any of the above
> URLs will result in a redirect. If a customer is using a proxy or other such method to restrict
> access this list may not represent the final URLs that are used.

### Ports and Networking

In a clustered environment where components are installed on more than one host, the following
network traffic flows need to be allowed.

| Source | Destination | Port | Protocol | Description |
| ------ | ----------- | ---- | -------- | ----------- |
| IAG5 | Itential Gateway Manager | 8080 | TCP | IAG5 connection to Itential Gateway Manager (on-prem) |
| IAG5 | Itential Gateway Manager | 443 | TCP | IAG5 connection to Itential Gateway Manager (cloud) |
| IAG5 Client | IAG5 Server | 50051 | TCP | IAG5 Client connection to IAG5 Server |
| IAG5 Server | IAG5 Runner | 50051 | TCP | IAG5 Server connection to IAG5 Runner |
| IAG5 Server/Runner | DynamoDB | 443 | TCP | IAG5 Server/Runner connection to DynamoDB |
| IAG5 Server/Runner | Etcd | 2379 | TCP | IAG5 Server/Runner connection to Etcd |

Notes

- Not all ports will need to be open for every supported architecture
- Secure ports are only required when explicitly configured in the inventory

### TLS Certificates

The IAG5 collection is not responsible for creating any TLS certificates that may be used to
further tighten security in the Itential ecosystem. However, if these certificates are provided it
can upload and configure the platform to use them. The table below describes the certificates that
can be used and what their purpose is.

| Certificate | Description |
| :-----------| :-----------|
| Gateway Manager | Enables secure communication with the Itential Gateway Manager. |
| IAG5 Client |  |
| IAG5 Server |  |
| IAG5 Runner |  |

### Passwords

The IAG5 collection will create several user accounts in the dependent systems. It uses default
passwords in all cases and those passwords can be overridden with the defined ansible variables.
To override these variables just define the variable in the IAG5 inventory.

### Obtaining the Itential Artifacts

The IAG5 artifacts are hosted on the Itential Nexus repository. An account is required to access
Itential Nexus. If you do not have an account, contact your Itential Sales representative.

## Installing and Upgrading the IAG5 Ansible Collection

### Online Installation

The Itential IAG5 collection can be installed via the `ansible-galaxy` utility.

On your control node, execute the following command to install the collection:

```bash
ansible-galaxy collection install itential.iag5
```

This should also install the required Ansible dependencies. When a new version of the IAG5
collection is available, you can upgrade using the following command:

```bash
ansible-galaxy collection install itential.iag5 --upgrade
```

### Offline Installation

If your control node does not have internet connectivity, the IAG5 collection and its
dependencies can be downloaded via another system, copied to your control node, and installed
manually.

**&#9432; Note:**
Some of the following collections may already be installed on your control node. To verify, use the
`ansible-galaxy collection list` command.

1. Download the following collections from the provided links:

TODO
    - [Itential IAG5](https://galaxy.ansible.com/ui/repo/published/itential/iag5/)

2. Copy the downloaded collections to your control node.
3. Install the collections using the following command:

    ```bash
    ansible-galaxy collection install <COLLECTION>.tar.gz
    ```

## Running the Playbooks

Once you have have installed the IAG5 collection, run it to begin deploying IAG5 to your
environment. This section details a basic deployment using required variables only.

### Confirm Requirements

Before running the IAG5 collection we must ensure the following:

- **Compatible OS**: Any managed nodes to be configured by the IAG5 collection must use an
operating system that is compatible with the target version of IAG5. For more information, refer
to the [IAG5 Dependencies](TODO) page.
- **Hostnames**: Any hostnames used by managed nodes must be DNS-resolvable.
- **Administrative Privileges**: The `ansible_user` must have administrative privileges on managed
nodes.
- **SSH Access**: The control node must have SSH connectivity to all managed nodes.

**&#9432; Note:**
Although the IAG5 collection can be used to configure nodes that use any supported operating
system, it is optimized for Rocky/RHEL 8/9.

### Determine the Working and IAG5 Collection Directories

The IAG5 collection will be installed into the user's collection directory. Because the IAG5
collection will be overwritten when it is upgraded, users should not store any inventory files,
binaries or artifacts in the IAG5 collection directory. Instead, users should create a working
directory to store those files.

The working directory can be any directory on the control node and will be referred to as the
`WORKING-DIR` in this guide.

Determine what directory the IAG5 collection is installed to by using the `ansible-galaxy
collection list` command. In the following example, the IAG5 collection directory is
`/home/<USER>/.ansible/collections/ansible_collections/itential/iag5`.

#### Example: Determining the IAG5 Collection Directory

```bash
% ansible-galaxy collection list

# //home/<USER>/.ansible/collections/ansible_collections
Collection        Version
----------------- -------
itential.iag5     1.0.0
```

The IAG5 collection directory will be referred to as the `IAG5-DIR` in this guide.

### Create the Inventories Directory

The `inventories` directory should be a sub-directory of the working directory. It will contain
the hosts files.

```bash
cd <WORKING-DIR>
mkdir inventories
```

### Determine Installation Method

Choose one of the following installation methods based on your requirements:

1. **Manual Upload**: Manually download the required files onto the control node in a `files`
directory. The IAG5 collection will move these artifact files to the target nodes.
2. **Repository Download**: Provide a repository download URL with either a username/password or an
API key. The IAG5 collection will make an API request to download the files directly onto the
target nodes.

### Manual Upload

#### Create the Files Directory

The `files` directory should be a sub-directory of the working directory. It will contain the
Itential binaries and artifacts.

```bash
cd <WORKING-DIR>
mkdir files
```

#### Download Installation Artifacts

Download the IAG5 RPMs/tarballs from the [Itential Nexus Repository](TODO) to local storage.

**&#9432; Note:**
If you are unsure which files should be downloaded for your environment, contact your Itential
Professional Services representative.

#### Copy Installation Artifacts into the Files Directory

Next, copy the files downloaded in the previous step to the `files` subdirectory.

#### Example: Copying to the Files Directory

```bash
cd <WORKING-DIR>/files
cp ~/Downloads/iagctl*.rpm .
```

#### Create a Symlink to the Files Directory

Navigate to the playbooks directory in the IAG5 directory and create a symlink to the files
directory in the working directory.

```bash
cd <IAG5-DIR>/playbooks
ln -s <WORKING-DIR>/files .
```

### Repository Download

#### Obtain the Download URL

You can obtain the download URL from either a **Sonatype Nexus Repository** or **JFrog**. Follow
the steps below based on the repository type:

- **For Sonatype Nexus**: Navigate to the file you wish to use and locate the **Path** parameter.
Copy the link provided in the **Path** field to obtain the download URL.
- **For JFrog**: Locate the file in the JFrog repository and copy the File URL.

This download method supports both the IAG5 RPM and tarball files.

#### Configure Repository Credentials

Depending on the repository you are using, you will need to provide the appropriate credentials:

- **For Nexus**: Set the `repository_username` and `repository_password` variables.
- **For JFrog**: Set the `repository_api_key` variable.

**&#9432; Note:**
To secure sensitive information like passwords or API keys, consider using Ansible Vault to encrypt
these variables.

### Create the Inventory File

Using a text editor, create an inventory file that defines your deployment environment. To do this,
assign your managed nodes to the relevant groups according to what components you would like to
install on them. In the following example:

- All required variables have been defined.

**&#9432; Note:**
Itential recommends that all inventories follow the best practices outlined in the
[Ansible documentation](https://docs.ansible.com/ansible/latest/getting_started/get_started_inventory.html).

#### Example: Creating the Inventory File

```bash
cd <WORKING-DIR>
mkdir -p inventories/dev
vi inventories/dev/hosts
```

</br>

#### Example: Inventory File (YAML Format)

```yaml
all:
  vars:
    ansible_user: <ANSIBLE-USER>

    # Nexus
    repository_username: <NEXUS-USERNAME>
    repository_password: <NEXUS-PASSWORD>

  children:
    gateway_all:
      children:
        iag5_servers:
        iag5_clients:
      vars:
        gateway_pki_src_dir: <PKI-DIR>

    gateway_servers:
      children:
        iag5_servers:
      vars:
        gateway_server_packages:
          - <IAGCTL-RPM>
        gateway_server_secrets_encrypt_key: <ENCRYPT-KEY>

    iag5_servers:
      hosts:
        <IAG5-SERVER-HOSTNAME>:
          ansible_host: <IAG5-SERVER-IP>
      vars:
        gateway_server_connect_hosts: <GATEWAY-MANAGER-IP>:8080

    iag5_clients:
      hosts:
        <IAG5-CLIENT-HOSTNAME>:
          ansible_host: <IAG5-CLIENT-IP>
      vars:
        gateway_client_host: <IAG5-SERVER-IP>
        gateway_client_packages:
          - <IAGCTL-TARBALL>
```

### Run the IAG5 Site Playbook

Navigate to the working directory and execute the following run command.

#### Example: Running the IAG5 Site Playbook

```bash
cd <WORKING-DIR>
ansible-playbook itential.iag5.site -i inventories/dev
```

### Confirm Successful Installation

After the IAG5 playbook is finished running, perform the following checks on each component to
confirm successful installation.

#### Example Output: IAG5 System Status

```bash
$ sudo systemctl status iagctl
```

### Running the IAG5 Component Playbooks

In addition to the site playbook, there are playbooks for running the individual components.

#### Clients Playbook

```bash
cd <WORKING-DIR>
ansible-playbook itential.iag5.clients -i inventories/dev
```

#### Servers Playbook

```bash
cd <WORKING-DIR>
ansible-playbook itential.iag5.servers -i inventories/dev
```

#### Runners Playbook

```bash
cd <WORKING-DIR>
ansible-playbook itential.iag5.runners -i inventories/dev
```

## Sample Inventories

Below are simplified sample host files that describe the basic configurations to produce the
supported architectures. These are intended to be starting points only.

### All-in-one Single Node Inventory

```yaml
# Note:
#  - All example inventory_hostname entries must be replaced with the actual server hostnames.
#  - All hostnames must be resolvable.
all:
  vars:
    ansible_user: <ANSIBLE-USER>

    # Itential Nexus repository credentials
    repository_username: <NEXUS-USERNAME>
    repository_password: <NEXUS-PASSWORD>

    gateway_secrets_encrypt_key: <ENCRYPT-KEY>
    gateway_pki_src_dir: <PKI-DIR>

  children:
    iag5_servers:
      hosts:
        example-server:
          ansible_host: <SERVER-IP>
      vars:
        gateway_server_connect_hosts: <GATEWAY-MANAGER-IP>:8080
        gateway_server_packages:
          - <IAGCTL-RPM>

    iag5_clients:
      hosts:
        example-client:
          ansible_host: <CLIENT-IP>
          gateway_client_host: <SERVER-IP>
      vars:
        gateway_client_packages:
          - <IAGCTL-TARBALL>
```

### All-in-one Active/Standby High Availability Inventory

```yaml
# Notes:
#  - All example inventory_hostname entries must be replaced with the actual server hostnames.
#  - All hostnames must be resolvable.
#  - Backend 'dynamodb' is also supported; see Reference Guide for details.
all:
  vars:
    ansible_user: <ANSIBLE-USER>

    # Itential Nexus repository credentials
    repository_username: <NEXUS-USERNAME>
    repository_password: <NEXUS-PASSWORD>

    gateway_secrets_encrypt_key: <ENCRYPT-KEY>
    gateway_pki_src_dir: <PKI-DIR>

  children:
    iag5_servers:
      hosts:
        example-active-server:
          ansible_host: <ACTIVE-SERVER-IP>
        example-standby-server:
          ansible_host: <STANDBY-SERVER-IP>
      vars:
        gateway_server_packages:
          - <IAGCTL-RPM>
        gateway_server_store_backend: etcd
        gateway_server_store_etcd_hosts: <ETCD-SERVER1-IP>:2379 <ETCD-SERVER2-IP>:2379 <ETCD-SERVER3-IP>:2379

    iag5_clients:
      hosts:
        example-client:
          ansible_host: <CLIENT-IP>
          gateway_client_host: <ACTIVE-SERVER-IP>
      vars:
        gateway_client_packages:
          - <IAGCTL-TARBALL>

```

### Distributed Service Execution with Single Cluster Inventory

```yaml
# Note:
#  - All example inventory_hostname entries must be replaced with the actual server hostnames.
#  - All hostnames must be resolvable.
#  - Backend 'dynamodb' is also supported; see Reference Guide for details.
all:
  vars:
    ansible_user: <ANSIBLE-USER>

    # Itential Nexus repository credentials
    repository_username: <NEXUS-USERNAME>
    repository_password: <NEXUS-PASSWORD>

    gateway_secrets_encrypt_key: <ENCRYPT-KEY>
    gateway_pki_src_dir: <PKI-DIR>

  children:
    iag5_servers:
      hosts:
        example-server:
          ansible_host: <SERVER-IP>

    iag5_runners:
      hosts:
        example-runner1:
          ansible_host: <RUNNER1-IP>
        example-runner2:
          ansible_host: <RUNNER2-IP>
        example-runner3:
          ansible_host: <RUNNER3-IP>
      vars:
        gateway_server_connect_hosts: <GATEWAY-MANAGER-IP>:8080
        gateway_server_distributed_execution: true

    servers_runners:
      hosts:
        example-server:
        example-runner1:
        example-runner2:
        example-runner3:
      vars:
        gateway_server_packages:
          - <IAGCTL-RPM>
        gateway_server_store_backend: etcd
        gateway_server_store_etcd_hosts: <ETCD-SERVER1-IP>:2379 <ETCD-SERVER2-IP>:2379 <ETCD-SERVER3-IP>:2379

    iag5_clients:
      hosts:
        example-client:
          ansible_host: <CLIENT-IP>
          gateway_client_host: <SERVER-IP>
      vars:
        gateway_client_packages:
          - <IAGCTL-TARBALL>
```

### High Availability with Distributed Execution Inventory

```yaml
# Note:
#  - All example inventory_hostname entries must be replaced with the actual server hostnames.
#  - All hostnames must be resolvable.
#  - Backend 'dynamodb' is also supported; see Reference Guide for details.
all:
  vars:
    ansible_user: <ANSIBLE-USER>

    # Itential Nexus repository credentials
    repository_username: <NEXUS-USERNAME>
    repository_password: <NEXUS-PASSWORD>

    gateway_secrets_encrypt_key: <ENCRYPT-KEY>
    gateway_pki_src_dir: <PKI-DIR>

  children:
    iag5_servers:
      hosts:
        example-active-server:
          ansible_host: <ACTIVE-SERVER-IP>
        example-standby-server:
          ansible_host: <STANDBY-SERVER-IP>

    iag5_runners:
      hosts:
        example-runner1:
          ansible_host: <RUNNER1-IP>
        rexample-unner2:
          ansible_host: <RUNNER2-IP>
        example-runner3:
          ansible_host: <RUNNER3-IP>
      vars:
        gateway_server_connect_hosts: <GATEWAY-MANAGER-IP>:8080
        gateway_server_distributed_execution: true

    servers_runners:
      hosts:
        example-active-server:
        example-standby-server:
        example-runner1:
        example-runner2:
        example-runner3:
      vars:
        gateway_server_packages:
          - <IAGCTL-RPM>
        gateway_server_store_backend: etcd
        gateway_server_store_etcd_hosts: <ETCD-SERVER1-IP>:2379 <ETCD-SERVER2-IP>:2379 <ETCD-SERVER3-IP>:2379

    iag5_clients:
      hosts:
        example-client:
          ansible_host: <CLIENT-IP>
          gateway_client_host: <ACTIVE-SERVER-IP>
      vars:
        gateway_client_packages:
          - <IAGCTL-TARBALL>
```

### Multiple Cluster Architecture Inventories

```yaml
# Note:
#  - All example inventory_hostname entries must be replaced with the actual server hostnames.
#  - All hostnames must be resolvable.
#  - Backend 'dynamodb' is also supported; see Reference Guide for details.
all:
  vars:
    ansible_user: <ANSIBLE-USER>

    # Itential Nexus repository credentials
    repository_username: <NEXUS-USERNAME>
    repository_password: <NEXUS-PASSWORD>

    gateway_secrets_encrypt_key: <ENCRYPT-KEY>
    gateway_pki_src_dir: <PKI-DIR>

  children:
    iag5_servers:
      hosts:
        example-cluster1_server:
          ansible_host: <CLUSTER1-SERVER-IP>
        example-cluster2_server:
          ansible_host: <CLUSTER2-SERVER-IP>
      vars:
        gateway_server_connect_hosts: <GATEWAY-MANAGER-IP>:8080
        gateway_server_distributed_execution: true

    iag5_runners:
      hosts:
        example-cluster1_runner1:
          ansible_host: <CLUSTER1-RUNNER1-IP>
        example-cluster1_runner2:
          ansible_host: <CLUSTER1-RUNNER2-IP>
        example-cluster1_runner3:
          ansible_host: <CLUSTER1-RUNNER3-IP>
        example-cluster2_runner1:
          ansible_host: <CLUSTER2-RUNNER1-IP>
        example-cluster2_runner2:
          ansible_host: <CLUSTER2-RUNNER2-IP>
        example-cluster2_runner3:
          ansible_host: <CLUSTER2-RUNNER3-IP>

    iag5_servers_runners:
      hosts:
        example-cluster1_server:
        example-cluster1_runner1:
        example-cluster1_runner2:
        example-cluster1_runner3:
        example-cluster2_server:
        example-cluster2_runner1:
        example-cluster2_runner2:
        example-cluster2_runner3:
      vars:
        gateway_server_packages:
          - <IAGCTL-RPM>
        gateway_server_store_backend: etcd

    cluster1_iag5_all:
      hosts:
        example-cluster1_client:
        example-cluster1_server:
        example-cluster1_runner1:
        example-cluster1_runner2:
        example-cluster1_runner3:
      vars:
        gateway_cluster_id: cluster_1

    cluster1_iag5_servers_runners:
      hosts:
        example-cluster1_server:
        example-cluster1_runner1:
        example-cluster1_runner2:
        example-cluster1_runner3:
      vars:
        gateway_server_store_etcd_hosts: <CLUSTER1-ETCD-SERVER1-IP>:2379 <CLUSTER1-ETCD-SERVER2-IP>:2379 <CLUSTER1-ETCD-SERVER3-IP>:2379

    cluster2_iag5_all:
      hosts:
        example-cluster2_client:
        example-cluster2_server:
        example-cluster2_runner1:
        example-cluster2_runner2:
        example-cluster2_runner3:
      vars:
        gateway_cluster_id: cluster_2

    cluster2_iag5_servers_runners:
      hosts:
        example-cluster2_server:
        example-cluster2_runner1:
        example-cluster2_runner2:
        example-cluster2_runner3:
      vars:
        gateway_server_store_etcd_hosts: <CLUSTER2-ETCD-SERVER1-IP>:2379 <CLUSTER2-ETCD-SERVER2-IP>:2379 <CLUSTER2-TCD-SERVER3-IP>:2379

    iag5_clients:
      hosts:
        example-cluster1_client:
          ansible_host: <CLUSTER1-CLIENT-IP>
          gateway_client_host: <CLUSTER1-SERVER-IP>
        example-cluster2_client:
          ansible_host: <CLUSTER2-CLIENT-IP>
          gateway_client_host: <CLUSTER2-SERVER-IP>
      vars:
        gateway_client_packages:
          - <IAGCTL-TARBALL>
```

## Reference Guide

All IAG5 collection variables are documented in the IAG Reference Guide.

[IAG Reference Guide](docs/reference_guide.md)

## Patching IAG5

To patch IAG5, simply replace the the current artifacts (RPM or tarball) in the inventory with the
new artifacts and re-run the appropriate playbook.
