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

  # Optional pin/rollback: install exact .pkg.tar.zst files (paths or URLs).
  unless new_resource.pinned_packages.empty?
    execute 'install pinned msys2 packages' do
      command msys2_shell("pacman -U --needed --noconfirm #{new_resource.pinned_packages.join(' ')}")
    end
  end

  # Refresh db and install; avoid full `pacman -Syu` (hangs on a runtime
  # restart). Success-only sentinel keeps it idempotent (group queries are
  # unreliable as a guard).
  installed = windows_safe_path_join(new_resource.install_dir, 'etc', '.cinc-packages-installed')
  execute 'install msys2 packages' do
    command msys2_shell("pacman -Sy --needed --noconfirm #{new_resource.packages.join(' ')} && touch /etc/.cinc-packages-installed")
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
