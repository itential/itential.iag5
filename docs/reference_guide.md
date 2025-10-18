# IAG5 Reference Guide

## Common Variables

The variables in this section are common to the client, server and runner roles. They can be
overridden in the `iag5_clients`, `iag5_servers` or `iag_runners` group vars.

| Variable | Type | Description | Default Value |
| :------- | :--- | :---------- | :------------ |
| `gateway_cluster_id` | String | The IAG5 cluster ID. | cluster_1 |
| `gateway_pki_upload` | Boolean | Flag for enabling/disabling upload of PKI certificates and keys. | true |
| `gateway_pki_key_suffix` | String | The default PKI key suffix. | .key |
| `gateway_pki_cert_suffix` | String | The default PKI certificate suffix. | .crt |
| `gateway_pki_src_dir` | String | The PKI source directory on the control node. | N/A (must be defined in inventory) |
| `gateway_secrets_encrypt_key` | String | The secrets encrypt key. | N/A (must be defined in inventory) |
| `gateway_secrets_encrypt_key_dir` | String | The directory where the secrets encrypt key is stored. | "{{ gateway_client_working_dir }}/keys" (clients)<br>"{{ gateway_server_config_dir }}/keys" (servers/runners) |
| `gateway_secrets_encrypt_key_file` | String | The path to the secrets encrypt key. | "{{ gateway_secrets_encrypt_key_dir }}/encryption-key" |
| `repository_username` | String | The username for authenticating to the Itential Nexus repository. | N/A |
| `repository_password` | String | The password for authenticating to the Itential Nexus repository. | N/A |

## Client Variables

The variables in this section may be overridden in the inventory in the `iag5_clients` group vars.

| Variable | Type | Description | Default Value |
| :------- | :--- | :---------- | :------------ |
| `gateway_client_packages` | List of Strings | The gateway client packages to install. | N/A (must be defined in inventory) |
| `gateway_client_user` | String | The user account where the client will be installed. | itential |
| `gateway_client_group` | String | The user group. | itential |
| `gateway_client_install_dir` | String | The location where the client binaries will be installed. | "/home/{{ gateway_client_user }}/.local/bin" |
| `gateway_client_working_dir` | String | The location where the client working files are located. | "/home/{{ gateway_client_user }}/.gateway.d" |
| `gateway_client_host` | String | The hostname or IP of the IAG5 server the client will connect to. | N/A (must be defined in inventory) |
| `gateway_client_port` | Integer | The port of the IAG5 server the client will connect to. | 50051 |
| `gateway_client_log_level` | String | The client logging level. | INFO |
| `gateway_client_use_tls` | Boolena | Flag for enabling/disabling TLS. | true |
| `gateway_client_pki_dir` | String | Path to the client TLS certificates and keys. | "{{ gateway_client_working_dir }}/ssl" |
| `gateway_client_pki_key_file` | String | The name of the client TLS key file. | "{{ inventory_hostname }}{{ gateway_pki_key_suffix }}" |
| `gateway_client_pki_key_src` | String | The path to the source client TLS key file on the control node. | "{{ gateway_pki_src_dir }}/{{ gateway_client_pki_key_file }}" |
| `gateway_client_pki_key_dest` | String | The path to the destination client TLS key. | "{{ gateway_client_pki_dir }}/{{ gateway_client_pki_key_file }}" |
| `gateway_client_pki_cert_file` | String | The name of the client TLS certificate. | "{{ inventory_hostname }}{{ gateway_pki_cert_suffix }}" |
| `gateway_client_pki_cert_src` | String | The path to the source client TLS certificate file on the control node. | "{{ gateway_pki_src_dir }}/{{ gateway_client_pki_cert_file }}" |
| `gateway_client_pki_cert_dest` | String | The path to the destination client TLS certificate. | "{{ gateway_client_pki_dir }}/{{ gateway_client_pki_cert_file }}" |
| `gateway_client_pki_ca_file` | String | The name of the client TLS CA certificate file. | "ca{{ gateway_pki_cert_suffix }}" |
| `gateway_client_pki_ca_cert_src` | String | The path to the source client TLS CA certificate on the control node. | "{{ gateway_pki_src_dir }}/{{ gateway_client_pki_ca_file }}" |
| `gateway_client_pki_ca_cert_dest` | String | The path to the client TLS CA certificate. | "{{ gateway_client_pki_dir }}/{{ gateway_client_pki_ca_file }}" |
| `gateway_client_terminal_timestamp_timezone` | String | Timezones are shown in UTC by default. When you set this to 'local', the client uses your machine's timezone.<br>You can also set a timezone (tz) identifier such as 'America/New_York'. | utc |

If `gateway_client_packages` contains links to artifacts in the Itential Nexus repository, the
`repository_username`/`repository_password` must be defined.

# Common Server/Runner Variables

The variables in this section are common to the server and runner roles. They can be overridden in
the `iag5_servers` or `iag_runners` group vars.

| Variable | Type | Description | Default Value |
| :------- | :--- | :---------- | :------------ |
| `gateway_server_packages` | List of Strings | The gateway server packages to install | N/A (must be defined in inventory) |
| `gateway_server_listen_address` | String | The server listen address. | 0.0.0.0 |
| `gateway_server_port` | Integer | The server listen port. | 50051 |
| `gateway_server_requirements_file` | String |  | requirements.txt |
| `gateway_server_user` | String | The server user. All server files and the service will be owned by this user. | itential |
| `gateway_server_group` | String | The server group. | itential |
| `gateway_server_config_dir` | String | The directory containing the server configuration files. | /etc/gateway |
| `gateway_server_data_dir` | String | The directory containing the server data files. | /var/lib/gateway |
| `gateway_server_python_packages` | List of String | The list of Python packages to install. | - python3.12<br>- python3.12-pip |
| `gateway_server_python_executable` | String | The path to the Python executable. | /usr/bin/python3.12 |
| `gateway_server_pip_executable` | String | The path to the Pip executable. | /usr/bin/pip3.12 |
| `gateway_server_local_bin_dir` | String | The server local binnary directory. | "/home/{{ gateway_server_user }}/.local/bin" |
| `gateway_server_opentofu_packages` | List of String | The list of OpenTofu packages to install. | - tofu |
| `gateway_server_log_console_json` | Boolean | Flag for enabling/disabling logging to the console in JSON format. | false |
| `gateway_server_log_file_enabled` | Boolean | Flag for enabling/disabling logging. | true |
| `gateway_server_log_file_json` | Boolean | Flag for enabling/disabling logging in JSON format. | false |
| `gateway_server_log_level` | String | The logging level. | INFO |
| `gateway_server_log_server_dir` | String | The directory where log files are written. | /var/log/gateway |
| `gateway_server_log_timestamp_timezone` | String | Sets the timezone for timestamps in gateway logs.<br>Timezones are shown in UTC by default. When you set this to 'local', the client uses your machine's timezone.<br>You can also set a timezone (tz) identifier such as 'America/New_York'. | utc |
| `gateway_server_use_tls` | Boolean | Flag for enabling/disabling TLS. | true |
| `gateway_server_pki_dir` | String | The directory where TLS certificates and keys are located. | "{{ gateway_server_config_dir }}/ssl" |
| `gateway_server_pki_key_file` | String | The name of the server TLS key file. | "{{ inventory_hostname }}{{ gateway_pki_key_suffix }}" |
| `gateway_server_pki_key_src` | String | The path to the source server TLS key file on the control node. | "{{ gateway_pki_src_dir }}/{{ gateway_server_pki_key_file }}" |
| `gateway_server_pki_key_dest` | String | The path to the destination server TLS key. | "{{ gateway_server_pki_dir }}/{{ gateway_server_pki_key_file }}" |
| `gateway_server_pki_cert_file` | String | The name of the server TLS certificate. | "{{ inventory_hostname }}{{ gateway_pki_cert_suffix }}" |
| `gateway_server_pki_cert_src` | String | The path to the source server TLS certificate file on the control node. | "{{ gateway_pki_src_dir }}/{{ gateway_server_pki_cert_file }}" |
| `gateway_server_pki_cert_dest` | String | The path to the destination server TLS certificate. | "{{ gateway_server_pki_dir }}/{{ gateway_server_pki_cert_file }}" |
| `gateway_server_pki_ca_file` | String | The name of the server TLS CA certificate file. | "ca{{ gateway_pki_cert_suffix }}" |
| `gateway_server_pki_ca_cert_src` | String | The path to the source server TLS CA certificate on the control node. | "{{ gateway_pki_src_dir }}/{{ gateway_server_pki_ca_file }}" |
| `gateway_server_pki_ca_cert_dest` | String | The path to the server TLS CA certificate. | "{{ gateway_server_pki_dir }}/{{ gateway_server_pki_ca_file }}" |
| `gateway_server_registry_default_overridable` | Boolean | Controls whether users can override the default PyPI or Ansible Galaxy registries when creating a Python or Ansible service. | true |
| `gateway_server_store_backend` | String | Sets the backend type for persistent data storage.<br>Valid values are 'local', 'memory', 'etc' and 'dynamodb' | local |
| `gateway_server_store_etcd_hosts` | String | Sets the etcd hosts that the gateway connects to for backend storage.<br>A host entry consists of an address and port: hostname:port.<br>If there are multiple etcd hosts, enter them as a space separated list: hostname1:port hostname2:port. | localhost:2379 |
| `gateway_server_store_etcd_use_tls` | Boolean | Flag for enabling/disabling TLS connections to Etcd. | true |
| `gateway_server_store_etcd_client_cert_auth` | Boolean | Flag for determining the TLS authentication method used when connecting to an Etcd store backend and gateway_server_store_etcd_use_tls is set to 'true'. | true |
| `gateway_server_store_dynamodb_table_name` | String | Sets the Amazon DynamoDB table name that the gateway connects to for backend storage. | itential.gateway5.store |
| `gateway_server_store_dynamodb_aws_access_key_id` | String | The AWS access key when using DynamoDB. | N/A |
| `gateway_server_store_dynamodb_aws_secret_access_key` | String | The AWS secret access key when using DynamoDB. | N/A |
| `gateway_server_store_dynamodb_aws_session_token` | String | The AWS session token when using DynamoDB. | N/A |
| `gateway_server_store_dynamodb_aws_region` | String | The AWS region when using DynamoDB. | N/A |
| `gateway_server_terminal_no_color` | Boolean | Determines whether the console outputs and logs display in color. | false |

If `gateway_server_packages` contains links to artifacts in the Itential Nexus repository, the
`repository_username`/`repository_password` must be defined.

# Server Variables

The variables in this section may be overridden in the inventory in the `iag5_servers` group vars.

| Variable | Type | Description | Default Value |
| :------- | :--- | :---------- | :------------ |
| `gateway_server_distributed_execution` | Boolean | Flag for enabling/disabling distributed execution.<br>Set to 'true' when deploying an architecture utilizing runners. | false |
| `gateway_server_api_key_expiration` | Integer | The amount of time (in minutes) before a user API key expires. | 1440 |
| `gateway_server_connect_enabled` | Boolean | Flag for enabling/disabling the connection to Gateway Manager | true |
| `gateway_server_connect_server_ha_enabled` | Boolean | Enable this configuration variable when you have multiple all in one or core nodes for a particular GATEWAY_APPLICATION_CLUSTER_ID. When you enable High Availability (HA), the system runs in active/standby mode. One server connects to Gateway Manager while the others remain in standby mode. If the active node goes down, a standby node connects to Gateway Manager and begins serving requests. | false |
| `gateway_server_connect_server_ha_is_primary` | Boolean | When you set GATEWAY_CONNECT_SERVER_HA_ENABLED to true, use this configuration variable to designate one node as the primary. When all nodes are online, this node takes the highest precedence and connects to Gateway Manager. Only one core HA node can connect to Gateway Manager at a time. If this node loses connection to Gateway Manager or the database, a standby node takes its place. | false |
| `gateway_server_connect_insecure_tls` | Boolean | Determines whether the gateway verifies TLS certificates when it connects to Itential Platform. When set to true, the gateway skips TLS certificate verification. We strongly recommend enabling TLS certificate verification in production environments. | false |
| `gateway_server_connect_certificate_file` | String | Specifies the full path to the certificate file used to establish a secure connection to Gateway Manager. | "{{ gateway_server_pki_cert_dest }}" |
| `gateway_server_connect_private_key_file` | String | Specifies the full path to the private key file that the gateway uses to connect to Gateway Manager. | "{{ gateway_server_pki_key_dest }}" |
| `gateway_server_features_ansible_enabled` | Boolean | Enables or disables all Ansible features. When you set this variable to false, the gateway disables the management of Ansible playbooks and the execution of Ansible services. | true |
| `gateway_server_features_hostkeys_enabled` | Boolean | Enables or disables the hostkeys feature. When you set this variable to false, the gateway disables the hostkeys managment commands. | true |
| `gateway_server_features_opentofu_enabled` | Boolean | Enables or disables all OpenTofu features. When you set this variable to false, the gateway disables the management of OpenTofu plans and the execution of OpenTofu services. | true |
| `gateway_server_features_python_enabled` | Boolean | Enables or disables all Python features. When you set this variable to false, the gateway disables the management of Python scripts and the execution of Python services. | true |

# Runner Variables

The variables in this section may be overridden in the inventory in the `iag5_runners` group vars.

| Variable | Type | Description | Default Value |
| :------- | :--- | :---------- | :------------ |
| `gateway_server_runner_announcement_address` | IP Address | Sets the address that a gateway runner registers to its cluster when it comes online. When a gateway core server sends a service execution request to a gateway runner, it sends the request to this address. If you don't explicitly set this variable, the gateway runner identifies its own IP address and registers it to the cluster. | N/A (must be defined in inventory when runners are used.) |
