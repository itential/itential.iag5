# Role: offline

## Purpose

Shared utility role for air-gapped installs of Itential Gateway. It downloads packages (RPMs and
the client archive) to a target node, fetches them to the control node, and installs RPMs from the
control node onto target nodes with all repositories disabled. It has no `main.yml` and no
defaults. All task files are called with `tasks_from:` by the `gateway_server` and `gateway_client`
roles, and all variables are passed in by the calling task. See `docs/offline_install_guide.md`.

## Task Files

| File | Called By | Purpose |
|------|-----------|---------|
| `download-rpms.yml` | `gateway_server/tasks/download-packages.yml` | Downloads RPMs on the target node using one of several methods |
| `download-archives.yml` | `gateway_client/tasks/download-packages.yml` | Downloads archives (the client tarball) from `https://` URLs to the target node |
| `fetch-packages.yml` | `gateway_server` and `gateway_client` `download-packages.yml` | Copies the downloaded packages from the target node to the control node |
| `install-rpms.yml` | `gateway_server/tasks/install_gateway.yml`, `install_python.yml`, `install_tofu.yml` | Copies RPMs from the control node to the target node and installs them |

The client tarball is not installed by this role. `gateway_client/tasks/install_gateway_client.yml`
unpacks it from `gateway_offline_control_node_archives_dir` itself.

## download-rpms.yml

Requires the caller to set:

| Variable | Values | Purpose |
|----------|--------|---------|
| `offline_download_dir` | path | Directory on the target node to download RPMs into |
| `offline_download_method` | `yum_module`, `yum_install`, `yum_reinstall`, `repotrack`, `yumdownloader`, `get_url` | Which download mechanism to use |
| `offline_download_packages` | list | Package names or URLs to download |

`gateway_server/tasks/download-packages.yml` uses `get_url` for the `iagctl` RPM and
`gateway_offline_download_method` (default `yum_module`) for the Python and OpenTofu RPMs.

`get_url` supports `repository_api_key` (JFrog and GitLab) and `repository_username` /
`repository_password` (Nexus).

## download-archives.yml

Requires `offline_download_dir` and `offline_download_packages`. Downloads each `https://` URL with
`get_url`, using the same authentication as `download-rpms.yml`.

## fetch-packages.yml

Requires:

| Variable | Purpose |
|----------|---------|
| `offline_src_dir` | Directory on the target node containing the downloaded packages |
| `offline_dest_dir` | Directory on the control node to fetch the packages into |

Uses `ansible.builtin.fetch` with `flat: true`.

## install-rpms.yml

Requires `offline_rpms_path`, a directory on the control node whose `*.rpm` files are copied and
installed.

Process: creates a temp dir on the target, copies the RPMs, rebuilds the RPM DB, disables all
repos, installs with `dnf` using `cacheonly: true` and `disable_gpg_check: true`, then removes the
temp dir. Set `offline_use_rpm_cmd: true` and `offline_rpm_cmd_opts` to install with `rpm -i`
instead.

## Offline Directory Structure

The paths are built in `roles/gateway/defaults/main.yml`. There is one tree under
`gateway_offline_control_node_root` on the control node and one under `gateway_offline_target_node_root`
(default `/var/tmp`) on the target node:

```text
<gateway_offline_control_node_root>/itential_packages
└── gateway
    └── <VERSION>
        └── <OS>
            ├── archives
            └── rpms
                ├── gateway
                ├── opentofu
                └── python
```

- `<VERSION>` is parsed from the file names in `gateway_server_packages` (server RPMs) and
  `gateway_client_packages` (client archive) by `gateway_offline_version_regex`. There is no
  release variable to set.
- `<OS>` is `gateway_offline_os`, for example `rocky_9`.
- `rpms/gateway` holds the `iagctl` RPM, `rpms/python` and `rpms/opentofu` hold those features'
  RPMs (only when the feature is enabled), and `archives` holds the client tarball.

## Dependencies / Assumptions

- `gateway_offline_control_node_root` must be set in the inventory and be a directory on the control node.
  The `gateway_server` and `gateway_client` `validate-vars.yml` and `download-packages.yml` assert it.
- The role is not applied on its own. The download task files run from
  `playbooks/download_packages.yml`, which forces `gateway_offline_install_enabled` to `false`; the install
  task files run when `gateway_offline_install_enabled` is `true`.
- `install-rpms.yml` relies on the RPMs being self-contained, with all dependencies downloaded.
  Use `yumdownloader` or `repotrack` as `gateway_offline_download_method` when the download host
  already has some of the packages installed.

## Gotchas

- `download-rpms.yml` with `get_url` only processes packages where `'http' in package` and
  `package.endswith('.rpm')`. `download-archives.yml` only processes entries containing `http`.
  Other entries are silently skipped.
- `download-rpms.yml` with `repotrack` runs from the download directory (`chdir`), not with
  `--download-path`. Verify `repotrack` behavior on the target OS version.
- `download-rpms.yml` with `yumdownloader` sets `failed_when: false`, so a failed download does not
  fail the play. Check the downloaded files.
- `install-rpms.yml` with `offline_use_rpm_cmd: true` needs the caller to set `offline_rpm_cmd_opts`.
  Neither variable has a default or is set anywhere in the collection.
