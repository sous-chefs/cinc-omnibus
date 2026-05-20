# cinc_omnibus_builder

Configures a build host for Cinc Omnibus projects.

## Actions

| Action | Description |
| --- | --- |
| `:create` | Installs build packages, installs `omnibus-toolchain`, creates the `omnibus` user and environment files. This is the default action. |
| `:remove` | Removes files and directories managed directly by this resource. Package removal is opt-in with `remove_packages true`. |

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
| `cache_dir` | String | `'/var/cache/omnibus'` | Omnibus cache directory. |
| `toolchain_install_dir` | String | platform-specific | Path where `omnibus-toolchain` is installed. |
| `toolchain_version` | String | `'latest'` | Version passed to `chef_ingredient`. |
| `toolchain_channel` | String, Symbol | `:stable` | Channel passed to `chef_ingredient`. |
| `toolchain_architecture` | String | kernel machine | Architecture passed to `chef_ingredient`. |
| `manage_toolchain` | true, false | `true` | Whether to install or upgrade `omnibus-toolchain` with `chef_ingredient`. |
| `mixlib_install_version` | String | `'3.12.30'` | `mixlib-install` version override for `chef_ingredient`. |
| `ruby_docker_copy_patch_path` | String | `'/usr/local/share/ruby-docker-copy-patch.rb'` | Path for the Docker copy-file Ruby patch. |
| `manage_ruby_docker_copy_patch` | true, false | `true` | Whether to write the Ruby Docker copy-file patch. |
| `manage_debian_arm_links` | true, false | `true` | Whether to create Debian ARM compatibility links on Debian versions older than 12. |
| `extra_environment` | Hash | `{}` | Additional environment variables for `load-omnibus-toolchain.sh`. Values may be strings or arrays. |
| `remove_packages` | true, false | `false` | Whether `:remove` should remove configured packages. |

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

### Use an externally managed toolchain

```ruby
cinc_omnibus_builder 'default' do
  manage_toolchain false
end
```

### Remove generated files

```ruby
cinc_omnibus_builder 'default' do
  action :remove
end
```
