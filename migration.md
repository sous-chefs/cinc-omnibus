# Migration Guide

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
