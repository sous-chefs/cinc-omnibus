# cinc_omnibus_builder

Configures a build host for Cinc Omnibus projects.

## Actions

| Action | Description |
| --- | --- |
| `:create` | Installs build packages, installs the Cinc-built `omnibus-toolchain`, creates the `omnibus` user (Unix only) and environment files. This is the default action. |
| `:remove` | Removes files and directories managed directly by this resource. Package removal is opt-in with `remove_packages true`. |

The toolchain package is sourced from the Cinc Project's package mirror via the Cinc-patched `mixlib-install` gem (fetched from `https://rubygems.cinc.sh`), which routes `chef_ingredient` lookups through `omnitruck.cinc.sh`.

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
| `cache_dir` | String | platform-specific | Omnibus cache directory. Defaults to `/var/cache/omnibus` on Unix and `C:\omnibus\cache` on Windows. |
| `toolchain_install_dir` | String | platform-specific | Path where `omnibus-toolchain` is installed. Defaults to `/opt/omnibus-toolchain` on Unix and `C:\cinc-project\omnibus-toolchain` on Windows. |
| `toolchain_version` | String | `'latest'` | Version passed to `chef_ingredient`. |
| `toolchain_channel` | String, Symbol | `:stable` | Channel passed to `chef_ingredient`. |
| `toolchain_architecture` | String | kernel machine | Architecture passed to `chef_ingredient`. |
| `mixlib_install_version` | String | `'3.12.30'` | `mixlib-install` version override for `chef_ingredient`. |
| `ruby_docker_copy_patch_path` | String | `'/usr/local/share/ruby-docker-copy-patch.rb'` | Path for the Docker copy-file Ruby patch. |
| `manage_ruby_docker_copy_patch` | true, false | `true` | Whether to write the Ruby Docker copy-file patch. No-op on non-Linux platforms. |
| `manage_debian_arm_links` | true, false | `true` | Whether to create Debian ARM compatibility links on Debian versions older than 12. |
| `extra_environment` | Hash | `{}` | Additional environment variables for the toolchain load shim (`load-omnibus-toolchain.sh` on Unix, `load-omnibus-toolchain.ps1` on Windows). Values may be strings or arrays. |
| `remove_packages` | true, false | `false` | Whether `:remove` should remove configured packages. |
| `manage_msys2` | true, false | `true` | Windows only. Whether to install and manage MSYS2 via the `cinc_omnibus_msys2` resource. |
| `msys2_packages` | Array | UCRT64 build deps mirroring the Linux set | Pacman packages/groups passed to `cinc_omnibus_msys2`. |
| `msys2_ignore_packages` | Array | gcc/gcc-libs/binutils | Packages frozen via pacman `IgnorePkg`, passed to `cinc_omnibus_msys2`. |
| `msys2_pinned_packages` | Array | `[]` | Exact `.pkg.tar.zst` files/URLs to `pacman -U`, passed to `cinc_omnibus_msys2`. |
| `msys2_base_archive_date` | String | newest on the mirror | Dated MSYS2 base archive to install (defaults to the newest on the mirror), passed to `cinc_omnibus_msys2`. |
| `msys2_verify_signature` | true, false | `true` | Verify the MSYS2 base archive's GPG signature, passed to `cinc_omnibus_msys2`. |
| `manage_gitlab_runner` | true, false | `true` | Non-Linux only. Whether to install and manage the GitLab Runner via the [`cinc_omnibus_gitlab_runner`](cinc_omnibus_gitlab_runner.md) resource. No-op on Linux. |
| `manage_gitlab_runner_service` | true, false | `true` | Whether the runner service is set up and started (passed to `cinc_omnibus_gitlab_runner`). |
| `manage_gitlab_runner_signing` | true, false | `true` | macOS only. Whether to re-sign the runner binary with a fixed identity for a durable TCC grant (passed to `cinc_omnibus_gitlab_runner`). |
| `gitlab_runner_version` | String, nil | `nil` | GitLab Runner version to install (passed to `cinc_omnibus_gitlab_runner`). |

## Platform notes

* **Linux:** installs the `omnibus-toolchain` package via `chef_ingredient`, creates the `omnibus`
  user and group, drops the Docker copy-file Ruby patch at
  `/usr/local/share/ruby-docker-copy-patch.rb`, and on Debian ARM versions older than 12 creates
  `/usr/bin/mkdir` and `/bin/install` compatibility symlinks.
* **macOS:** installs Homebrew prerequisites, installs the `omnibus-toolchain` `.pkg`, and creates
  `/usr/local/bin/libtoolize` → Homebrew's `glibtoolize`. On Apple Silicon also creates
  `/usr/local/bin/pkg-config` → Homebrew's `pkg-config`, since the Homebrew prefix
  (`/opt/homebrew`) isn't on the default omnibus PATH.
* **FreeBSD:** installs `pkg` prerequisites and the `omnibus-toolchain` self-extracting `.sh`.
* **Windows:** installs chocolatey and the build tools it manages (WiX, 7-Zip, the Windows SDK,
  Git), installs the `omnibus-toolchain` `.msi` to `C:\cinc-project\omnibus-toolchain`, skips the
  omnibus user/group creation, and writes `load-omnibus-toolchain.ps1` instead of the bash shim.
  The shim prepends those tool directories (plus MSYS2 and the toolchain's `embedded\bin`) to
  `$env:PATH` and sets `HOMEDRIVE`/`HOMEPATH` to the build user's home, so a freshly bootstrapped
  box works without relying on a pre-baked system PATH.

  **MSYS2 is managed by the [`cinc_omnibus_msys2`](cinc_omnibus_msys2.md) resource** (unless
  `manage_msys2 false`). It installs MSYS2 at `C:\msys64`, provisions the ucrt64 build toolchain
  via pacman, and freezes gcc/binutils with `IgnorePkg` so upgrades are deliberate. The shim adds
  `C:\msys64\ucrt64\bin` and `C:\msys64\usr\bin` to PATH. Chocolatey is still used for the other
  Windows build tools (WiX, 7-Zip, the Windows SDK, Git).

* **GitLab Runner (non-Linux only):** on macOS, FreeBSD, and Windows the builder also installs and
  manages the GitLab Runner via the [`cinc_omnibus_gitlab_runner`](cinc_omnibus_gitlab_runner.md)
  resource (unless `manage_gitlab_runner false`). Registration stays manual. On macOS it re-signs the
  Homebrew binary with a fixed identity so the "control Finder" TCC grant survives upgrades — see that
  resource's docs for the one-time bootstrap. On Linux this is a no-op (the runner lives on the Docker
  host).

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

### Remove generated files

```ruby
cinc_omnibus_builder 'default' do
  action :remove
end
```
