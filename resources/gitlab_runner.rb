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
    package 'gitlab-runner' do
      version new_resource.version if new_resource.version
    end

    if new_resource.manage_macos_signing
      binary = gitlab_runner_mac_binary
      keychain = new_resource.signing_keychain
      password = new_resource.signing_keychain_password
      identity = new_resource.signing_identity
      identifier = new_resource.signing_identifier
      home = new_resource.build_user_home
      build_user = new_resource.build_user
      build_env = { 'HOME' => home }

      directory ::File.dirname(keychain) do
        owner build_user
        recursive true
      end

      # Create the dedicated signing keychain + a stable self-signed
      # code-signing identity. Idempotent: skipped once the identity exists.
      bash 'create gitlab-runner signing identity' do
        user build_user
        environment build_env
        sensitive true
        code <<~BASH
          set -e
          KEYCHAIN=#{Shellwords.escape(keychain)}
          KCPASS=#{Shellwords.escape(password)}
          IDENTITY=#{Shellwords.escape(identity)}
          [ -f "$KEYCHAIN" ] || security create-keychain -p "$KCPASS" "$KEYCHAIN"
          # Unlock BEFORE set-keychain-settings: on a locked keychain the latter
          # needs an interactive unlock, which fails ("User interaction is not
          # allowed") in a headless/non-GUI converge. With the password supplied
          # up front, none of the commands below need an interactive session.
          security unlock-keychain -p "$KCPASS" "$KEYCHAIN"
          security set-keychain-settings "$KEYCHAIN"
          TMP=$(mktemp -d)
          trap 'rm -rf "$TMP"' EXIT
          # Use a config file (not -addext) so the codeSigning EKU is set on every
          # macOS LibreSSL version.
          {
            echo '[req]'
            echo 'distinguished_name = dn'
            echo 'x509_extensions = v3'
            echo '[dn]'
            echo '[v3]'
            echo 'basicConstraints = critical,CA:FALSE'
            echo 'keyUsage = critical,digitalSignature'
            echo 'extendedKeyUsage = critical,codeSigning'
          } > "$TMP/req.cnf"
          # Use the system LibreSSL (/usr/bin/openssl), not whatever is on PATH:
          # a Homebrew openssl@3 exports PKCS#12 with a SHA-256 MAC that macOS
          # `security import` rejects ("MAC verification failed"). LibreSSL
          # defaults to the SHA1-MAC/3DES form `security` reads natively.
          /usr/bin/openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
            -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
            -subj "/CN=$IDENTITY" -config "$TMP/req.cnf"
          /usr/bin/openssl pkcs12 -export -out "$TMP/id.p12" \
            -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -passout pass:"$KCPASS"
          # codesign is pointed at this keychain explicitly (--keychain), so it
          # need not be added to the user search list.
          security import "$TMP/id.p12" -k "$KEYCHAIN" -P "$KCPASS" -T /usr/bin/codesign -A
          security set-key-partition-list -S apple-tool:,apple: -s -k "$KCPASS" "$KEYCHAIN" >/dev/null
        BASH
        not_if "security find-identity -v -p codesigning #{Shellwords.escape(keychain)} | grep -Fq #{Shellwords.escape(identity)}",
               user: build_user, environment: build_env
      end

      # Re-sign with the stable identity. Idempotent via the signature check, so
      # it re-runs after every `brew upgrade` (which replaces the binary).
      # Do NOT add --options runtime: the binary must stay non-hardened so it can
      # send AppleEvents to Finder without the apple-events entitlement.
      esc_binary = Shellwords.escape(binary)
      execute 'resign gitlab-runner' do
        command [
          "security unlock-keychain -p #{Shellwords.escape(password)} #{Shellwords.escape(keychain)}",
          "codesign --force --sign #{Shellwords.escape(identity)} --identifier #{Shellwords.escape(identifier)} " \
          "--keychain #{Shellwords.escape(keychain)} #{esc_binary}",
          "codesign --verify --strict #{esc_binary}",
        ].join(' && ')
        user build_user
        environment build_env
        sensitive true
        not_if "codesign -d --verbose=4 #{esc_binary} 2>&1 | grep -Fq #{Shellwords.escape("Authority=#{identity}")} && " \
               "codesign -d --verbose=4 #{esc_binary} 2>&1 | grep -Fq #{Shellwords.escape("Identifier=#{identifier}")}",
               user: build_user, environment: build_env
        notifies :run, 'execute[restart gitlab-runner service]', :immediately if new_resource.manage_service
      end

      # One-time TCC grant helper (replaces the standalone finder-auth-flow repo).
      cookbook_file ::File.join(home, 'finder-auth-flow.scpt') do
        source 'finder-auth-flow.scpt'
        cookbook 'cinc-omnibus'
        owner build_user
        mode '0755'
      end
    end

    if new_resource.manage_service
      service_user = new_resource.build_user
      service_env = { 'HOME' => new_resource.build_user_home }
      # The LaunchAgent loads into gui/<uid>, so brew services only works when
      # build_user owns the console (is logged in). Skip cleanly otherwise — a
      # headless converge (e.g. CI) would error trying to bootstrap into a
      # nonexistent Aqua session.
      console_owned = %([ "$(stat -f %u /dev/console)" = "$(id -u #{Shellwords.escape(service_user)})" ])

      # macOS supports only a per-user LaunchAgent (in the GUI session) — never
      # sudo/LaunchDaemon. brew services without sudo writes the user agent.
      execute 'enable gitlab-runner service' do
        command 'brew services start gitlab-runner'
        user service_user
        environment service_env
        only_if console_owned, user: service_user, environment: service_env
        not_if 'brew services list | grep -E "^gitlab-runner[[:space:]]+started"',
               user: service_user, environment: service_env
      end

      execute 'restart gitlab-runner service' do
        command 'brew services restart gitlab-runner'
        user service_user
        environment service_env
        action :nothing
        only_if console_owned, user: service_user, environment: service_env
        # When signing is on, the resign step is the restart trigger. Only fall
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
        not_if 'Get-Service -Name gitlab-runner -ErrorAction SilentlyContinue'
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
    if new_resource.manage_service
      service_user = new_resource.build_user
      service_env = { 'HOME' => new_resource.build_user_home }

      execute 'stop gitlab-runner service' do
        command 'brew services stop gitlab-runner'
        user service_user
        environment service_env
        only_if 'brew services list | grep -E "^gitlab-runner[[:space:]]+(started|scheduled)"',
                user: service_user, environment: service_env
      end
    end

    # Reverse the signing keychain :create created (delete-keychain also drops
    # it from the search list).
    execute 'delete gitlab-runner signing keychain' do
      command "security delete-keychain #{Shellwords.escape(new_resource.signing_keychain)}"
      user new_resource.build_user
      environment('HOME' => new_resource.build_user_home)
      only_if { ::File.exist?(new_resource.signing_keychain) }
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
        only_if 'Get-Service -Name gitlab-runner -ErrorAction SilentlyContinue'
      end
    end

    chocolatey_package 'gitlab-runner' do
      action :remove
    end if new_resource.remove_package
  end
end
