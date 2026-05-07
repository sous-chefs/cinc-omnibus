# Migration Guide

This cookbook has completed a full migration from the legacy default recipe to the
`cinc_omnibus_builder` custom resource.

## What changed

* `recipe[cinc-omnibus::default]` was removed.
* The public API is now the `cinc_omnibus_builder` resource.
* Build-host configuration is now expressed with resource properties instead of recipe internals.

## How to migrate

Legacy pattern:

```ruby
include_recipe 'cinc-omnibus::default'
```

Resource pattern:

```ruby
cinc_omnibus_builder 'default'
```

## Customization

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
