# frozen_string_literal: true

require 'shellwords'

module CincOmnibus
  module Cookbook
    module Helpers
      def omnibus_packages
        pkgs = []
        case node['platform_family']
        when 'amazon'
          pkgs = %w(
            automake
            bzip2
            ca-certificates
            git
            glibc-langpack-en
            glibc-locale-source
            iproute
            libffi-devel
            libtool
            ncurses-devel
            openssh-clients
            pkgconf
            perl-Digest-SHA
            perl-IPC-Cmd
            perl-Time-Piece
            perl-bignum
            rpm-build
            rpm-sign
            rsync
            tar
            tzdata
            wget
            zlib-devel
          )
          pkgs << %w(perl-FindBin perl-lib) if node['platform_version'].to_i >= 2022
          pkgs.append(omnibus_java_pkg)
          pkgs.flatten.sort
        when 'rhel', 'fedora'
          pkgs = %w(
            automake
            bzip2
            ca-certificates
            git
            iproute
            libffi-devel
            libtool
            openssh-clients
            pkgconf
            perl-Digest-SHA
            perl-IPC-Cmd
            perl-Time-Piece
            perl-bignum
            rpm-build
            rpm-sign
            rsync
            tar
            tzdata
            wget
            zlib-devel
          )
          pkgs << %w(glibc-langpack-en glibc-locale-source) if node['platform_version'].to_i >= 8
          pkgs << %w(perl-FindBin perl-lib) if node['platform_version'].to_i >= 9
          pkgs.delete('zlib-devel') if node['platform_version'].to_i >= 10
          pkgs << 'zlib-ng-compat-devel' if node['platform_version'].to_i >= 10
          pkgs.delete('wget') if node['platform'] == 'fedora'
          pkgs << 'wget2-wget' if node['platform'] == 'fedora'
          pkgs.append(omnibus_java_pkg)
          pkgs.flatten.sort
        when 'debian'
          pkgs = %w(
            automake
            binutils
            bzip2
            ca-certificates
            devscripts
            git
            dpkg-dev
            fakeroot
            gnupg
            iproute2
            libffi-dev
            libncurses-dev
            libssl-dev
            libtool
            locales
            locales-all
            openssh-client
            pkgconf
            rsync
            tar
            tzdata
            wget
            zlib1g-dev
          )
          pkgs.append(omnibus_java_pkg)
          pkgs.flatten.sort
        when 'suse'
          pkgs = %w(
            automake
            bzip2
            curl
            git
            glibc-i18ndata
            glibc-locale
            gzip
            hostname
            iproute2
            libffi-devel
            libtool
            ncurses-devel
            openssh
            pkgconf
            rpm-build
            rsync
            tar
            timezone
            wget
            zlib-devel
          )
          pkgs.append(omnibus_java_pkg)
          pkgs.flatten.sort
        when 'mac_os_x'
          %w(
            autoconf
            automake
            git
            gnu-tar
            libffi
            libtool
            libyaml
            openssl@3
            pkgconf
            readline
          )
        when 'freebsd'
          %w(
            autoconf
            automake
            bash
            ca_root_nss
            ccache
            gcc
            git
            libffi
            libtool
            libyaml
            openssl
            pkgconf
            readline
          )
        end
      end

      def omnibus_java_pkg
        case node['platform']
        when 'amazon'
          'java-17-amazon-corretto-headless'
        when 'centos', 'centos_stream', 'redhat', 'almalinux', 'rocky', 'oracle'
          case node['platform_version'].to_i
          when 8, 9
            'java-17-openjdk-devel'
          when 10
            'java-21-openjdk-devel'
          end
        when 'fedora'
          'java-latest-openjdk-devel'
        when 'debian'
          case node['platform_version'].to_i
          when 10, 11
            'openjdk-11-jdk-headless'
          when 12
            'openjdk-17-jdk-headless'
          else
            'openjdk-21-jdk-headless'
          end
        when 'ubuntu'
          case node['platform_version']
          when '18.04'
            'openjdk-11-jdk-headless'
          when '20.04'
            'openjdk-17-jdk-headless'
          else
            'openjdk-21-jdk-headless'
          end
        when 'opensuseleap'
          # Leap 16.0 dropped the Java 11 packages; it ships OpenJDK 21.
          node['platform_version'].to_i >= 16 ? 'java-21-openjdk-devel' : 'java-11-openjdk-devel'
        end
      end

      def omnibus_unsafe_deps
        case node['platform_family']
        when 'amazon', 'rhel', 'fedora', 'suse'
          %w(pcre2-devel libselinux-devel)
        when 'debian'
          %w(libpcre2-dev libselinux1-dev)
        end
      end

      def omnibus_pkgconfig_files(install_dir = default_toolchain_install_dir)
        [
          ::File.join(install_dir, 'bin', 'pkg-config'),
          ::File.join(install_dir, 'embedded', 'bin', 'pkg-config'),
          ::File.join(install_dir, 'LICENSES', 'pkg-config-lite-COPYING'),
          ::File.join(install_dir, 'embedded', 'share', 'aclocal', 'pkg.m4'),
        ]
      end

      def omnibus_env
        node.run_state[:omnibus_env] ||= Hash.new { |hash, key| hash[key] = [] }
      end

      # Where the ccache port drops its cc/gcc/c++ symlinks: ports' bsd.ccache.mk
      # uses ${LOCALBASE}/libexec/ccache, and LOCALBASE is /usr/local.
      def freebsd_ccache_wrapper_dir
        '/usr/local/libexec/ccache'
      end

      # The runner checks out under <build user home>/builds/<runner token>/...,
      # and the build step runs it through sudo, so root's git has to accept a
      # checkout the build user owns. The trailing /* matches at any depth, which
      # keeps the runner-specific token out of the value.
      def default_git_safe_directories(home = default_build_user_home)
        [::File.join(home, 'builds', '*')]
      end

      # macOS keeps root's home outside /Users.
      def mac_root_home
        '/var/root'
      end

      # The load-shim variables and patch content helpers below back files
      # dropped by the builder action; they reference new_resource, so are only
      # valid in action context.

      # Template variables for the load-omnibus-toolchain.sh shim. Berkshelf and
      # Java are Linux-only, so the template omits those version checks on
      # macOS/FreeBSD.
      def omnibus_toolchain_sh_variables(env)
        {
          install_dir: new_resource.toolchain_install_dir,
          path: env.fetch('PATH').uniq.join(::File::PATH_SEPARATOR),
          exports: env.reject { |key, _value| key == 'PATH' }
                      .map { |key, value| "export #{key}=#{value.first}" }
                      .join("\n"),
          linux: linux?,
        }
      end

      def ruby_docker_copy_patch_content
        <<~RUBY
          # frozen_string_literal: true

          require "fileutils"

          # Fixes a linux 5.6 - 5.10 kernel bug around copy_file_range syscall
          # https://github.com/docker/for-linux/issues/1015

          module FileUtils
            class Entry_
              def copy_file(dest)
                File.open(path) do |s|
                  File.open(dest, 'wb', s.stat.mode) do |d|
                    s.chmod s.lstat.mode
                    IO.copy_stream(s, d)
                    d.chmod(d.lstat.mode)
                  end
                end
              end
            end
          end
        RUBY
      end

      def default_toolchain_install_dir
        '/opt/omnibus-toolchain'
      end

      # Windows-only paths (runner install dir, Docker dirs). Backslashes are
      # only substituted on a Windows host, so the ChefSpec host keeps '/'.
      def windows_safe_path_join(*pieces)
        path = File.join(*pieces)

        if File::ALT_SEPARATOR
          path.gsub(File::SEPARATOR, File::ALT_SEPARATOR)
        else
          path
        end
      end

      def default_build_user_home
        mac_os_x? ? '/Users/omnibus' : '/home/omnibus'
      end

      def windows_system_drive
        ENV['SYSTEMDRIVE'] || 'C:'
      end

      def gitlab_runner_windows_install_dir
        windows_safe_path_join(windows_system_drive, 'GitLab-Runner')
      end

      # Docker on the Windows host: image layers, container writable layers and
      # daemon.json live under ProgramData; the choco docker-engine package (v23+)
      # installs the binaries under Program Files.
      def windows_docker_program_data
        windows_safe_path_join(windows_system_drive, 'ProgramData', 'docker')
      end

      def windows_docker_daemon_config_path
        windows_safe_path_join(windows_docker_program_data, 'config', 'daemon.json')
      end

      # Defender real-time scanning sat at 90% CPU during concurrent container
      # builds; the layer dirs are what it chews on. A custom data-root is
      # appended when set.
      def windows_docker_defender_exclusions(data_root = nil)
        [
          windows_docker_program_data,
          windows_safe_path_join(windows_system_drive, 'Program Files', 'docker'),
          data_root,
        ].compact
      end

      # PowerShell array literal of single-quoted strings.
      def powershell_string_array(items)
        "@(#{items.map { |item| "'#{item.to_s.gsub("'", "''")}'" }.join(', ')})"
      end

      # PowerShell statements that leave the entries of `items` missing from the
      # Get-MpPreference list `flag` (ExclusionPath / ExclusionProcess) in
      # $missing. -notcontains is case-insensitive, matching how Defender stores
      # paths. Two statements, so callers append with ';' rather than assign.
      def windows_defender_missing_exclusions(flag, items)
        "$current = @((Get-MpPreference).#{flag}); " \
        "$missing = @(#{powershell_string_array(items)} | Where-Object { $current -notcontains $_ })"
      end

      # The windows_* predicates below back the cinc_omnibus_docker_host guards;
      # they shell out, so they are only valid in action context.

      # Process isolation needs no hypervisor, and with Hyper-V present the
      # Server Standard licence caps Hyper-V-isolated containers at two.
      def windows_hyperv_installed?
        powershell_exec!("(Get-WindowsFeature -Name Hyper-V -ErrorAction SilentlyContinue).InstallState -eq 'Installed'").result == true
      end

      # False once the Windows-Defender feature is removed (the Mp* cmdlets go
      # with it) — every Defender step is guarded on this.
      def windows_defender_present?
        powershell_exec!('[bool](Get-Command Get-MpPreference -ErrorAction SilentlyContinue)').result == true
      end

      # Tamper Protection makes Set-MpPreference a silent no-op; it can only be
      # turned off from the Windows Security UI or an MDM/Intune policy.
      def windows_defender_tamper_protected?
        powershell_exec!('[bool](Get-MpComputerStatus -ErrorAction SilentlyContinue).IsTamperProtected').result == true
      end

      # Chef's reboot_pending?: a reboot requested this run, or Windows'
      # CBS/Windows Update/PendingFileRenameOperations markers.
      def windows_reboot_pending?
        reboot_pending?
      end

      # A docker service that chocolatey does not own (Microsoft's
      # install-docker-ce.ps1, the GitHub Actions runner image): leave it alone
      # rather than install a second engine over it.
      def windows_docker_installed_outside_chocolatey?
        powershell_exec!(<<~PS1).result == true
          $choco = if ($env:ChocolateyInstall) { $env:ChocolateyInstall } else { Join-Path $env:ProgramData 'chocolatey' }
          [bool](Get-Service -Name docker -ErrorAction SilentlyContinue) -and -not (Test-Path (Join-Path $choco 'lib\docker-engine'))
        PS1
      end

      def default_build_user_shell
        ::File.join(default_toolchain_install_dir, 'bin', 'bash')
      end

      def default_cache_dir
        '/var/cache/omnibus'
      end

      # macOS only. True when the build user already holds a SecureToken. We
      # mirror this onto the user resource so Chef's mac_user provider sees no
      # divergence and never tries to toggle the token (which would demand
      # admin credentials we don't have). sysadminctl writes status to stderr;
      # if it isn't available we assume no token.
      def mac_build_user_secure_token?(user)
        return false unless mac_os_x?

        status = shell_out('sysadminctl', '-secureTokenStatus', user)
        "#{status.stdout}#{status.stderr}".match?(/Secure token is ENABLED/)
      rescue Errno::ENOENT
        false
      end

      # macOS Remote Login limited to specific users gates on membership in the
      # com.apple.access_ssh Service ACL; the build user's primary-group change
      # can drop it, so the builder re-adds the user.
      def mac_ssh_access_grant_command(user)
        "dseditgroup -o edit -a #{Shellwords.escape(user)} -t user com.apple.access_ssh"
      end

      # True when the build user is already in that SSH access group.
      def mac_ssh_access_granted?(user)
        shell_out('dseditgroup', '-o', 'checkmember', '-m', user, 'com.apple.access_ssh').exitstatus.zero?
      end

      # True when Remote Login is limited to specific users: the SACL group
      # exists only in that mode (it's renamed *-disabled for "all users"), so
      # its presence is the signal to manage membership — and the guard that
      # keeps us from flipping an all-users host into restricted mode.
      def mac_ssh_access_restricted?
        shell_out('dseditgroup', '-o', 'read', 'com.apple.access_ssh').exitstatus.zero?
      end

      # Homebrew's prefix: /opt/homebrew on Apple Silicon, /usr/local on Intel.
      def mac_brew_prefix
        arm? ? '/opt/homebrew' : '/usr/local'
      end

      # The gitlab-runner binary installed by Homebrew (a symlink into the
      # Cellar; codesign follows it to sign the real Mach-O).
      def gitlab_runner_mac_binary(prefix = mac_brew_prefix)
        ::File.join(prefix, 'bin', 'gitlab-runner')
      end

      # The gitlab_runner_* helpers below back the cinc_omnibus_gitlab_runner
      # provider's guards and scripts; they reference new_resource and shell out,
      # so they are only valid in action context.

      def gitlab_runner_build_env
        { 'HOME' => new_resource.build_user_home }
      end

      def gitlab_runner_run_as_build_user(command)
        shell_out(command, user: new_resource.build_user, environment: gitlab_runner_build_env)
      end

      # bash that (re)creates the dedicated signing keychain and a single stable
      # self-signed code-signing identity.
      def gitlab_runner_signing_keychain_script
        <<~BASH
          set -e
          KEYCHAIN=#{Shellwords.escape(new_resource.signing_keychain)}
          KCPASS=#{Shellwords.escape(new_resource.signing_keychain_password)}
          IDENTITY=#{Shellwords.escape(new_resource.signing_identity)}
          # Recreate from scratch so we never accumulate duplicate identities
          # (codesign --sign by name is ambiguous when more than one matches).
          security delete-keychain "$KEYCHAIN" 2>/dev/null || true
          security create-keychain -p "$KCPASS" "$KEYCHAIN"
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
          /usr/bin/openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -subj "/CN=$IDENTITY" -config "$TMP/req.cnf"
          /usr/bin/openssl pkcs12 -export -out "$TMP/id.p12" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -passout pass:"$KCPASS"
          security import "$TMP/id.p12" -k "$KEYCHAIN" -P "$KCPASS" -T /usr/bin/codesign -A
          security set-key-partition-list -S apple-tool:,apple: -s -k "$KCPASS" "$KEYCHAIN" >/dev/null
        BASH
      end

      # The resign command: unlock the keychain, re-sign with the stable identity,
      # and verify. Kept non-hardened (no --options runtime) so the binary can
      # send AppleEvents to Finder without the apple-events entitlement.
      def gitlab_runner_resign_command
        keychain = Shellwords.escape(new_resource.signing_keychain)
        binary = Shellwords.escape(gitlab_runner_mac_binary)
        [
          "security unlock-keychain -p #{Shellwords.escape(new_resource.signing_keychain_password)} #{keychain}",
          "codesign --force --sign #{Shellwords.escape(new_resource.signing_identity)} " \
          "--identifier #{Shellwords.escape(new_resource.signing_identifier)} --keychain #{keychain} #{binary}",
          "codesign --verify --strict #{binary}",
        ].join(' && ')
      end

      # True when EXACTLY ONE matching identity exists: 0 = not set up yet, 2+ =
      # duplicates that make codesign --sign ambiguous. No -v, since a self-signed
      # cert is untrusted and never shows under "valid identities only".
      def gitlab_runner_signing_identity_ready?
        count = "security find-identity -p codesigning #{Shellwords.escape(new_resource.signing_keychain)} " \
                "2>/dev/null | grep -Fc #{Shellwords.escape(new_resource.signing_identity)}"
        gitlab_runner_run_as_build_user(%([ "$(#{count})" -eq 1 ])).exitstatus.zero?
      end

      def gitlab_runner_keychain_in_search_list?
        gitlab_runner_run_as_build_user(
          "security list-keychains -d user | grep -Fq #{Shellwords.escape(new_resource.signing_keychain)}"
        ).exitstatus.zero?
      end

      # True when the binary already carries our stable identity (Authority CN and
      # Identifier both match), so the resign is a no-op until the next upgrade
      # replaces the binary.
      def gitlab_runner_binary_signed?
        binary = Shellwords.escape(gitlab_runner_mac_binary)
        gitlab_runner_run_as_build_user(
          "codesign -d --verbose=4 #{binary} 2>&1 | grep -Fq #{Shellwords.escape("Authority=#{new_resource.signing_identity}")} && " \
          "codesign -d --verbose=4 #{binary} 2>&1 | grep -Fq #{Shellwords.escape("Identifier=#{new_resource.signing_identifier}")}"
        ).exitstatus.zero?
      end

      def gitlab_runner_service_started?
        gitlab_runner_run_as_build_user('brew services list | grep -E "^gitlab-runner[[:space:]]+started"').exitstatus.zero?
      end

      def gitlab_runner_service_active?
        gitlab_runner_run_as_build_user('brew services list | grep -E "^gitlab-runner[[:space:]]+(started|scheduled)"').exitstatus.zero?
      end

      # The LaunchAgent loads into gui/<uid>, so brew services only works when
      # build_user owns the console (is logged in); otherwise skip cleanly.
      def gitlab_runner_console_owned_by_build_user?
        gitlab_runner_run_as_build_user(%([ "$(stat -f %u /dev/console)" = "$(id -u #{Shellwords.escape(new_resource.build_user)})" ])).exitstatus.zero?
      end

      def gitlab_runner_signing_keychain_exists?
        ::File.exist?(new_resource.signing_keychain)
      end

      # The binary the choco package drops with /InstallDir, and what the
      # service must point at (not the shim on PATH).
      def gitlab_runner_windows_exe
        windows_safe_path_join(new_resource.windows_install_dir, 'gitlab-runner.exe')
      end

      def gitlab_runner_windows_service_path
        powershell_out(%((Get-CimInstance Win32_Service -Filter "Name='gitlab-runner'").PathName)).stdout.strip
      end

      def gitlab_runner_windows_service_exists?
        !gitlab_runner_windows_service_path.empty?
      end

      # Installed *and* registered against our binary; anything else (the
      # choco shim, a moved install dir) gets reinstalled.
      def gitlab_runner_windows_service_installed?
        gitlab_runner_windows_service_path.downcase.include?(gitlab_runner_windows_exe.downcase)
      end
    end
  end
end
