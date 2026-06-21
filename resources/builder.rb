# frozen_string_literal: true

provides :cinc_omnibus_builder
unified_mode true

include CincOmnibus::Cookbook::Helpers

property :instance_name, String, name_property: true
property :packages, [Array, nil], default: lazy { omnibus_packages }
property :unsafe_packages, [Array, nil], default: lazy { omnibus_unsafe_deps }
property :pkgconfig_files, Array, default: lazy { omnibus_pkgconfig_files(toolchain_install_dir) }
property :build_user, String, default: 'omnibus'
property :build_group, String, default: 'omnibus'
property :build_user_home, String, default: lazy { default_build_user_home }
property :build_user_shell, String, default: lazy { default_build_user_shell }
property :cache_dir, String, default: lazy { default_cache_dir }
property :toolchain_install_dir, String, default: lazy { default_toolchain_install_dir }
property :toolchain_version, String, default: 'latest'
property :toolchain_channel, [String, Symbol], default: :stable
property :toolchain_architecture, String, default: lazy { node['kernel']['machine'] }
property :mixlib_install_version, String, default: '3.12.30'
property :ruby_docker_copy_patch_path, String, default: '/usr/local/share/ruby-docker-copy-patch.rb'
property :manage_ruby_docker_copy_patch, [true, false], default: true
property :manage_debian_arm_links, [true, false], default: true
property :extra_environment, Hash, default: {}
property :remove_packages, [true, false], default: false
property :manage_msys2, [true, false], default: true
property :msys2_packages, Array, default: lazy { msys2_default_packages }
property :msys2_ignore_packages, Array, default: lazy { msys2_default_ignore_packages }
property :msys2_pinned_packages, Array, default: []
property :msys2_base_archive_date, String, default: lazy { msys2_latest_base_archive_date }
property :msys2_verify_signature, [true, false], default: true
property :manage_gitlab_runner, [true, false], default: true
property :manage_gitlab_runner_service, [true, false], default: true
property :manage_gitlab_runner_signing, [true, false], default: true
property :gitlab_runner_version, [String, nil]

default_action :create

action_class do
  include CincOmnibus::Cookbook::Helpers

  def omnibus_toolchain_environment
    install_dir = new_resource.toolchain_install_dir

    env = {
      'OMNIBUS_TOOLCHAIN_INSTALL_DIR' => [install_dir],
      'SSL_CERT_FILE' => [windows_safe_path_join(install_dir, 'embedded', 'ssl', 'certs', 'cacert.pem')],
    }

    if windows?
      # A fresh box has no build tools on PATH, so the shim prepends them.
      # HOMEDRIVE/HOMEPATH point Ruby/Git at the build user's home.
      env['PATH'] = windows_path_entries(install_dir)
      env['HOMEDRIVE'] = [windows_system_drive]
      env['HOMEPATH'] = [new_resource.build_user_home.sub(/\A[A-Za-z]:/, '')]
      env['MSYS2_INSTALL_DIR'] = [windows_msys2_install_dir]
      env['MSYSTEM'] = ['UCRT64']
      env['OMNIBUS_WINDOWS_ARCH'] = ['x64']
      env['BASH_ENV'] = [windows_safe_path_join(windows_msys2_install_dir, 'etc', 'bash.bashrc')]
    else
      env['PATH'] = [::File.join(install_dir, 'bin'), '/usr/local/bin']
    end

    new_resource.extra_environment.each do |key, value|
      env[key] = Array(value)
    end

    env
  end

  def omnibus_toolchain_path(env)
    env.fetch('PATH').uniq.join(::File::PATH_SEPARATOR)
  end

  def load_omnibus_toolchain_content(env)
    install_dir = new_resource.toolchain_install_dir
    path = omnibus_toolchain_path(env)
    exports = env.reject { |key, _value| key == 'PATH' }
                 .map { |key, value| "export #{key}=#{value.first}" }
                 .join("\n")

    <<~SCRIPT
      #!/usr/bin/env bash

      ###################################################################
      # Load the base Omnibus environment
      ###################################################################
      export PATH="#{path}:$PATH"
      #{exports}
      ###################################################################
      # Query tool versions
      ###################################################################

      echo ""
      echo "========================================"
      echo "= Tool Versions"
      echo "========================================"
      echo ""

      echo "$(head -1 #{install_dir}/version-manifest.txt)"
      echo ""

      echo "Bash.........$(bash --version | head -1)"
      echo "Berkshelf....$(berks --version | head -1)"
      echo "Bundler......$(bundle --version | head -1)"
      echo "Curl.........$(curl --version | head -1)"
      echo "GCC..........$(gcc --version | head -1)"
      echo "Git..........$(git --version | head -1)"
      echo "Java.........$(java -version 2>&1 | head -1)"
      echo "Make.........$(make --version | head -1)"
      echo "Patch........$(patch --version | head -1)"
      echo "Pkg-config...$(pkg-config --version)"
      echo "Ruby.........$(ruby --version)"
      echo "RubyGems.....$(gem --version)"
      echo "Tar..........$(tar --version | head -1)"

      echo ""
      echo "========================================"
    SCRIPT
  end

  def load_omnibus_toolchain_ps1_content(env)
    # Windows PATH separator is ';'; File::PATH_SEPARATOR is ':' on the ChefSpec host.
    path = env.fetch('PATH').uniq.join(';')
    exports = env.reject { |key, _value| key == 'PATH' }
                 .map { |key, value| "$env:#{key}='#{value.first}'" }
                 .join("\n")

    <<~SCRIPT
      ###############################################################
      # Load the base Omnibus environment
      ###############################################################
      #{exports}
      $env:PATH="#{path};$env:PATH"

      ###############################################################
      # Query tool versions
      ###############################################################

      $env:OMNIBUS_GIT_VERSION=git --version
      $env:OMNIBUS_RUBY_VERSION=ruby --version
      $env:OMNIBUS_GEM_VERSION=gem --version
      $env:OMNIBUS_BUNDLER_VERSION=bundle --version
      $env:OMNIBUS_GCC_VERSION=(gcc --version)[0]
      $env:OMNIBUS_MAKE_VERSION=(make --version)[0]
      $env:OMNIBUS_SEVENZIP_VERSION=(7z -h)[1]
      $env:OMNIBUS_WIX_HEAT_VERSION=(heat -help)[0]
      $env:OMNIBUS_WIX_CANDLE_VERSION=(candle -help)[0]
      $env:OMNIBUS_WIX_LIGHT_VERSION=(light -help)[0]

      Write-Host " ========================================"
      Write-Host " = Tool Versions"
      Write-Host " ========================================"

      Write-Host " 7-Zip..........$env:OMNIBUS_SEVENZIP_VERSION"
      Write-Host " Bundler........$env:OMNIBUS_BUNDLER_VERSION"
      Write-Host " GCC............$env:OMNIBUS_GCC_VERSION"
      Write-Host " Git............$env:OMNIBUS_GIT_VERSION"
      Write-Host " Make...........$env:OMNIBUS_MAKE_VERSION"
      Write-Host " Ruby...........$env:OMNIBUS_RUBY_VERSION"
      Write-Host " RubyGems.......$env:OMNIBUS_GEM_VERSION"
      Write-Host " WiX:Heat.......$env:OMNIBUS_WIX_HEAT_VERSION"
      Write-Host " WiX:Candle.....$env:OMNIBUS_WIX_CANDLE_VERSION"

      Write-Host " ========================================"
    SCRIPT
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
end

action :create do
  # Bootstrap the FreeBSD pkg catalog: freebsd_package's `pkg rquery` returns
  # no candidate until the catalog is fetched. `creates` keeps it idempotent.
  execute 'pkg update' do
    command 'pkg update'
    only_if { freebsd? }
    creates '/var/db/pkg/repos/FreeBSD/db'
  end

  if new_resource.packages
    if windows?
      # Build tools via chocolatey; MSYS2 (needs pacman) is handled by
      # cinc_omnibus_msys2 below.
      chocolatey_installer 'install'

      new_resource.packages.each { |p| chocolatey_package p }
    elsif freebsd?
      # Work around a freebsd_pkgng multipackage bug (only the first name gets
      # a candidate version); install one at a time.
      new_resource.packages.each { |p| package p }
    elsif platform_family?('suse')
      # openSUSE Leap images can ship a runtime lib (e.g. libncurses6) that is
      # newer than the matching *-devel package available in the configured
      # repos, which makes a plain install of e.g. ncurses-devel unsatisfiable.
      # Allow zypper to downgrade the runtime lib to the version the -devel
      # package pins to so the dependency can be resolved.
      package new_resource.packages do
        options '--allow-downgrade'
      end
    else
      package new_resource.packages
    end
  end
  package 'devtoolset-10' if centos? && node['platform_version'].to_i == 7

  if windows? && new_resource.manage_msys2
    cinc_omnibus_msys2 new_resource.instance_name do
      packages new_resource.msys2_packages
      ignore_packages new_resource.msys2_ignore_packages
      pinned_packages new_resource.msys2_pinned_packages
      base_archive_date new_resource.msys2_base_archive_date
      verify_signature new_resource.msys2_verify_signature
    end
  end

  build_essential 'cinc-omnibus' unless windows?

  package new_resource.unsafe_packages do
    action :remove
  end if new_resource.unsafe_packages

  node.override['chef-ingredient']['mixlib-install']['version'] = new_resource.mixlib_install_version

  chef_ingredient 'omnibus-toolchain' do
    rubygems_url 'https://rubygems.cinc.sh'
    version new_resource.toolchain_version
    channel new_resource.toolchain_channel
    architecture new_resource.toolchain_architecture
    platform 'sles' if platform?('opensuseleap')
    platform_version_compatibility_mode true
    action(windows? ? :install : :upgrade)
  end

  new_resource.pkgconfig_files.each do |pkgconfig_file|
    file pkgconfig_file do
      manage_symlink_source true
      action :delete
    end
  end

  unless windows?
    group new_resource.build_group do
      append true
    end

    # Declare the build user's existing SecureToken state (macOS only) so the
    # mac_user provider doesn't try to toggle it, which would need admin creds.
    # Computed here, not in the block: sub-resource blocks can't see our helpers.
    build_user_secure_token = mac_build_user_secure_token?(new_resource.build_user)

    user new_resource.build_user do
      home new_resource.build_user_home
      group new_resource.build_group
      shell new_resource.build_user_shell
      secure_token build_user_secure_token if mac_os_x?
    end
  end

  directory new_resource.build_user_home do
    unless windows?
      owner new_resource.build_user
      group new_resource.build_group
    end
  end

  directory new_resource.cache_dir do
    recursive true
    unless windows?
      owner new_resource.build_user
      group new_resource.build_group
    end
  end

  directory Chef::Config[:file_cache_path] do
    recursive true
  end

  env = omnibus_toolchain_environment

  file ::File.join(new_resource.build_user_home, '.gitconfig') do
    unless windows?
      owner new_resource.build_user
      group new_resource.build_group
      mode '0644'
    end
    content <<~GITCONFIG
      # This file is written by Cinc
      # Do NOT modify this file by hand.

      [user]
        ; Set a sane user name and email. This makes git happy and prevents
        ; spammy output on each git command.
        name  = Omnibus
        email = omnibus@cinc.sh
      [color]
        ; Since this is a build machine, we do not want colored output.
        ui = false
      [core]
        editor = $EDITOR
        whitespace = fix
      [apply]
        whitespace = fix
      [push]
        default = tracking
      [branch]
        autosetuprebase = always
      [pull]
        rebase = preserve
    GITCONFIG
  end

  if windows?
    file ::File.join(new_resource.build_user_home, 'load-omnibus-toolchain.ps1') do
      content load_omnibus_toolchain_ps1_content(env)
    end
  else
    file ::File.join(new_resource.build_user_home, 'load-omnibus-toolchain.sh') do
      content load_omnibus_toolchain_content(env)
      owner new_resource.build_user
      group new_resource.build_group
      mode '0755'
    end
  end

  if new_resource.manage_ruby_docker_copy_patch && linux?
    file new_resource.ruby_docker_copy_patch_path do
      content ruby_docker_copy_patch_content
    end
  end

  if new_resource.manage_debian_arm_links && arm? && debian_platform? && node['platform_version'].to_i < 12
    link '/usr/bin/mkdir' do
      to '/bin/mkdir'
    end

    link '/bin/install' do
      to '/usr/bin/install'
    end
  end

  if mac_os_x?
    # Homebrew names libtool's binary glibtoolize, and on Apple Silicon puts
    # pkg-config outside the default omnibus PATH.
    brew_prefix = arm? ? '/opt/homebrew' : '/usr/local'

    link '/usr/local/bin/libtoolize' do
      to ::File.join(brew_prefix, 'bin', 'glibtoolize')
    end

    if arm?
      link '/usr/local/bin/pkg-config' do
        to ::File.join(brew_prefix, 'bin', 'pkg-config')
      end
    end
  end

  # Install the GitLab Runner on non-Linux builders (Linux runners live on the
  # Docker host). Registration stays manual; this never runs `register`.
  if new_resource.manage_gitlab_runner && !linux?
    cinc_omnibus_gitlab_runner new_resource.instance_name do
      build_user new_resource.build_user
      build_user_home new_resource.build_user_home
      version new_resource.gitlab_runner_version
      manage_service new_resource.manage_gitlab_runner_service
      manage_macos_signing new_resource.manage_gitlab_runner_signing
    end
  end
end

action :remove do
  new_resource.pkgconfig_files.each do |pkgconfig_file|
    file pkgconfig_file do
      action :delete
    end
  end

  file ::File.join(new_resource.build_user_home, '.gitconfig') do
    action :delete
  end

  if windows?
    file ::File.join(new_resource.build_user_home, 'load-omnibus-toolchain.ps1') do
      action :delete
    end
  else
    file ::File.join(new_resource.build_user_home, 'load-omnibus-toolchain.sh') do
      action :delete
    end
  end

  if linux?
    file new_resource.ruby_docker_copy_patch_path do
      action :delete
    end
  end

  directory new_resource.cache_dir do
    recursive true
    action :delete
  end

  package new_resource.packages do
    action :remove
  end if new_resource.remove_packages && new_resource.packages

  if windows? && new_resource.manage_msys2 && new_resource.remove_packages
    cinc_omnibus_msys2 new_resource.instance_name do
      action :remove
    end
  end

  if new_resource.manage_gitlab_runner && !linux?
    cinc_omnibus_gitlab_runner new_resource.instance_name do
      build_user new_resource.build_user
      build_user_home new_resource.build_user_home
      manage_service new_resource.manage_gitlab_runner_service
      remove_package new_resource.remove_packages
      action :remove
    end
  end
end
