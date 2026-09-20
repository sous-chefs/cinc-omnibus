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
property :git_safe_directories, Array, default: lazy { default_git_safe_directories(build_user_home) }
property :manage_root_gitconfig, [true, false], default: true
property :extra_environment, Hash, default: {}
property :remove_packages, [true, false], default: false
property :manage_gitlab_runner, [true, false], default: true
property :manage_gitlab_runner_service, [true, false], default: true
property :manage_gitlab_runner_signing, [true, false], default: true
property :manage_gitlab_runner_sudoers, [true, false], default: true
property :gitlab_runner_version, [String, nil]
# Windows only: the host runs the builds in containers, so it is prepared as a
# Docker host (cinc_omnibus_docker_host) instead of getting the build tools.
property :manage_docker_host, [true, false], default: true
property :docker_engine_version, [String, nil]
property :docker_data_root, [String, nil]
property :docker_daemon_config, Hash, default: {}
property :containers_feature_source, [String, nil]
property :reboot_after_feature_install, [true, false], default: true
property :allow_hyperv, [true, false], default: false
property :manage_defender, [true, false], default: true
property :defender_exclusions, Array,
         default: lazy { windows_docker_defender_exclusions(docker_data_root) + [gitlab_runner_windows_install_dir] }
property :defender_process_exclusions, Array, default: []
property :disable_defender_realtime, [true, false], default: true
property :remove_defender, [true, false], default: false

default_action :create

action_class do
  include CincOmnibus::Cookbook::Helpers

  def omnibus_toolchain_environment
    install_dir = new_resource.toolchain_install_dir

    env = {
      'OMNIBUS_TOOLCHAIN_INSTALL_DIR' => [install_dir],
      'SSL_CERT_FILE' => [::File.join(install_dir, 'embedded', 'ssl', 'certs', 'cacert.pem')],
      'PATH' => [::File.join(install_dir, 'bin'), '/usr/local/bin'],
    }

    # ccache's compiler wrappers live in their own dir and only take effect
    # when it precedes the real compilers on PATH, as ports' bsd.ccache.mk does.
    env['PATH'].unshift(freebsd_ccache_wrapper_dir) if freebsd?

    new_resource.extra_environment.each do |key, value|
      env[key] = Array(value)
    end

    env
  end
end

action :create do
  # Windows builds run in the cincproject/omnibus-windows image, which carries
  # the toolchain, MSYS2 and the build tools; the host only needs Docker and a
  # runner with the docker-windows executor.
  if windows?
    if new_resource.manage_docker_host
      cinc_omnibus_docker_host new_resource.instance_name do
        docker_engine_version new_resource.docker_engine_version
        docker_data_root new_resource.docker_data_root
        docker_daemon_config new_resource.docker_daemon_config
        containers_feature_source new_resource.containers_feature_source
        reboot_after_feature_install new_resource.reboot_after_feature_install
        allow_hyperv new_resource.allow_hyperv
        manage_defender new_resource.manage_defender
        defender_exclusions new_resource.defender_exclusions
        defender_process_exclusions new_resource.defender_process_exclusions
        disable_defender_realtime new_resource.disable_defender_realtime
        remove_defender new_resource.remove_defender
      end
    end

    if new_resource.manage_gitlab_runner
      cinc_omnibus_gitlab_runner new_resource.instance_name do
        version new_resource.gitlab_runner_version
        manage_service new_resource.manage_gitlab_runner_service
      end
    end

    next
  end

  # Bootstrap the FreeBSD pkg catalog: freebsd_package's `pkg rquery` returns
  # no candidate until the catalog is fetched. `creates` keeps it idempotent.
  execute 'pkg update' do
    command 'pkg update'
    only_if { freebsd? }
    creates '/var/db/pkg/repos/FreeBSD/db'
  end

  if new_resource.packages
    if freebsd?
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

  build_essential 'cinc-omnibus'

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
    action :upgrade
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

  directory new_resource.build_user_home do
    owner new_resource.build_user
    group new_resource.build_group
  end

  directory new_resource.cache_dir do
    recursive true
    owner new_resource.build_user
    group new_resource.build_group
  end

  directory Chef::Config[:file_cache_path] do
    recursive true
  end

  env = omnibus_toolchain_environment

  gitconfig_variables = { safe_directories: new_resource.git_safe_directories }

  template ::File.join(new_resource.build_user_home, '.gitconfig') do
    source 'gitconfig.erb'
    cookbook 'cinc-omnibus' # not the wrapper that declares the resource
    variables gitconfig_variables
    owner new_resource.build_user
    group new_resource.build_group
    mode '0644'
  end

  # The macOS build step runs `sudo -E`, which today keeps HOME pointed at the
  # build user, so root reads the file above. Give root its own copy so the
  # build keeps working if that ever stops holding.
  if mac_os_x? && new_resource.manage_root_gitconfig
    template ::File.join(mac_root_home, '.gitconfig') do
      source 'gitconfig.erb'
      cookbook 'cinc-omnibus' # not the wrapper that declares the resource
      variables gitconfig_variables
      owner 'root'
      group 'wheel'
      mode '0644'
    end
  end

  template ::File.join(new_resource.build_user_home, 'load-omnibus-toolchain.sh') do
    source 'load-omnibus-toolchain.sh.erb'
    cookbook 'cinc-omnibus' # not the wrapper that declares the resource
    variables omnibus_toolchain_sh_variables(env)
    owner new_resource.build_user
    group new_resource.build_group
    mode '0755'
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
    # Homebrew names libtool's binary glibtoolize and ships GNU tar as gtar (the
    # system bsdtar rejects GNU options like --warning=no-file-changed); on Apple
    # Silicon it also puts pkg-config outside the default omnibus PATH.
    brew_prefix = arm? ? '/opt/homebrew' : '/usr/local'

    link '/usr/local/bin/libtoolize' do
      to ::File.join(brew_prefix, 'bin', 'glibtoolize')
    end

    # /usr/local/bin precedes /usr/bin in the default macOS PATH, so this makes
    # GNU tar the global `tar`.
    link '/usr/local/bin/tar' do
      to ::File.join(brew_prefix, 'bin', 'gtar')
    end

    if arm?
      link '/usr/local/bin/pkg-config' do
        to ::File.join(brew_prefix, 'bin', 'pkg-config')
      end

      # Apple's /usr/bin/git (2.32.1) predates both the sudo-aware ownership
      # check and safe.directory globs, so `sudo -E` builds reject the runner's
      # checkout. Intel reaches Homebrew's git through /usr/local/bin for free.
      # Guarded: a dangling link here would shadow /usr/bin/git for every caller.
      link '/usr/local/bin/git' do
        to ::File.join(brew_prefix, 'bin', 'git')
        only_if { ::File.exist?(::File.join(brew_prefix, 'bin', 'git')) }
      end
    end

    # Setting the build user's primary group to `omnibus` can drop it from the
    # com.apple.access_ssh SACL, locking it out where Remote Login is limited to
    # specific users. Re-add it — but only when that SACL exists, so we never
    # flip an all-users host into restricted mode. Idempotent via checkmember.
    execute 'grant build user ssh access' do
      command mac_ssh_access_grant_command(new_resource.build_user)
      only_if { mac_ssh_access_restricted? }
      not_if  { mac_ssh_access_granted?(new_resource.build_user) }
    end
  end

  if freebsd?
    # The ports OpenSSL's OPENSSLDIR is /usr/local/openssl, but ca_root_nss only
    # populates /usr/local/etc/ssl and /usr/local/share/certs. Without a cert.pem
    # there, anything linked against it (an RVM-built ruby, notably) fails TLS
    # verification with "unable to get local issuer certificate".
    directory '/usr/local/openssl'

    link '/usr/local/openssl/cert.pem' do
      to '/usr/local/share/certs/ca-root-nss.crt'
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
      manage_sudoers new_resource.manage_gitlab_runner_sudoers
    end
  end
end

action :remove do
  if windows?
    if new_resource.manage_docker_host
      cinc_omnibus_docker_host new_resource.instance_name do
        docker_data_root new_resource.docker_data_root
        manage_defender new_resource.manage_defender
        defender_exclusions new_resource.defender_exclusions
        defender_process_exclusions new_resource.defender_process_exclusions
        disable_defender_realtime new_resource.disable_defender_realtime
        remove_defender new_resource.remove_defender
        remove_package new_resource.remove_packages
        action :remove
      end
    end

    if new_resource.manage_gitlab_runner
      cinc_omnibus_gitlab_runner new_resource.instance_name do
        manage_service new_resource.manage_gitlab_runner_service
        remove_package new_resource.remove_packages
        action :remove
      end
    end

    next
  end

  new_resource.pkgconfig_files.each do |pkgconfig_file|
    file pkgconfig_file do
      action :delete
    end
  end

  file ::File.join(new_resource.build_user_home, '.gitconfig') do
    action :delete
  end

  file ::File.join(mac_root_home, '.gitconfig') do
    action :delete
  end if mac_os_x? && new_resource.manage_root_gitconfig

  file ::File.join(new_resource.build_user_home, 'load-omnibus-toolchain.sh') do
    action :delete
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

  if new_resource.manage_gitlab_runner && !linux?
    cinc_omnibus_gitlab_runner new_resource.instance_name do
      build_user new_resource.build_user
      build_user_home new_resource.build_user_home
      manage_service new_resource.manage_gitlab_runner_service
      manage_sudoers new_resource.manage_gitlab_runner_sudoers
      remove_package new_resource.remove_packages
      action :remove
    end
  end
end
