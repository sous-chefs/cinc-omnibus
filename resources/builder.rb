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
      # PATH stays untouched on Windows; the runner's system PATH
      # already orders WiX / 7-Zip / MSYS2 / Ruby / Git correctly.
      env['MSYS2_INSTALL_DIR'] = [windows_safe_path_join(windows_system_drive, 'msys64')]
      env['MSYSTEM'] = ['UCRT64']
      env['OMNIBUS_WINDOWS_ARCH'] = ['x64']
      env['BASH_ENV'] = [windows_safe_path_join(windows_system_drive, 'msys64', 'etc', 'bash.bashrc')]
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
    exports = env.reject { |key, _value| key == 'PATH' }
                 .map { |key, value| "$env:#{key}='#{value.first}'" }
                 .join("\n")

    <<~SCRIPT
      ###############################################################
      # Load the base Omnibus environment
      ###############################################################
      #{exports}

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
  # Bootstrap the FreeBSD pkg catalog on a fresh box. Chef's
  # freebsd_package provider relies on `pkg rquery`, which returns "No
  # candidate version available" until the catalog has been fetched
  # (`pkg install` would auto-bootstrap, but the candidate query never
  # gets there). `creates` makes this idempotent: the catalog file is
  # written by pkg as part of the fetch.
  execute 'pkg update' do
    command 'pkg update'
    only_if { freebsd? }
    creates '/var/db/pkg/repos/FreeBSD/db'
  end

  if new_resource.packages
    if freebsd?
      # Chef's freebsd_pkgng provider has a multipackage bug: a single
      # `pkg rquery` call with multiple names returns N lines of versions
      # but candidate_version_array only carries the combined string at
      # index 0, leaving the rest of the package_name array with no
      # candidate. Install one at a time so each call gets its own
      # candidate_version lookup.
      new_resource.packages.each { |p| package p }
    else
      package new_resource.packages
    end
  end
  package 'devtoolset-10' if centos? && node['platform_version'].to_i == 7

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

    user new_resource.build_user do
      home new_resource.build_user_home
      group new_resource.build_group
      shell new_resource.build_user_shell
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
    # Homebrew installs libtool's binary as glibtoolize and (on Apple
    # Silicon) puts pkg-config outside the default omnibus build PATH.
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
end
