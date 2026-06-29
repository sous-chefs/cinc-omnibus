# frozen_string_literal: true

provides :cinc_omnibus_msys2
unified_mode true

include CincOmnibus::Cookbook::Helpers

property :instance_name, String, name_property: true
property :install_dir, String, default: lazy { windows_msys2_install_dir }
property :base_archive_date, String, default: lazy { msys2_latest_base_archive_date }
property :base_archive_url, String, default: lazy { msys2_default_base_archive_url(base_archive_date) }
property :verify_signature, [true, false], default: true
property :signing_key_fingerprint, String, default: lazy { msys2_signing_key_fingerprint }
property :gpg_path, String, default: lazy { windows_safe_path_join(windows_system_drive, 'Program Files', 'Git', 'usr', 'bin', 'gpg.exe') }
property :msystem, String, default: 'UCRT64'
property :packages, Array, default: lazy { msys2_default_packages }
property :ignore_packages, Array, default: lazy { msys2_default_ignore_packages }
property :pinned_packages, Array, default: []

default_action :install

action_class do
  include CincOmnibus::Cookbook::Helpers
end

action :install do
  archive_path = ::File.join(Chef::Config[:file_cache_path], 'msys2-base-x86_64.sfx.exe')
  sig_path = "#{archive_path}.sig"

  # No checksum is published, only a GPG signature: import the key and fetch
  # the detached .sig to verify before extracting.
  if new_resource.verify_signature
    directory msys2_gpg_home do
      recursive true
    end

    cookbook_file msys2_signing_key_path do
      source 'msys2-signing-key.asc'
      cookbook 'cinc-omnibus' # not the wrapper that declares the resource
    end

    execute 'import msys2 signing key' do
      command msys2_gpg_cmd(%(--import "#{to_msys_path(msys2_signing_key_path)}"))
      not_if msys2_gpg_cmd("--list-keys #{new_resource.signing_key_fingerprint}")
    end

    remote_file sig_path do
      source "#{new_resource.base_archive_url}.sig"
      not_if { ::File.exist?(msys2_bash_exe) }
    end
  end

  # Download the base. Skipped once bash.exe exists.
  remote_file archive_path do
    source new_resource.base_archive_url
    not_if { ::File.exist?(msys2_bash_exe) }
  end

  # Verify before extracting; a non-zero gpg exit aborts the run.
  if new_resource.verify_signature
    execute 'verify msys2 base signature' do
      command msys2_gpg_cmd(%(--verify "#{to_msys_path(sig_path)}" "#{to_msys_path(archive_path)}"))
      not_if { ::File.exist?(msys2_bash_exe) }
    end
  end

  # The sfx self-extracts its msys64/ tree (carries its own zstd decoder).
  execute 'extract msys2 base' do
    command %("#{archive_path}" -y -o"#{msys2_extract_parent}")
    creates msys2_bash_exe
  end

  # First login shell run executes /etc/post-install; sentinel keeps it once.
  initialized = windows_safe_path_join(new_resource.install_dir, 'etc', '.cinc-initialized')
  execute 'initialize msys2' do
    command msys2_shell('true && touch /etc/.cinc-initialized')
    creates initialized
  end

  installed = windows_safe_path_join(new_resource.install_dir, 'etc', '.cinc-packages-installed')

  # Full `-Syuu` first: rolling-release MSYS2 only supports full upgrades, and
  # `pacman -Sy <pkg>` partial-upgrades, linking new packages (wget) against
  # sonames the old deps (nettle) no longer ship. Per MSYS2 CI guidance run it
  # twice (core then the rest), reaping leftover runtime processes between.
  # Redirect output so a keyring hook's dirmngr/gpg-agent can't hold Chef's pipe
  # and hang (see the gpg reaper below); clear a stale db.lck from a killed pass.
  # Guarded (with everything below) by the install sentinel, so it runs once.
  upgrade_log = '/tmp/cinc-msys2-upgrade.log'
  2.times do |pass|
    execute "upgrade msys2 base (pass #{pass + 1})" do
      command msys2_shell(%(rm -f /var/lib/pacman/db.lck; pacman -Syuu --noconfirm --overwrite "*" > #{upgrade_log} 2>&1))
      timeout 900
      ignore_failure true # a runtime swap can kill or hang this pass
      not_if { ::File.exist?(installed) }
    end

    execute "reap msys2 runtime processes (pass #{pass + 1})" do
      command 'taskkill /F /FI "MODULES eq msys-2.0.dll"'
      returns [0, 128] # 128 = nothing matched
      not_if { ::File.exist?(installed) }
    end
  end

  # Optional pin/rollback: install exact .pkg.tar.zst files (paths or URLs)
  # before the live install so the freeze below keeps them in place.
  unless new_resource.pinned_packages.empty?
    execute 'install pinned msys2 packages' do
      command msys2_shell("pacman -U --needed --noconfirm #{new_resource.pinned_packages.join(' ')}")
      not_if { ::File.exist?(installed) }
    end
  end

  # Install the build deps from the db the upgrade just synced (no -y: reuse the
  # consistent snapshot). Success-only sentinel keeps it idempotent (group
  # queries are unreliable as a guard).
  execute 'install msys2 packages' do
    command msys2_shell("pacman -S --needed --noconfirm #{new_resource.packages.join(' ')} && touch /etc/.cinc-packages-installed")
    creates installed
  end

  # Freeze the compiler against `pacman -Syu`. Must run AFTER install:
  # IgnorePkg + --noconfirm would otherwise skip the first gcc install too.
  ruby_block 'set msys2 IgnorePkg' do
    block do
      conf = msys2_pacman_conf
      lines = ::File.readlines(conf)
      desired = "#{msys2_ignore_pkg_line}\n"
      idx = lines.index { |l| l =~ /^\s*#?\s*IgnorePkg\s*=/ }
      if idx
        lines[idx] = desired
      else
        opt = lines.index { |l| l =~ /^\[options\]/ }
        lines.insert((opt || -1) + 1, desired)
      end
      ::File.write(conf, lines.join)
    end
    only_if { ::File.exist?(msys2_pacman_conf) }
    not_if { ::File.exist?(msys2_pacman_conf) && ::File.read(msys2_pacman_conf).include?(msys2_ignore_pkg_line) }
  end

  # gpg-agent/dirmngr inherit Chef's stdout handle and hold the pipe open,
  # hanging the converge until it times out. Reap them. 128 = nothing to kill.
  execute 'stop msys2 gpg daemons' do
    command 'taskkill /F /T /IM gpg-agent.exe /IM dirmngr.exe'
    returns [0, 128]
    only_if { msys2_gpg_daemons_running? }
  end
end

action :remove do
  directory new_resource.install_dir do
    recursive true
    action :delete
  end
end
