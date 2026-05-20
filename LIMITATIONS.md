# Limitations

## Package Availability

The `cinc_omnibus_builder` resource configures build hosts for Cinc Omnibus projects. It installs
distribution build packages, removes known unsafe package conflicts, and installs the
`omnibus-toolchain` package through `chef_ingredient`.

### Cinc packages

Cinc publishes install scripts and plain packages for Cinc Client, Auditor, Server, and Workstation.
The Cinc download page states that packages are available on the Cinc download site, while standard
package-manager repositories such as APT and Yum are not currently provided.

### Chef/Cinc platform baseline

This cookbook uses Chef/Cinc omnibus packages through `chef_ingredient`, so its realistic platform
support follows the Chef Infra Client and Chef Workstation platform families that still receive
current packages.

Current non-EOL Kitchen coverage in this migration branch includes:

* AlmaLinux 8, 9, and 10
* Amazon Linux 2023
* CentOS Stream 9 and 10
* Debian 12 and 13
* Fedora latest
* Oracle Linux 8 and 9
* Rocky Linux 8, 9, and 10
* Ubuntu 22.04 and 24.04

SUSE Linux Enterprise support remains declared through the `suse` platform helper path, but there is
no public Dokken SLES image in the local matrix. The old openSUSE Leap 15 Kitchen target was removed
because Leap 15.6 reached EOL on April 30, 2026.

## Architecture Limitations

The resource preserves the legacy Cinc rubygems fallback for platforms where upstream Chef packages
do not publish some architectures:

* Enterprise Linux 9 on `ppc64le` and `s390x`
* Enterprise Linux 10 and newer
* Debian and Ubuntu on `ppc64le`
* `riscv64`

The `omnibus-toolchain` package was not available from Chef's package endpoint for the Linux
package paths checked during this migration, including local `arm64` paths and GitHub Actions
`x86_64` EL paths. The test cookbook disables toolchain installation while keeping the resource
default as `manage_toolchain true`; ChefSpec verifies the default `chef_ingredient` declaration.

## Source/Compiled Installation

This cookbook prepares a build host; it does not compile Cinc or Omnibus projects itself.

### Build Dependencies

| Platform Family | Package Source |
| --- | --- |
| Debian/Ubuntu | Distribution packages plus `omnibus-toolchain` |
| RHEL family/Amazon/Fedora | Distribution packages plus `omnibus-toolchain` |
| SUSE | Distribution packages plus `omnibus-toolchain` |

## Known Issues

* A single-node Kitchen suite verifies host preparation and the toolchain script, but it does not
  build a full Cinc artifact.
* The resource still writes `/usr/local/share/ruby-docker-copy-patch.rb` to preserve the previous
  Docker copy-file patch behavior.
