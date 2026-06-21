# cinc_omnibus_gitlab_runner

Installs the [GitLab Runner](https://docs.gitlab.com/runner/) on a **non-Linux** Cinc Omnibus build
host (macOS, FreeBSD, Windows) and manages its service. On Linux it is a no-op — Linux omnibus
builds run in Docker containers and the runner lives on the Docker host, not the build node.

`cinc_omnibus_builder` invokes this resource automatically on non-Linux platforms (unless
`manage_gitlab_runner false`); you normally don't declare it directly.

> **Registration is never automated.** This resource installs the binary and the service but never
> runs `gitlab-runner register` — connecting a runner to a GitLab instance with a registration token
> stays a deliberate manual step. The service runs idle until a runner is registered.

## Actions

| Action | Description |
| --- | --- |
| `:create` | Installs/upgrades the `gitlab-runner` binary, manages the service, and (macOS) re-signs the binary for a durable TCC grant. Default action. |
| `:remove` | Stops/removes the service and (macOS) the helper script. Package removal is opt-in with `remove_package true`. |

## Properties

| Property | Type | Default | Description |
| --- | --- | --- | --- |
| `instance_name` | String | name property | Resource name. |
| `version` | String, nil | `nil` (package default / latest) | Version to pass to the platform package provider. Best-effort on Homebrew (which tracks the latest formula). |
| `manage_service` | true, false | `true` | Whether to set up and start the runner service (macOS LaunchAgent, FreeBSD rc.d, Windows service). |
| `build_user` | String | `'omnibus'` | macOS only: the user whose GUI session the LaunchAgent runs in, and who owns the signing keychain. |
| `build_user_home` | String | platform-specific | Home of `build_user`. |
| `manage_macos_signing` | true, false | `true` | macOS only: re-sign the binary with a fixed self-signed identity so the Automation/TCC grant survives upgrades (see below). |
| `signing_identity` | String | `'Cinc Omnibus GitLab Runner Code Signing'` | macOS only: common name of the self-signed code-signing certificate. |
| `signing_identifier` | String | `'sh.cinc.omnibus.gitlab-runner'` | macOS only: `codesign --identifier` used when re-signing. |
| `signing_keychain` | String | `<home>/Library/Keychains/cinc-omnibus-signing.keychain-db` | macOS only: dedicated keychain holding the signing identity. |
| `signing_keychain_password` | String | `'cinc-omnibus'` | macOS only: password for the signing keychain. Self-signed, locally-trusted only; override per site. |
| `windows_install_dir` | String | `C:\GitLab-Runner` | Windows only: working directory / config location for the service. |
| `remove_package` | true, false | `false` | Whether `:remove` should also uninstall the `gitlab-runner` package. |

## Platform notes

### macOS

* **Install:** `gitlab-runner` via Homebrew (matching the cookbook's existing Homebrew-managed
  macOS handling). `build_user` should own the Homebrew prefix, so that the install, the
  re-signing, and the per-user LaunchAgent all run as the same account.
* **Service:** started with `brew services start gitlab-runner` **as `build_user`, without sudo**,
  so it is a per-user **LaunchAgent** in the build user's GUI (Aqua) session. This is the only mode
  GitLab supports on macOS, and it is required anyway — the omnibus `.dmg` packaging step drives
  Finder via AppleScript, which only works from a GUI session. It is restarted automatically after
  an upgrade. Because the agent loads into the build user's `gui/<uid>` launchd domain, the cookbook
  only (re)starts it when `build_user` owns the console — enable **auto-login** for `build_user` so
  it's logged in across reboots and converges. On a host with no one logged in, the start step is
  skipped (rather than failing the run) and the agent loads at next login.
* **The TCC "control Finder" problem and the fix.** That Finder AppleScript needs the macOS TCC
  **Automation** permission (`gitlab-runner` → Finder). Homebrew ships `gitlab-runner` as a Go
  binary that is ad-hoc signed at build time, so its code-signing identity (cdhash) changes on every
  *version upgrade* — which invalidates the prior TCC grant and forces a manual "Allow" click in the
  GUI after each `brew upgrade gitlab-runner`.

  With `manage_macos_signing true` (default), the resource creates a fixed self-signed code-signing
  identity once (in a dedicated keychain owned by `build_user`) and **re-signs the binary with that
  stable identity after every upgrade**. Because the designated requirement then stays constant, a
  one-time Automation grant persists across all future upgrades.

  **One-time bootstrap (do this once, ever):** after the first converge re-signs the binary, log in
  to the build host's console as `build_user`, run the helper the cookbook drops at
  `~/finder-auth-flow.scpt`, and click **Allow** on the "gitlab-runner wants to control Finder"
  prompt:

  ```sh
  osascript ~/finder-auth-flow.scpt
  ```

  After that, `brew upgrade gitlab-runner` needs no manual intervention.

  > **The grant persists only as long as the signing keychain survives.** It lives in a dedicated
  > keychain owned by `build_user`. If that keychain or identity is lost (re-image, build-user
  > recreation, home wipe), the next converge mints a *new* certificate with a different designated
  > requirement, so the grant is lost and you re-run the one-time `finder-auth-flow.scpt` bootstrap
  > once more. To keep the grant stable across host rebuilds, pre-provision the same identity (import
  > a fixed `.p12`) instead of letting each host generate its own.
  >
  > **Validate the client identity on your hosts first.** macOS attributes the AppleEvent to the
  > *responsible* process; confirm it is `gitlab-runner` (not `/usr/bin/osascript`) by triggering a
  > build and checking the prompt, or:
  > `log show --last 1h --predicate 'subsystem == "com.apple.TCC"' | grep -i appleevents`.
  > If a different binary is named, set `signing_identifier`/`signing_identity` to target it. There
  > is no MDM-free way around the **single** initial Allow click; this approach removes the
  > *per-upgrade* clicks. (With MDM, prefer an `AppleEvents` PPPC profile instead and set
  > `manage_macos_signing false`.)

### FreeBSD

* **Install:** the community port/package `gitlab-runner` (`devel/gitlab-runner`), which also brings
  the rc.d service, the `gitlab-runner` user/group, and runtime deps (bash, git, ca_root_nss). There
  is no GitLab-official FreeBSD package, and **no upstream `freebsd-arm64` binary** — rely on the
  port (built for the host arch) on arm64 hosts.
* **Service:** enabled and started via rc.d (`gitlab_runner`).

### Windows

* **Install:** `chocolatey_package 'gitlab-runner'` (matching the cookbook's existing chocolatey
  usage). The package drops the binary and a PATH shim without creating a service by default.
* **Service:** installed with `gitlab-runner install` under the **Built-in System Account**
  (headless, no password) pointed at `windows_install_dir`, then enabled and started. A Windows
  service is non-interactive (no GUI), which is correct for headless omnibus builds.

## Examples

```ruby
# Managed automatically by cinc_omnibus_builder; equivalent to:
cinc_omnibus_gitlab_runner 'default'

# Install the binary but leave the service and TCC handling alone:
cinc_omnibus_gitlab_runner 'default' do
  manage_service false
  manage_macos_signing false
end
```
