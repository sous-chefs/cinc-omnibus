# frozen_string_literal: true

provides :cinc_omnibus_builder
unified_mode true

include CincOmnibus::Cookbook::Helpers

property :instance_name, String, name_property: true
property :packages, [Array, nil], default: lazy { omnibus_packages }
property :unsafe_packages, [Array, nil], default: lazy { omnibus_unsafe_deps }
property :pkgconfig_files, Array, default: lazy { omnibus_pkgconfig_files }
property :build_user, String, default: 'omnibus'
property :build_group, String, default: 'omnibus'
property :build_user_home, String, default: lazy { default_build_user_home }
property :build_user_shell, String, default: lazy { default_build_user_shell }
property :cache_dir, String, default: '/var/cache/omnibus'
property :toolchain_install_dir, String, default: lazy { default_toolchain_install_dir }
property :toolchain_version, String, default: 'latest'
property :toolchain_channel, [String, Symbol], default: :stable
property :toolchain_architecture, String, default: lazy { node['kernel']['machine'] }
property :manage_toolchain, [true, false], default: true
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
    env = {
      'OMNIBUS_TOOLCHAIN_INSTALL_DIR' => [new_resource.toolchain_install_dir],
      'SSL_CERT_FILE' => [windows_safe_path_join(new_resource.toolchain_install_dir, 'embedded', 'ssl', 'certs', 'cacert.pem')],
      'PATH' => [::File.join(new_resource.toolchain_install_dir, 'bin'), '/usr/local/bin'],
    }

    new_resource.extra_environment.each do |key, value|
      env[key] = Array(value)
    end

    env
  end

  def omnibus_toolchain_path(env)
    env.fetch('PATH').uniq.join(::File::PATH_SEPARATOR)
  end

  def load_omnibus_toolchain_content(env)
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

      echo "$(head -1 /opt/omnibus-toolchain/version-manifest.txt)"
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
  package new_resource.packages if new_resource.packages
  package 'devtoolset-10' if centos? && node['platform_version'].to_i == 7

  build_essential 'cinc-omnibus'

  package new_resource.unsafe_packages do
    action :remove
  end if new_resource.unsafe_packages

  node.override['chef-ingredient']['mixlib-install']['version'] = new_resource.mixlib_install_version

  if new_resource.manage_toolchain
    chef_ingredient 'omnibus-toolchain' do
      rubygems_url 'https://rubygems.cinc.sh' if cinc_omnibus?
      version new_resource.toolchain_version
      channel new_resource.toolchain_channel
      architecture new_resource.toolchain_architecture
      platform 'sles' if platform?('opensuseleap')
      platform_version_compatibility_mode true
      action(windows? ? :install : :upgrade)
    end
  end

  new_resource.pkgconfig_files.each do |pkgconfig_file|
    file pkgconfig_file do
      manage_symlink_source true
      action :delete
    end
  end

  group new_resource.build_group do
    append true
  end

  user new_resource.build_user do
    home new_resource.build_user_home
    group new_resource.build_group
    shell new_resource.build_user_shell
  end

  directory new_resource.build_user_home do
    owner new_resource.build_user
    group new_resource.build_group
  end

  directory new_resource.cache_dir do
    owner new_resource.build_user
    group new_resource.build_group
  end

  directory Chef::Config[:file_cache_path] do
    recursive true
  end

  env = omnibus_toolchain_environment

  file ::File.join(new_resource.build_user_home, '.gitconfig') do
    owner new_resource.build_user
    group new_resource.build_group
    mode '0644'
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

  file ::File.join(new_resource.build_user_home, 'load-omnibus-toolchain.sh') do
    content load_omnibus_toolchain_content(env)
    owner new_resource.build_user
    group new_resource.build_group
    mode '0755'
  end

  file new_resource.ruby_docker_copy_patch_path do
    content ruby_docker_copy_patch_content
  end if new_resource.manage_ruby_docker_copy_patch

  if new_resource.manage_debian_arm_links && arm? && debian_platform? && node['platform_version'].to_i < 12
    link '/usr/bin/mkdir' do
      to '/bin/mkdir'
    end

    link '/bin/install' do
      to '/usr/bin/install'
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

  file ::File.join(new_resource.build_user_home, 'load-omnibus-toolchain.sh') do
    action :delete
  end

  file new_resource.ruby_docker_copy_patch_path do
    action :delete
  end

  directory new_resource.cache_dir do
    recursive true
    action :delete
  end

  package new_resource.packages do
    action :remove
  end if new_resource.remove_packages && new_resource.packages
end
