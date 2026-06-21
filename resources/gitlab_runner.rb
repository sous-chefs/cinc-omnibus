# frozen_string_literal: true

require 'shellwords'

provides :cinc_omnibus_gitlab_runner
unified_mode true

include CincOmnibus::Cookbook::Helpers

property :instance_name, String, name_property: true
property :version, [String, nil]
property :manage_service, [true, false], default: true
property :build_user, String, default: 'omnibus'
property :build_user_home, String, default: lazy { default_build_user_home }

# macOS code-signing: re-sign the Homebrew binary with a fixed self-signed
# identity so its TCC "Automation" (control Finder) grant survives upgrades.
property :manage_macos_signing, [true, false], default: true
property :signing_identity, String, default: 'Cinc Omnibus GitLab Runner Code Signing'
property :signing_identifier, String, default: 'sh.cinc.omnibus.gitlab-runner'
property :signing_keychain, String,
         default: lazy { ::File.join(build_user_home, 'Library', 'Keychains', 'cinc-omnibus-signing.keychain-db') }
property :signing_keychain_password, String, default: 'cinc-omnibus', sensitive: true

property :windows_install_dir, String,
         default: lazy { windows_safe_path_join(windows_system_drive, 'GitLab-Runner') }

property :remove_package, [true, false], default: false

default_action :create

action_class do
  include CincOmnibus::Cookbook::Helpers
end

# Registration (`gitlab-runner register`) is intentionally never performed here;
# it stays a manual step. The service runs idle until a runner is registered.
action :create do
  # On Linux the runner lives on the Docker host, not the build node.
  next if linux?

  if mac_os_x?
    build_user = new_resource.build_user
    build_env = gitlab_runner_build_env

    package 'gitlab-runner' do
      version new_resource.version if new_resource.version
    end

    if new_resource.manage_macos_signing
      keychain = new_resource.signing_keychain
      signing_script = gitlab_runner_signing_keychain_script
      resign_command = gitlab_runner_resign_command

      directory ::File.dirname(keychain) do
        owner build_user
        recursive true
      end

      # Create the dedicated signing keychain + a single stable self-signed
      # code-signing identity. Self-heals 0/2+ identity states (see helper).
      bash 'create gitlab-runner signing identity' do
        user build_user
        environment build_env
        sensitive true
        code signing_script
        not_if { gitlab_runner_signing_identity_ready? }
      end

      # codesign discovers the identity through the user keychain search list
      # (the --keychain flag alone is unreliable). Separate + idempotent so it
      # also repairs hosts whose identity already exists. build_user's home has
      # no spaces, so the unquoted rebuild of the existing list is safe.
      execute 'add gitlab-runner signing keychain to search list' do
        command "security list-keychains -d user -s #{Shellwords.escape(keychain)} " \
                "$(security list-keychains -d user | tr -d '\"')"
        user build_user
        environment build_env
        not_if { gitlab_runner_keychain_in_search_list? }
      end

      # Re-sign with the stable identity; idempotent, so it re-runs after every
      # `brew upgrade` (which replaces the binary).
      execute 'resign gitlab-runner' do
        command resign_command
        user build_user
        environment build_env
        sensitive true
        not_if { gitlab_runner_binary_signed? }
        notifies :run, 'execute[restart gitlab-runner service]', :immediately if new_resource.manage_service
      end

      # One-time TCC grant helper (replaces the standalone finder-auth-flow repo).
      cookbook_file ::File.join(new_resource.build_user_home, 'finder-auth-flow.scpt') do
        source 'finder-auth-flow.scpt'
        cookbook 'cinc-omnibus'
        owner build_user
        mode '0755'
      end
    end

    if new_resource.manage_service
      # macOS supports only a per-user LaunchAgent (in the GUI session) — never
      # sudo/LaunchDaemon. brew services without sudo writes the user agent, and
      # the agent only loads when build_user owns the console, so a headless
      # converge skips cleanly instead of failing to bootstrap a gui/<uid> domain.
      execute 'enable gitlab-runner service' do
        command 'brew services start gitlab-runner'
        user build_user
        environment build_env
        only_if { gitlab_runner_console_owned_by_build_user? }
        not_if { gitlab_runner_service_started? }
      end

      execute 'restart gitlab-runner service' do
        command 'brew services restart gitlab-runner'
        user build_user
        environment build_env
        action :nothing
        only_if { gitlab_runner_console_owned_by_build_user? }
        # When signing is on, the resign step is the restart trigger; only fall
        # back to the package subscription when signing is disabled, so the
        # service still restarts on an upgrade in that mode.
        subscribes :run, 'package[gitlab-runner]', :immediately unless new_resource.manage_macos_signing
      end
    end
  elsif freebsd?
    # Bootstrap the pkg catalog so the install finds a candidate (pkgng never
    # fetches on its own). Idempotent via creates; a no-op when invoked from
    # cinc_omnibus_builder, which already does this.
    execute 'pkg update' do
      command 'pkg update'
      creates '/var/db/pkg/repos/FreeBSD/db'
    end

    # The community port (devel/gitlab-runner) brings the rc.d service, the
    # gitlab-runner user/group, and runtime deps (bash, git, ca_root_nss).
    package 'gitlab-runner' do
      version new_resource.version if new_resource.version
    end

    service 'gitlab_runner' do
      action [:enable, :start]
    end if new_resource.manage_service
  elsif windows?
    chocolatey_package 'gitlab-runner' do
      version new_resource.version if new_resource.version
    end

    if new_resource.manage_service
      install_dir = new_resource.windows_install_dir

      directory install_dir

      # Built-in System Account service (headless, no password). Guarded so an
      # already-installed service isn't reinstalled. Refresh PATH from the
      # registry first: chocolatey adds the runner's dir to the machine PATH
      # during this same converge, which the running process won't see yet.
      powershell_script 'install gitlab-runner service' do
        code <<~PS1
          $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
          gitlab-runner install --working-directory "#{install_dir}" --config "#{windows_safe_path_join(install_dir, 'config.toml')}"
        PS1
        not_if { gitlab_runner_windows_service_installed? }
      end

      service 'gitlab-runner' do
        action [:enable, :start]
      end
    end
  end
end

action :remove do
  next if linux?

  if mac_os_x?
    build_user = new_resource.build_user
    build_env = gitlab_runner_build_env

    if new_resource.manage_service
      execute 'stop gitlab-runner service' do
        command 'brew services stop gitlab-runner'
        user build_user
        environment build_env
        only_if { gitlab_runner_service_active? }
      end
    end

    # Reverse the signing keychain :create created (delete-keychain also drops
    # it from the search list).
    execute 'delete gitlab-runner signing keychain' do
      command "security delete-keychain #{Shellwords.escape(new_resource.signing_keychain)}"
      user build_user
      environment build_env
      only_if { gitlab_runner_signing_keychain_exists? }
    end

    file ::File.join(new_resource.build_user_home, 'finder-auth-flow.scpt') do
      action :delete
    end

    package 'gitlab-runner' do
      action :remove
    end if new_resource.remove_package
  elsif freebsd?
    service 'gitlab_runner' do
      action [:stop, :disable]
    end if new_resource.manage_service

    package 'gitlab-runner' do
      action :remove
    end if new_resource.remove_package
  elsif windows?
    if new_resource.manage_service
      powershell_script 'uninstall gitlab-runner service' do
        code <<~PS1
          $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
          gitlab-runner stop; gitlab-runner uninstall
        PS1
        only_if { gitlab_runner_windows_service_installed? }
      end
    end

    chocolatey_package 'gitlab-runner' do
      action :remove
    end if new_resource.remove_package
  end
end
