# AGENTS.md

## Cookbook Purpose

Provides the cinc_omnibus_builder resource for configuring Cinc Omnibus build hosts

## Agent Findings

* This cookbook is in an incremental modernization pass. Preserve existing public recipes and attributes unless a later full migration is explicitly selected.
* Dependency management should use `Policyfile.rb`; do not reintroduce Berkshelf.

## Known Limitations

## Package Source

The `cinc_omnibus_builder` resource configures build hosts for Cinc Omnibus projects. It installs
distribution build packages, removes known unsafe package conflicts, and installs the
`omnibus-toolchain` package through `chef_ingredient`.

The toolchain package is fetched unconditionally from the Cinc Project's mirror
(`omnitruck.cinc.sh`) via the Cinc-patched `mixlib-install` gem (sourced from
`https://rubygems.cinc.sh`). The previous Chef Progress (`packages.chef.io`) fallback was removed
when Chef wound down its omnibus pipeline.

## Platform Support

Supported platforms and architectures track the build matrix of the upstream Cinc
[`omnibus-toolchain`](https://gitlab.com/cinc-project/distribution/omnibus-toolchain) project
(see its `CINC_MAINTENANCE_PLAN.md` §2.3 for the source of truth).

### Kitchen coverage

| Suite | Driver | Platforms |
| --- | --- | --- |
| `kitchen.dokken.yml` | docker/dokken | AlmaLinux 8/9/10, Amazon Linux 2023, CentOS Stream 9/10, Debian 12/13, Fedora latest, openSUSE Leap 15, Oracle Linux 8/9, Rocky Linux 8/9/10, Ubuntu 20.04/22.04/24.04/26.04 |
| `kitchen.yml` | vagrant | All of the above plus FreeBSD 14 and Windows Server 2022 for local end-to-end verification |
| `kitchen.exec.yml` | exec (runner) | `macos-latest` and `windows-latest` (GHA-driven); `freebsd-latest` for self-hosted runs |

Cross-architecture coverage (aarch64, ppc64le, s390x, riscv64) is exercised by the toolchain
project's CI; the cookbook's Kitchen suites stay x86_64-only.

The GitHub Actions Windows image already ships Docker (installed by Microsoft's
`install-docker-ce.ps1`, not Chocolatey) with the Containers feature enabled, so the exec suite
exercises the adopt-existing-docker path and never triggers the feature-install reboot. It also
ships the Hyper-V feature, so the test recipe sets `allow_hyperv true` (the guard is unit-tested
and InSpec asserts process isolation instead) and `reboot_after_feature_install false`: Kitchen
runs on the host under the exec driver, so a reboot would kill the job. The full fresh-host path (feature install, reboot gate,
choco `docker-engine`, runner service) is a manual run of the same exec suite on an OpenStack
`Windows 2022 Server` VM; TESTING.md has the walkthrough. kitchen-openstack has no WinRM support,
so the VM cannot be driven from a workstation.

## Build dependencies installed

| Platform Family | Source |
| --- | --- |
| Debian / Ubuntu | Distribution packages + `omnibus-toolchain` |
| RHEL family / Amazon / Fedora | Distribution packages + `omnibus-toolchain` |
| SUSE | Distribution packages + `omnibus-toolchain` |
| macOS | Homebrew formulae + `omnibus-toolchain` `.pkg` |
| FreeBSD | `pkg` packages + `omnibus-toolchain` self-extracting `.sh` |
| Windows | None on the host: the `cincproject/omnibus-windows` image carries MSYS2, the toolchain and the build tools |

## Windows: Docker host, not builder

Since 5.0 the Windows arm of `cinc_omnibus_builder` prepares a Windows Server 2022+ **Docker host**
through `cinc_omnibus_docker_host` (documentation/cinc_omnibus_docker_host.md): Containers feature
(reboot requested at end of run), Hyper-V must be absent (process isolation), Defender exclusions +
real-time off (feature removal opt-in), Chocolatey `docker-engine`, `daemon.json` only when
`docker_data_root`/`docker_daemon_config` are set. The pet-builder path (`cinc_omnibus_msys2`, the
choco build tools, the toolchain MSI, `load-omnibus-toolchain.ps1`) was removed; its equivalent is
the Dockerfile in the docker-images repository (`omnibus-windows/`).

Chef's `windows_defender` resource maps `realtime_protection` to `DisableIOAVProtection` (not
`DisableRealtimeMonitoring`) and `windows_defender_exclusion` does not quote paths with spaces, so
the resource calls `Set-MpPreference`/`Add-MpPreference` directly. Tamper Protection silently
ignores `Set-MpPreference`; the resource warns and skips rather than re-running every converge.

On FreeBSD the cookbook links `/usr/local/openssl/cert.pem` (the ports OpenSSL's `OPENSSLDIR`, which
`ca_root_nss` leaves empty) to the `ca_root_nss` bundle, so RVM-built rubies can verify TLS.

On macOS the cookbook also creates compatibility symlinks in `/usr/local/bin` so that the
canonical autotools names resolve against Homebrew's renamed binaries: `libtoolize` →
`glibtoolize` always, and on Apple Silicon also `pkg-config` → Homebrew's `pkg-config` shim
(which lives outside `/usr/local/bin` when Homebrew is in `/opt/homebrew`), plus `git` for the
same reason.

That `git` link is load-bearing, not cosmetic. Builds run `sudo -E bundle exec omnibus build`, so
git runs as root over a build-user-owned checkout and rejects it unless the path is a
`safe.directory`. The cookbook writes those entries into the managed `.gitconfig` (build user, and
root's on macOS) as `<build_user_home>/builds/*`, which keeps the runner-specific token out of the
value — but a trailing `/*` needs git 2.46+, and Apple's `/usr/bin/git` is 2.32.1, old enough to
predate both that and the `SUDO_UID` bypass git 2.36 added. Intel picks up Homebrew's git from
`/usr/local/bin` by accident of the prefix; Apple Silicon needs the link, and without it `git
describe` fails and packages version as `0.0.0` without failing the job.

## GitLab Runner

On non-Linux builders (macOS, FreeBSD, Windows) the cookbook installs and manages the GitLab Runner
via [`cinc_omnibus_gitlab_runner`](documentation/cinc_omnibus_gitlab_runner.md) (`manage_gitlab_runner`,
default true). It never runs `gitlab-runner register` — registration stays manual. On Linux it is a
no-op, since Linux omnibus builds run in Docker and the runner lives on the Docker host. On Windows
the service runs as LocalSystem (which the docker named pipe grants by default) and serves two
hand-registered runners: a `shell` one that builds the image and a `docker-windows` one for product
builds.

On macOS the runner's omnibus `.dmg` step drives Finder via AppleScript, which needs the TCC
*Automation* permission. Because Homebrew's `gitlab-runner` is ad-hoc signed and its identity changes
on every version upgrade, that grant is normally lost on each `brew upgrade`. The cookbook re-signs
the binary with a fixed self-signed identity so the grant persists; this still requires a **single**
manual "Allow" click the first time (there is no MDM-free way to avoid that one prompt). See the
resource docs for the one-time bootstrap and how to validate the AppleEvents client on your hosts.

## Source / Compiled Installation

This cookbook prepares a build host; it does not compile Cinc or Omnibus projects itself.

## Known Issues

* The integration test verifies host preparation, toolchain install, and the load shim; it does
  not build a full Cinc artifact.
* The resource writes `/usr/local/share/ruby-docker-copy-patch.rb` on Linux to preserve the
  copy-file syscall workaround for Linux kernels 5.6–5.10 (no-op on macOS/FreeBSD/Windows).
* On Windows, Defender path exclusions do not reach a running container's writable layer (a mounted
  VHDX); `defender_process_exclusions` or `remove_defender` are the levers, neither measured yet.
