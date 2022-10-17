module CincOmnibus
  module Cookbook
    module Helpers
      require 'mixlib/shellout'

      def omnibus_packages
        pkgs = []
        case node['platform_family']
        when 'amazon'
          pkgs = %w(
            automake
            bzip2
            ca-certificates
            glibc-langpack-en
            glibc-locale-source
            iproute
            libffi-devel
            ncurses-devel
            openssh-clients
            rpm-build
            rpm-sign
            rsync
            tar
            tzdata
            wget
            zlib-devel
          )
          pkgs.append(omnibus_java_pkg)
          pkgs.flatten.sort
        when 'rhel'
          pkgs = %w(
            automake
            bzip2
            ca-certificates
            iproute
            libffi-devel
            openssh-clients
            rpm-build
            rpm-sign
            rsync
            tar
            tzdata
            wget
            zlib-devel
          )
          pkgs << %w(glibc-langpack-en glibc-locale-source) if node['platform_version'].to_i >= 8
          pkgs.append(omnibus_java_pkg)
          pkgs.flatten.sort
        when 'debian'
          pkgs = %w(
            automake
            binutils
            bzip2
            ca-certificates
            devscripts
            dpkg-dev
            fakeroot
            gnupg
            iproute2
            libffi-dev
            libncurses-dev
            libssl-dev
            locales
            locales-all
            openssh-client
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
            glibc-i18ndata
            glibc-locale
            gzip
            hostname
            iproute2
            libffi-devel
            ncurses-devel
            openssh
            rpm-build
            rsync
            tar
            timezone
            wget
            zlib-devel
          )
          pkgs.append(omnibus_java_pkg)
          pkgs.flatten.sort
        end
      end

      def omnibus_java_pkg
        case node['platform']
        when 'amazon'
          case node['platform_version'].to_i
          when 2
            'java-11-amazon-corretto-headless'
          when 2022
            'java-17-amazon-corretto-headless'
          end
        when 'centos', 'redhat'
          case node['platform_version'].to_i
          when 7
            'java-11-openjdk-devel'
          when 8, 9
            'java-17-openjdk-devel'
          end
        when 'debian'
          case node['platform_version'].to_i
          when 9
            'openjdk-8-jdk-headless'
          else
            'openjdk-11-jdk-headless'
          end
        when 'ubuntu'
          case node['platform_version']
          when '18.04'
            'openjdk-11-jdk-headless'
          when '20.04'
            'openjdk-17-jdk-headless'
          else
            'openjdk-18-jdk-headless'
          end
        when 'opensuseleap'
          'java-11-openjdk-devel'
        end
      end

      def omnibus_env
        node.run_state[:omnibus_env] ||= Hash.new { |hash, key| hash[key] = [] }
      end

      def toolchain_install_dir
        if windows?
          windows_safe_path_join(ENV['SYSTEMDRIVE'], 'opscode', 'omnibus-toolchain')
        else
          '/opt/omnibus-toolchain'
        end
      end

      def windows_safe_path_join(*pieces)
        path = File.join(*pieces)

        if File::ALT_SEPARATOR
          path.gsub(File::SEPARATOR, File::ALT_SEPARATOR)
        else
          path
        end
      end

      def build_user_home
        if mac_os_x?
          '/Users/omnibus'
        elsif windows?
          windows_safe_path_join(ENV['SYSTEMDRIVE'], 'omnibus')
        else
          '/home/omnibus'
        end
      end

      def build_user_shell
        if windows?
          windows_safe_path_join(toolchain_install_dir, 'embedded', 'bin', 'usr', 'bin', 'bash')
        else
          ::File.join(toolchain_install_dir, 'bin', 'bash')
        end
      end
    end
  end
end
Chef::DSL::Recipe.include ::CincOmnibus::Cookbook::Helpers
Chef::Resource.include ::CincOmnibus::Cookbook::Helpers
