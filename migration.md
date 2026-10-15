# Migration Guide

## Migrating from 4.x to 5.x

The 5.0 major release moves Windows omnibus builds into containers: the builds run in the
`cincproject/omnibus-windows` image (docker-images repository), and a Windows node converged with
this cookbook is now a **Docker host** (Windows Server 2022+, process isolation), not a builder. The
breaking changes are:

* **`cinc_omnibus_msys2` resource removed**, along with the vendored MSYS2 signing key. MSYS2 is
  provisioned by the image's Dockerfile with the same package set, verification and `IgnorePkg`
  freeze. Wrappers that declared the resource or set `manage_msys2` / `msys2_*` on
  `cinc_omnibus_builder` must drop them.
* **`cinc_omnibus_builder` on Windows no longer installs anything build-related.** No Chocolatey
  build tools (Git, 7-Zip, WiX, Windows SDK 8.1), no `omnibus-toolchain` MSI, no
  `C:\omnibus\load-omnibus-toolchain.ps1`, no `.gitconfig`, no `C:\omnibus\cache`. It now invokes
  the new [`cinc_omnibus_docker_host`](documentation/cinc_omnibus_docker_host.md) resource (Containers
  feature, Defender, `docker-engine`) and `cinc_omnibus_gitlab_runner`. Existing pet builders are
  not migrated in place: re-image the host and register a `docker-windows` runner.
* **Windows-specific defaults dropped.** `build_user_home`, `cache_dir`, `toolchain_install_dir`
  and `build_user_shell` no longer have Windows values; `git_safe_directories` no longer special-cases
  Windows. `extra_environment` has no effect on Windows (set `ENV` in the image instead).
* **A Windows converge may request a reboot.** Installing the Containers feature (and removing
  Defender, if `remove_defender true`) ends the run with a reboot request; the next converge starts
  Docker. Set `reboot_after_feature_install false` to only warn.
* **Hyper-V fails the converge** on Windows unless `allow_hyperv true`.

The Linux, macOS and FreeBSD behaviour is unchanged.

## Migrating from 2.x to 3.x

The 3.0 major release flips the toolchain source to the independent Cinc fork and adds first-class
support for macOS, FreeBSD, and Windows. The breaking changes are:

* **`cinc_omnibus?` helper removed.** Wrapper cookbooks that referenced it must drop the call.
  Every platform now sources `omnibus-toolchain` from the Cinc mirror unconditionally; there is
  no Chef Progress fallback.
* **`manage_toolchain` property removed.** The Cinc-built toolchain is now the only install path
  for this resource. Wrappers that previously set `manage_toolchain false` should remove that
  property; if you need to skip the toolchain install entirely, do not call the resource.
* **Windows default `toolchain_install_dir` changed.** It moved from
  `C:\opscode\omnibus-toolchain` to `C:\cinc-project\omnibus-toolchain` to match the Cinc-built
  MSI. Operators or wrappers pinning the old path must update.
* **`/var/cache/omnibus` default replaced with a platform-aware lazy default.** The new default
  is `/var/cache/omnibus` on Unix and `C:\omnibus\cache` on Windows. Wrappers that explicitly set
  `cache_dir` are unaffected.
* **`omnibus_pkgconfig_files` now derives from `toolchain_install_dir`.** Wrappers that override
  `toolchain_install_dir` no longer try to delete stale `/opt/omnibus-toolchain` paths.

## Migrating from 1.x to 2.x

The 2.0 release completed a full migration from the legacy default recipe to the
`cinc_omnibus_builder` custom resource.

### What changed

* `recipe[cinc-omnibus::default]` was removed.
* The public API is the `cinc_omnibus_builder` resource.
* Build-host configuration is expressed with resource properties instead of recipe internals.

### How to migrate

Legacy pattern:

```ruby
include_recipe 'cinc-omnibus::default'
```

Resource pattern:

```ruby
cinc_omnibus_builder 'default'
```

### Customization

The old recipe had no public node attributes. If a wrapper cookbook previously depended on recipe
internals, move that configuration to explicit resource properties:

```ruby
cinc_omnibus_builder 'default' do
  toolchain_version 'latest'
  toolchain_channel :stable
  extra_environment(
    'BUNDLE_WITHOUT' => 'development'
  )
end
```

The cookbook's default Kitchen suite shows the supported resource-first pattern in
`test/cookbooks/test/recipes/default.rb`.
