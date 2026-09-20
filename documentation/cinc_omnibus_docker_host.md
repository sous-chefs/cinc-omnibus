# cinc_omnibus_docker_host

Prepares a **Windows Server** host to run Cinc omnibus builds in Windows containers. Windows
builds run inside the [`cincproject/omnibus-windows`](https://gitlab.com/cinc-project/docker-images)
image (MSYS2 UCRT64, `omnibus-toolchain`, WiX, 7-Zip, Git), so the host itself only needs the
Containers feature, Docker, and Defender out of the build path. The GitLab Runner (with the
`docker-windows` executor) is installed separately by
[`cinc_omnibus_gitlab_runner`](cinc_omnibus_gitlab_runner.md).

`cinc_omnibus_builder` invokes this resource automatically on Windows (unless
`manage_docker_host false`); you normally don't declare it directly. It is Windows-only and raises
elsewhere.

## Actions

| Action | Description |
| --- | --- |
| `:create` | Installs the Containers feature, configures Defender, installs `docker-engine` via Chocolatey, writes `daemon.json` when there is something to put in it, and enables/starts the `docker` service. Default action. |
| `:remove` | Stops and disables the `docker` service, deletes `daemon.json`, removes the Defender exclusions and re-enables real-time monitoring. Package removal is opt-in with `remove_package true`. The Containers feature is left installed and Defender is not reinstalled. |

## Properties

| Property | Type | Default | Description |
| --- | --- | --- | --- |
| `instance_name` | String | name property | Resource name. |
| `docker_engine_version` | String, nil | `nil` (latest) | Version of the Chocolatey `docker-engine` package. |
| `docker_data_root` | String, nil | `nil` (`C:\ProgramData\docker`) | Where Docker keeps image layers and container filesystems. Written as `data-root` in `daemon.json`; created and added to the Defender exclusions. |
| `docker_daemon_config` | Hash | `{}` | Extra `daemon.json` keys (e.g. `"group"`). Merged with `data-root`; the file is only written when the result is non-empty. |
| `containers_feature_source` | String, nil | `nil` (Windows Update) | `Install-WindowsFeature -Source` value for images with the Containers payload stripped (`InstallState: Removed`), e.g. `wim:D:\sources\install.wim:4`. |
| `reboot_after_feature_install` | true, false | `true` | Request a reboot at the end of the run when the Containers feature was installed or Defender removed. |
| `allow_hyperv` | true, false | `false` | Fail the converge when the Hyper-V feature is installed (see below). |
| `manage_defender` | true, false | `true` | Whether to touch Defender at all. |
| `defender_exclusions` | Array | `C:\ProgramData\docker`, `C:\Program Files\docker`, plus `docker_data_root` | Paths added to Defender's `ExclusionPath`. |
| `defender_process_exclusions` | Array | `[]` | Process names (`gcc.exe`, `ld.exe`, ...) added to `ExclusionProcess`. |
| `disable_defender_realtime` | true, false | `true` | Turn real-time and behavior monitoring off with `Set-MpPreference`. Ignored when `remove_defender` is true. |
| `remove_defender` | true, false | `false` | Uninstall the Defender feature entirely (reboot required). |
| `defender_feature_name` | String | `'Windows-Defender'` | Feature name passed to `Uninstall-WindowsFeature`. |
| `remove_package` | true, false | `false` | Whether `:remove` also uninstalls `docker-engine`. |

## What it does, and why

* **Hyper-V must be absent.** The builder image runs under *process* isolation, which needs no
  hypervisor and, on Windows Server Standard, allows unlimited containers; Hyper-V isolation caps
  you at two. With Hyper-V installed Docker may default to Hyper-V isolation, so the resource fails
  fast with the `Uninstall-WindowsFeature -Name Hyper-V -Restart` hint. `allow_hyperv true` skips
  the check.
* **Containers feature.** The Chocolatey `docker-engine` package does not enable it (unlike
  Microsoft's `install-docker-ce.ps1`), and without it Docker installs cleanly and then fails to
  start with `failed to connect to the docker API at npipe:////./pipe/docker_engine`. The install
  needs a reboot, requested at the end of the run; until then the docker service start is skipped
  with a warning and the next converge finishes the job. Bake the feature into the golden image so
  future hosts skip this.
* **Defender.** Real-time scanning sat at 90% CPU during a four-container OpenSSL run. The layer
  store and the engine's install dir are excluded, and real-time/behavior monitoring is turned off
  (Chef's `windows_defender` resource maps `realtime_protection` to `DisableIOAVProtection`, not
  `DisableRealtimeMonitoring`, and its exclusion resource does not quote `Program Files`, hence the
  direct `Set-MpPreference`/`Add-MpPreference` calls). Two caveats:
  * A container's writable layer is a mounted VHDX, so path exclusions never reach the files the
    compilers touch. `defender_process_exclusions` (by image name) is the lever for that.
  * **Tamper Protection** makes `Set-MpPreference` a silent no-op. The resource warns and skips
    instead of re-running every converge; turn it off in the Windows Security UI or via
    Intune/MDM, or set `remove_defender true` (`Uninstall-WindowsFeature` is not blocked). Removal
    leaves no on-host AV at all: reasonable on an isolated build host, not on anything
    general-purpose.
* **Docker.** Installed from the Chocolatey `docker-engine` package, which registers the `docker`
  service (`start=auto`) without starting it. A `docker` service Chocolatey does not own (Microsoft's
  `install-docker-ce.ps1`, the GitHub Actions runner image) is left alone rather than overwritten.
  `daemon.json` (`C:\ProgramData\docker\config\daemon.json`) is written only when `docker_data_root`
  or `docker_daemon_config` is set, and a change restarts the service.
* **`data-root` and the runner.** The `docker-windows` executor's `builds_dir`, `cache_dir` and
  `volumes` must live on `c:` (or be a bare drive letter). Moving image storage is done with
  `docker_data_root`, not by relocating the runner.

## Not managed here

* Registering the runners (`gitlab-runner register`): the runner resource installs the service, the
  two `[[runners]]` entries (a `shell` runner that builds the image and a `docker-windows` runner
  for product builds) are registered by hand. `runner-config.example.toml` in the docker-images
  repository is the reference `config.toml`.
* Pulling the builder image, `docker login` for Docker Hub rate limits, and periodic
  `docker system prune -a` (Windows layer cleanup is not prompt).

## Examples

```ruby
# Managed automatically by cinc_omnibus_builder; equivalent to:
cinc_omnibus_docker_host 'default'

# Layers on the NVMe volume, Defender gone, compiler processes excluded in the meantime:
cinc_omnibus_docker_host 'default' do
  docker_data_root 'E:\docker'
  remove_defender true
  defender_process_exclusions %w(gcc.exe ld.exe bash.exe make.exe)
end

# Golden image with the Containers payload stripped and no route to Windows Update:
cinc_omnibus_docker_host 'default' do
  containers_feature_source 'wim:D:\sources\install.wim:4'
  reboot_after_feature_install false
end
```
