# Role: offline

Shared utility role for air-gapped installs. It has no `main.yml` and no defaults; the
`gateway_server` and `gateway_client` roles call its task files with `tasks_from:`. All
variables are passed in by the calling task. See `docs/offline_install_guide.md`.

## Task files

| File | Purpose | Required variables |
| :--- | :------ | :----------------- |
| `download-rpms.yml` | Downloads RPMs on the target node. | `offline_download_dir`, `offline_download_method` (`yum_module`, `yum_install`, `yum_reinstall`, `repotrack`, `yumdownloader`, `get_url`), `offline_download_packages` |
| `download-archives.yml` | Downloads archives (for example the client tarball) from `https://` URLs to the target node. | `offline_download_dir`, `offline_download_packages` |
| `fetch-packages.yml` | Copies the downloaded packages from the target node to the control node. | `offline_src_dir`, `offline_dest_dir` |
| `install-rpms.yml` | Copies RPMs from the control node to the target node and installs them with all repositories disabled. | `offline_rpms_path` |

`install-rpms.yml` installs with `dnf` using `cacheonly: true`. Set `offline_use_rpm_cmd: true`
and `offline_rpm_cmd_opts` to install with `rpm -i` instead. `gateway_server` sets both
automatically when the install directories are relocated, passing the `--relocate` options built
from `gateway_server_relocations`.

`get_url` downloads support `repository_api_key` (JFrog and GitLab) and `repository_username`
and `repository_password` (Nexus).
