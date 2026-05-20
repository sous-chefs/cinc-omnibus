# cinc-omnibus Cookbook

[![Cookbook Version](https://img.shields.io/cookbook/v/selnux.svg)](https://supermarket.chef.io/cookbooks/cinc-omnibus)
[![CI State](https://github.com/sous-chefs/cinc-omnibus/workflows/ci/badge.svg)](https://github.com/sous-chefs/cinc-omnibus/actions?query=workflow%3Aci)
[![OpenCollective](https://opencollective.com/sous-chefs/backers/badge.svg)](#backers)
[![OpenCollective](https://opencollective.com/sous-chefs/sponsors/badge.svg)](#sponsors)
[![License](https://img.shields.io/badge/License-Apache%202.0-green.svg)](https://opensource.org/licenses/Apache-2.0)

## Description

The Cinc Omnibus cookbook provides the tools to build various Cinc projects. This cookbook was originally modeled after
the omnibus cookbook.

This major release removes `recipe[cinc-omnibus::default]`. Use the `cinc_omnibus_builder` resource instead. See [migration.md](migration.md) before upgrading from a recipe-based release.

## Requirements

* Chef 16 or higher

## Platform

* AlmaLinux 8+
* Amazon Linux 2023
* CentOS Stream 9+
* Debian 12+
* Fedora
* Oracle Linux 8+
* Red Hat Enterprise Linux 8+
* Rocky Linux 8+
* SUSE Linux Enterprise
* Ubuntu 22.04+

Current Kitchen verification in this migration branch covers AlmaLinux 8, AlmaLinux 9, AlmaLinux 10, Amazon Linux 2023, CentOS Stream 9, CentOS Stream 10, Debian 12, Debian 13, Fedora latest, Oracle Linux 8, Oracle Linux 9, Rocky Linux 8, Rocky Linux 9, Rocky Linux 10, Ubuntu 22.04, and Ubuntu 24.04.

## Resources

Resource documentation:

* [cinc_omnibus_builder](documentation/cinc_omnibus_builder.md)

### `cinc_omnibus_builder`

Configures a build host for Cinc Omnibus projects.

```ruby
cinc_omnibus_builder 'default'
```

The resource installs platform build dependencies, installs `omnibus-toolchain`, creates the `omnibus` user and cache directory, writes a Git configuration, and writes `load-omnibus-toolchain.sh`.

## Maintainers

This cookbook is maintained by the Sous Chefs. The Sous Chefs are a community of Chef cookbook maintainers working together to maintain important cookbooks. If you’d like to know more please visit [sous-chefs.org](https://sous-chefs.org/) or come chat with us on the Chef Community Slack in [#sous-chefs](https://chefcommunity.slack.com/messages/C2V7B88SF).

## Contributors

This project exists thanks to all the people who [contribute.](https://opencollective.com/sous-chefs/contributors.svg?width=890&button=false)

### Backers

Thank you to all our backers!

![https://opencollective.com/sous-chefs#backers](https://opencollective.com/sous-chefs/backers.svg?width=600&avatarHeight=40)

### Sponsors

Support this project by becoming a sponsor. Your logo will show up here with a link to your website.

![https://opencollective.com/sous-chefs/sponsor/0/website](https://opencollective.com/sous-chefs/sponsor/0/avatar.svg?avatarHeight=100)
![https://opencollective.com/sous-chefs/sponsor/1/website](https://opencollective.com/sous-chefs/sponsor/1/avatar.svg?avatarHeight=100)
![https://opencollective.com/sous-chefs/sponsor/2/website](https://opencollective.com/sous-chefs/sponsor/2/avatar.svg?avatarHeight=100)
![https://opencollective.com/sous-chefs/sponsor/3/website](https://opencollective.com/sous-chefs/sponsor/3/avatar.svg?avatarHeight=100)
![https://opencollective.com/sous-chefs/sponsor/4/website](https://opencollective.com/sous-chefs/sponsor/4/avatar.svg?avatarHeight=100)
![https://opencollective.com/sous-chefs/sponsor/5/website](https://opencollective.com/sous-chefs/sponsor/5/avatar.svg?avatarHeight=100)
![https://opencollective.com/sous-chefs/sponsor/6/website](https://opencollective.com/sous-chefs/sponsor/6/avatar.svg?avatarHeight=100)
![https://opencollective.com/sous-chefs/sponsor/7/website](https://opencollective.com/sous-chefs/sponsor/7/avatar.svg?avatarHeight=100)
![https://opencollective.com/sous-chefs/sponsor/8/website](https://opencollective.com/sous-chefs/sponsor/8/avatar.svg?avatarHeight=100)
![https://opencollective.com/sous-chefs/sponsor/9/website](https://opencollective.com/sous-chefs/sponsor/9/avatar.svg?avatarHeight=100)
