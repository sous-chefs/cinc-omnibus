# cinc_omnibus_msys2

Installs and manages MSYS2 on Windows Omnibus builders: downloads the MSYS2 base, provisions the
UCRT64 build toolchain with pacman, and freezes the compiler so upgrades are deliberate rather
than implicit. Called automatically by [`cinc_omnibus_builder`](cinc_omnibus_builder.md) on
Windows (unless `manage_msys2 false`), but it can also be used directly.

This resource is Windows-only.

The default `packages` mirror the Linux Omnibus build dependencies, mapped to UCRT64: the
`base-devel` and `mingw-w64-ucrt-x86_64-toolchain` groups (autotools, make, gcc, binutils,
pkgconf), the host tools `bzip2`, `ca-certificates`, `git`, `gnupg`, `openssh`, `rsync`, `wget`,
and the dev libraries `mingw-w64-ucrt-x86_64-{libffi,ncurses,openssl,zlib}`. OpenJDK is omitted
(server builds only, which we don't do on Windows).

## Actions

| Action | Description |
| --- | --- |
| `:install` | Downloads the MSYS2 base `.sfx.exe`, verifies its GPG signature, self-extracts it, runs first-time initialization, installs any `pinned_packages`, installs `packages`, then writes the `IgnorePkg` freeze to `pacman.conf`. The freeze is written *after* the install because `IgnorePkg` would otherwise make pacman skip the very first install of those packages. This is the default action. |
| `:remove` | Deletes the MSYS2 install directory. |

## Properties

| Property | Type | Default | Description |
| --- | --- | --- | --- |
| `instance_name` | String | name property | Resource name. |
| `install_dir` | String | `C:\msys64` | MSYS2 install directory. The base archive always unpacks a `msys64` folder, so a non-`msys64` basename is not supported. |
| `base_archive_date` | String | newest on the mirror | Date of the dated MSYS2 base archive on `repo.msys2.org/distrib`. Defaults to the newest archive found by scanning the mirror listing (falling back to a pinned date if it can't be reached). Set explicitly to pin. |
| `base_archive_url` | String | derived from `base_archive_date` | URL of the MSYS2 base self-extracting archive. Defaults to `https://repo.msys2.org/distrib/x86_64/msys2-base-x86_64-<date>.sfx.exe`. |
| `verify_signature` | true, false | `true` | Verify the archive's detached GPG signature against the vendored MSYS2 signing key before extraction. |
| `signing_key_fingerprint` | String | Christoph Reiter's key | Fingerprint expected in the keyring for verification. |
| `gpg_path` | String | Git for Windows `gpg.exe` | Path to the `gpg` binary used for verification (Git for Windows ships one, installed by `cinc_omnibus_builder`). |
| `msystem` | String | `'UCRT64'` | MSYS2 subsystem used for the shell environment. |
| `packages` | Array | UCRT64 build deps (see below) | Pacman packages or groups to install (`pacman -S --needed`). |
| `ignore_packages` | Array | `mingw-w64-ucrt-x86_64-gcc`, `…-gcc-libs`, `…-binutils` | Packages written to `IgnorePkg` in `pacman.conf` so `pacman -Syu` will not upgrade them. |
| `pinned_packages` | Array | `[]` | Exact `.pkg.tar.zst` files (local paths or URLs) installed with `pacman -U --needed` before `packages`. |

## Signature verification

MSYS2 publishes no checksum for the base archive, only a detached GPG signature, and that
signature exists **only for the dated archives** on `repo.msys2.org/distrib` (the GitHub "latest"
alias has no `.sig`). So the source is a dated archive — by default the newest one found by
scanning the mirror listing — and the download is verified against the MSYS2 signing key
(Christoph Reiter, fingerprint `0EBF782C5D53F7E5FB02A66746BD761F7A49B0EC`) before it is extracted.

The public key is vendored at `files/default/msys2-signing-key.asc`. Verification imports it into a
dedicated keyring and runs `gpg --verify` on the downloaded archive via `remote_file`'s `verify`
property, which fails the converge on a bad signature. `gpg` comes from Git for Windows, installed
by `cinc_omnibus_builder`. Set `verify_signature false` to skip (not recommended).

## How gcc is controlled

The MSYS2 base archive contains only the MSYS2 runtime — **never gcc**. The ucrt64 compiler is
always fetched live by pacman, so a fresh builder gets whatever version the mirror ships *now*.
Control comes from two levers:

1. **Freeze (`ignore_packages` → `IgnorePkg`).** After the toolchain installs, gcc/binutils are
   added to `IgnorePkg` in `pacman.conf`. A routine `pacman -Syu` then holds them back, so the
   compiler never moves out from under a build. Upgrading becomes a deliberate change: lift the
   freeze (edit `ignore_packages`) and re-converge.

2. **Pin/rollback (`pinned_packages`).** To reproduce or roll back to an exact compiler across
   fresh builders, host the specific `.pkg.tar.zst` files (these usually already exist in
   `C:\msys64\var\cache\pacman\pkg` on a working builder) and pass them here. They are installed
   with `pacman -U` before the live `pacman -S`, and the freeze keeps them in place.

## Examples

### Default (managed by the builder)

```ruby
cinc_omnibus_builder 'default'
```

### Use the resource directly

```ruby
cinc_omnibus_msys2 'default'
```

### Pin a known-good gcc

```ruby
cinc_omnibus_msys2 'default' do
  pinned_packages %w(
    https://builders.example.com/msys2/mingw-w64-ucrt-x86_64-gcc-14.2.0-3-any.pkg.tar.zst
    https://builders.example.com/msys2/mingw-w64-ucrt-x86_64-gcc-libs-14.2.0-3-any.pkg.tar.zst
    https://builders.example.com/msys2/mingw-w64-ucrt-x86_64-binutils-2.45-2-any.pkg.tar.zst
  )
end
```
