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
* **Windows:** installs the `omnibus-toolchain` `.msi` to `C:\cinc-project\omnibus-toolchain`,
  skips the omnibus user/group creation, and writes `load-omnibus-toolchain.ps1` instead of the
  bash shim. PATH on Windows is *not* prepended by the shim — the runner's system PATH already
  orders WiX / 7-Zip / MSYS2 / Ruby / Git correctly and prepending would shadow that ordering.

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
