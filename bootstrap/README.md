# Bootstrap

One-shot scripts that turn a fresh node into a Cinc Omnibus build host. They install Cinc Client
via the Cinc omnitruck, download `cinc-omnibus` + `chef-ingredient` from GitHub, converge the
`cinc_omnibus_builder` resource against the local node, then uninstall Cinc Client and remove
the scratch workspace. The toolchain itself (`/opt/omnibus-toolchain` or
`C:\cinc-project\omnibus-toolchain`) stays installed — that's the point.

## Layout

```text
bootstrap/
├── client.rb                          # Cinc Zero config — Unix paths
├── client.windows.rb                  # Cinc Zero config — Windows paths
├── install.sh                         # Linux + macOS + FreeBSD bootstrap
├── install.ps1                        # Windows bootstrap
├── cookbooks/cinc-omnibus-bootstrap/  # thin wrapper cookbook invoking the resource
└── runlist/builder.json               # run_list: [recipe[cinc-omnibus-bootstrap::default]]
```

The wrapper cookbook exists because `cinc-omnibus` itself is resource-only (no
`recipe[cinc-omnibus::default]` since v2). The run_list needs *some* recipe, so we ship a
one-line cookbook that calls `cinc_omnibus_builder 'default'`.

## Usage

### Linux (Debian/Ubuntu, RHEL/Amazon/Fedora), macOS, and FreeBSD

```sh
curl -L https://raw.githubusercontent.com/sous-chefs/cinc-omnibus/main/bootstrap/install.sh | sudo sh
```

The script is POSIX (`#!/bin/sh`) so it runs against `dash` / `ash` / `sh` on any of those
platforms — no bash required to launch it. The Cinc omnitruck install step does pipe through
`bash`, so on FreeBSD the script does `pkg install -y bash` as a prerequisite (macOS ships bash;
all Linux distros ship bash).

### Windows (Server 2016+)

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
. { Invoke-WebRequest -UseBasicParsing -Uri https://raw.githubusercontent.com/sous-chefs/cinc-omnibus/main/bootstrap/install.ps1 } | Invoke-Expression
```

> On Windows Server 2016 / Windows PowerShell 5.1, the `SecurityProtocol` line is required: the
> default .NET protocols can omit TLS 1.2, which GitHub requires, and the download fails with
> *"Could not create SSL/TLS secure channel."* The script sets TLS 1.2 internally for its own
> subsequent calls, but this first fetch happens before the script runs.

## Environment overrides

Both scripts accept the same two env vars to point at non-`main` branches (useful for testing
a PR before merge):

| Variable | Default | Purpose |
| --- | --- | --- |
| `REPO_BRANCH` | `main` | Branch/tag of `sous-chefs/cinc-omnibus` |
| `CHEF_INGREDIENT_BRANCH` | `main` | Branch/tag of `chef-cookbooks/chef-ingredient` |

Linux/macOS/FreeBSD:

```sh
REPO_BRANCH=feat/cinc-toolchain-migration sudo -E sh install.sh
```

Windows:

```powershell
$env:REPO_BRANCH = 'feat/cinc-toolchain-migration'
.\install.ps1
```

## What the script does

1. Installs Cinc Client via `https://omnitruck.cinc.sh/install.{sh,ps1}` if it isn't present.
2. Downloads `cinc-omnibus` and `chef-ingredient` as zips from GitHub (no berkshelf — keeps the
   bootstrap dependency-free and avoids needing native-extension build tooling).
3. Unpacks both into a scratch `cookbook_path` (`/tmp/cinc/cookbooks` on Unix,
   `C:\cinc\cookbooks` on Windows) alongside the local wrapper cookbook.
4. Runs `cinc-client --local-mode` with the wrapper cookbook in the run_list. The wrapper invokes
   `cinc_omnibus_builder 'default'`, which installs build deps, the omnibus toolchain, the build
   user, and the load shim.
5. Uninstalls Cinc Client and removes the scratch workspace. The build node no longer needs Cinc
   to run omnibus builds — those use `omnibus-toolchain`'s own Ruby.

## macOS: build user and SecureToken

On macOS the `user` resource that creates the build user (`omnibus` by default) runs through Chef's
`mac_user` provider, which always manages the account's **SecureToken**. Chef demands
`secure_token_password`, `admin_username`, and `admin_password` whenever it has to *change* the
token (desired state ≠ current state):

```text
Chef::Exceptions::User: secure_token_password, admin_username and admin_password
properties are required to modify SecureToken
```

A build user created from scratch by the bootstrap has no SecureToken, so historically this only
bit when the user *already existed with one* — e.g. created by hand in System Settings, or granted a
token by logging into the GUI (macOS auto-grants a token to the first interactive login on a Mac
that has none).

`cinc_omnibus_builder` handles this automatically: before creating the build user it reads the
account's current SecureToken state (`sysadminctl -secureTokenStatus`) and declares that *same*
state on the `user` resource. Because desired always matches current, `mac_user` never tries to
toggle the token and never needs credentials — whether the user has a token or not, and even if the
token gets auto-granted between runs. No configuration is required.

SecureToken is a FileVault disk-encryption credential (and, on Apple Silicon, confers volume-owner
status); it is **not** required for ordinary GUI login, screen sharing, SSH, or code signing, and
with FileVault off it has no practical effect. The cookbook neither grants nor removes it — it only
avoids fighting whatever state the account is already in.
