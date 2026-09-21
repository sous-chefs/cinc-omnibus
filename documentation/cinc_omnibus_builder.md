# cinc_omnibus_builder

Configures a build host for Cinc Omnibus projects.

## Actions

| Action | Description |
| --- | --- |
| `:create` | Installs build packages, installs the Cinc-built `omnibus-toolchain`, creates the `omnibus` user and environment files. On Windows, prepares a Docker host instead (see below). This is the default action. |
| `:remove` | Removes files and directories managed directly by this resource. Package removal is opt-in with `remove_packages true`. |

The toolchain package is sourced from the Cinc Project's package mirror via the Cinc-patched `mixlib-install` gem (fetched from `https://rubygems.cinc.sh`), which routes `chef_ingredient` lookups through `omnitruck.cinc.sh`.

On Windows the builds run in the `cincproject/omnibus-windows` container image, which carries the
toolchain, MSYS2 and the build tools; the resource prepares the host as a Docker host via
[`cinc_omnibus_docker_host`](cinc_omnibus_docker_host.md) and installs the GitLab Runner. None of the
package, user, toolchain or shim properties apply there.

## Properties

| Property | Type | Default | Description |
| --- | --- | --- | --- |
| `instance_name` | String | name property | Resource name. |
| `packages` | Array, nil | platform-specific | Build dependency packages to install. |
| `unsafe_packages` | Array, nil | platform-specific | Packages to remove because they conflict with Omnibus builds. |
| `pkgconfig_files` | Array | platform-specific | `pkg-config-lite` files to remove from the omnibus toolchain. |
| `build_user` | String | `'omnibus'` | Build user to create and own generated files. |
| `build_group` | String | `'omnibus'` | Build group to create and assign to the build user. |
| `build_user_home` | String | platform-specific | Home directory for the build user. |
| `build_user_shell` | String | platform-specific | Shell for the build user. |
| `cache_dir` | String | `/var/cache/omnibus` | Omnibus cache directory. |
| `toolchain_install_dir` | String | `/opt/omnibus-toolchain` | Path where `omnibus-toolchain` is installed. |
| `toolchain_version` | String | `'latest'` | Version passed to `chef_ingredient`. |
| `toolchain_channel` | String, Symbol | `:stable` | Channel passed to `chef_ingredient`. |
| `toolchain_architecture` | String | kernel machine | Architecture passed to `chef_ingredient`. |
| `mixlib_install_version` | String | `'3.12.30'` | `mixlib-install` version override for `chef_ingredient`. |
| `ruby_docker_copy_patch_path` | String | `'/usr/local/share/ruby-docker-copy-patch.rb'` | Path for the Docker copy-file Ruby patch. |
| `manage_ruby_docker_copy_patch` | true, false | `true` | Whether to write the Ruby Docker copy-file patch. No-op on non-Linux platforms. |
| `manage_debian_arm_links` | true, false | `true` | Whether to create Debian ARM compatibility links on Debian versions older than 12. |
| `git_safe_directories` | Array | `["<build_user_home>/builds/*"]` | Paths written as `safe.directory` entries in the managed `.gitconfig`, so git accepts the runner's checkout when the build step runs it under `sudo`. A trailing `/*` matches at any depth and needs git 2.46 or newer. |
| `manage_root_gitconfig` | true, false | `true` | macOS only. Whether to write the same `.gitconfig` to `/var/root` as well as the build user's home. |
| `extra_environment` | Hash | `{}` | Additional environment variables for the toolchain load shim (`load-omnibus-toolchain.sh`). Values may be strings or arrays. |
| `remove_packages` | true, false | `false` | Whether `:remove` should remove configured packages (and, on Windows, `docker-engine` and `gitlab-runner`). |
| `manage_gitlab_runner` | true, false | `true` | Non-Linux only. Whether to install and manage the GitLab Runner via the [`cinc_omnibus_gitlab_runner`](cinc_omnibus_gitlab_runner.md) resource. No-op on Linux. |
| `manage_gitlab_runner_service` | true, false | `true` | Whether the runner service is set up and started (passed to `cinc_omnibus_gitlab_runner`). |
| `manage_gitlab_runner_signing` | true, false | `true` | macOS only. Whether to re-sign the runner binary with a fixed identity for a durable TCC grant (passed to `cinc_omnibus_gitlab_runner`). |
| `manage_gitlab_runner_sudoers` | true, false | `true` | macOS and FreeBSD. Whether to grant the account the runner runs as passwordless sudo via a `sudoers.d` drop-in (passed to `cinc_omnibus_gitlab_runner`). |
| `gitlab_runner_version` | String, nil | `nil` | GitLab Runner version to install (passed to `cinc_omnibus_gitlab_runner`). |
| `manage_docker_host` | true, false | `true` | Windows only. Whether to prepare the host via [`cinc_omnibus_docker_host`](cinc_omnibus_docker_host.md). |
| `docker_engine_version` | String, nil | `nil` | Windows only. Chocolatey `docker-engine` version (passed to `cinc_omnibus_docker_host`). |
| `docker_data_root` | String, nil | `nil` | Windows only. Docker `data-root` for image layers and container filesystems (passed to `cinc_omnibus_docker_host`). |
| `docker_daemon_config` | Hash | `{}` | Windows only. Extra `daemon.json` keys (passed to `cinc_omnibus_docker_host`). |
| `containers_feature_source` | String, nil | `nil` | Windows only. `Install-WindowsFeature -Source` for a payload-stripped image (passed to `cinc_omnibus_docker_host`). |
| `reboot_after_feature_install` | true, false | `true` | Windows only. Request a reboot at the end of the run after a feature change (passed to `cinc_omnibus_docker_host`). |
| `allow_hyperv` | true, false | `false` | Windows only. Don't fail when Hyper-V is installed (passed to `cinc_omnibus_docker_host`). |
| `manage_defender` | true, false | `true` | Windows only. Whether to configure Defender at all (passed to `cinc_omnibus_docker_host`). |
| `defender_exclusions` | Array | Docker dirs, `docker_data_root`, `C:\GitLab-Runner` | Windows only. Defender path exclusions (passed to `cinc_omnibus_docker_host`). |
| `defender_process_exclusions` | Array | `[]` | Windows only. Defender process exclusions (passed to `cinc_omnibus_docker_host`). |
| `disable_defender_realtime` | true, false | `true` | Windows only. Turn real-time/behavior monitoring off (passed to `cinc_omnibus_docker_host`). |
| `remove_defender` | true, false | `false` | Windows only. Uninstall the Defender feature (passed to `cinc_omnibus_docker_host`). |

## Platform notes

* **Linux:** installs the `omnibus-toolchain` package via `chef_ingredient`, creates the `omnibus`
  user and group, drops the Docker copy-file Ruby patch at
  `/usr/local/share/ruby-docker-copy-patch.rb`, and on Debian ARM versions older than 12 creates
  `/usr/bin/mkdir` and `/bin/install` compatibility symlinks.
* **macOS:** installs Homebrew prerequisites, installs the `omnibus-toolchain` `.pkg`, and creates
  `/usr/local/bin/libtoolize` → Homebrew's `glibtoolize` and `/usr/local/bin/tar` → Homebrew's
  `gtar` (the system `tar` is bsdtar, which rejects GNU options). On Apple Silicon also creates
  `/usr/local/bin/pkg-config` → Homebrew's `pkg-config`, since the Homebrew prefix
  (`/opt/homebrew`) isn't on the default omnibus PATH. Because the build user's primary group is
  set to `omnibus`, it also keeps the user in the `com.apple.access_ssh` group so SSH logins keep
  working when Remote Login is limited to specific users.

  Apple Silicon also gets `/usr/local/bin/git` → Homebrew's `git`, for the same PATH reason.
  Builds run `sudo -E bundle exec omnibus build`, so git runs as root over a checkout the build
  user owns and refuses it unless the path is a `safe.directory`. Apple's `/usr/bin/git` (2.32.1)
  is too old to honor either the `safe.directory` values that survive a runner re-registration
  (only exact paths work — not `*`, not a trailing `/*`) or the `SUDO_UID` bypass git 2.36 added
  for exactly this case, so Intel — which reaches Homebrew's git through `/usr/local/bin` for
  free — worked while Apple Silicon silently produced `0.0.0` packages. Without a git new enough
  for it, `git describe` fails and omnibus falls back to that version.
* **FreeBSD:** installs `pkg` prerequisites and the `omnibus-toolchain` self-extracting `.sh`. Also
  links `/usr/local/openssl/cert.pem` → `/usr/local/share/certs/ca-root-nss.crt`: the ports OpenSSL
  compiles in `/usr/local/openssl` as its `OPENSSLDIR`, but `ca_root_nss` only populates
  `/usr/local/etc/ssl` and `/usr/local/share/certs`, so anything linked against it (an RVM-built
  Ruby, notably) fails TLS verification with "unable to get local issuer certificate". The load
  shim prepends `/usr/local/libexec/ccache` to `PATH` so builds pick up the `ccache` port's
  compiler wrappers, matching what ports' `bsd.ccache.mk` does.
* **Windows (Server 2022+):** the host is a Docker host, not a builder. Via
  [`cinc_omnibus_docker_host`](cinc_omnibus_docker_host.md) the resource installs the Containers
  feature (reboot requested at the end of the run), fails if Hyper-V is present (process isolation
  is the point), adds Defender exclusions for the Docker dirs and the runner dir and turns real-time
  monitoring off (or removes Defender with `remove_defender true`), installs `docker-engine` through
  Chocolatey and starts the service. No build user, toolchain, MSYS2 or load shim: those live in the
  `cincproject/omnibus-windows` image the `docker-windows` runner pulls.

* **GitLab Runner (non-Linux only):** on macOS, FreeBSD, and Windows the builder also installs and
  manages the GitLab Runner via the [`cinc_omnibus_gitlab_runner`](cinc_omnibus_gitlab_runner.md)
  resource (unless `manage_gitlab_runner false`). Registration stays manual. On macOS it re-signs the
  Homebrew binary with a fixed identity so the "control Finder" TCC grant survives upgrades — see that
  resource's docs for the one-time bootstrap. On Linux this is a no-op (the runner lives on the Docker
  host). On Windows the one service serves both the `shell` runner that builds the image and the
  `docker-windows` runner that runs the product builds.

## Examples

### Configure a default build host

```ruby
cinc_omnibus_builder 'default'
```

### Add environment used by Omnibus builds

```ruby
cinc_omnibus_builder 'default' do
  extra_environment(
    'BUNDLE_WITHOUT' => 'development'
  )
end
```

### Windows Docker host with layers on a separate volume

```ruby
cinc_omnibus_builder 'default' do
  docker_data_root 'E:\docker'
  remove_defender true
end
```

### Remove generated files

```ruby
cinc_omnibus_builder 'default' do
  action :remove
end
```
