# frozen_string_literal: true

require 'spec_helper'

describe 'cinc_omnibus_gitlab_runner' do
  step_into :cinc_omnibus_gitlab_runner

  # The guards are block form calling Helpers predicates (which shell out at
  # converge time); stub them like msys2_spec does for its guards.
  def stub_guard(name, value)
    allow_any_instance_of(CincOmnibus::Cookbook::Helpers).to receive(name).and_return(value)
  end

  recipe do
    cinc_omnibus_gitlab_runner 'default'
  end

  context 'on macos arm64' do
    platform 'mac_os_x', '12'

    before do
      stub_guard(:gitlab_runner_signing_identity_ready?, false)
      stub_guard(:gitlab_runner_keychain_in_search_list?, false)
      stub_guard(:gitlab_runner_binary_signed?, false)
      stub_guard(:gitlab_runner_service_started?, false)
      stub_guard(:gitlab_runner_console_owned_by_build_user?, true)
    end

    it { expect { chef_run }.to_not raise_error }
    it { is_expected.to install_package('gitlab-runner') }

    it 'creates the stable signing identity' do
      is_expected.to run_bash('create gitlab-runner signing identity')
    end

    it 'adds the signing keychain to the search list so codesign can find it' do
      is_expected.to run_execute('add gitlab-runner signing keychain to search list')
    end

    it 're-signs the Apple Silicon binary with the fixed identity' do
      is_expected.to run_execute('resign gitlab-runner').with(
        command: %r{/opt/homebrew/bin/gitlab-runner}
      )
    end

    it 'signs with the configured identifier' do
      is_expected.to run_execute('resign gitlab-runner').with(
        command: /--identifier sh\.cinc\.omnibus\.gitlab-runner/
      )
    end

    it { is_expected.to create_cookbook_file('/Users/omnibus/finder-auth-flow.scpt') }

    it 'starts the LaunchAgent as the build user without sudo' do
      is_expected.to run_execute('enable gitlab-runner service').with(
        command: 'brew services start gitlab-runner',
        user: 'omnibus'
      )
    end

    # The LaunchAgent runs as build_user, so the grant is named for that account
    # rather than for gitlab-runner as on FreeBSD.
    it 'grants the build user passwordless sudo' do
      is_expected.to create_file('/etc/sudoers.d/omnibus').with(
        content: "omnibus ALL = (ALL) NOPASSWD:ALL\n",
        owner: 'root',
        group: 'wheel',
        mode: '0440'
      )
    end

    # sudo is part of the macOS base system; nothing to install.
    it { is_expected.to_not install_package('sudo') }
  end

  context 'on macos with a custom build user' do
    platform 'mac_os_x', '12'

    before do
      stub_guard(:gitlab_runner_service_started?, false)
      stub_guard(:gitlab_runner_console_owned_by_build_user?, true)
    end

    recipe do
      cinc_omnibus_gitlab_runner 'default' do
        build_user 'builder'
        manage_macos_signing false
      end
    end

    it 'names the sudoers drop-in for that user' do
      is_expected.to create_file('/etc/sudoers.d/builder').with(
        content: "builder ALL = (ALL) NOPASSWD:ALL\n"
      )
    end
  end

  context 'on macos with manage_sudoers false' do
    platform 'mac_os_x', '12'

    before do
      stub_guard(:gitlab_runner_service_started?, false)
      stub_guard(:gitlab_runner_console_owned_by_build_user?, true)
    end

    recipe do
      cinc_omnibus_gitlab_runner 'default' do
        manage_sudoers false
        manage_macos_signing false
      end
    end

    it { is_expected.to_not create_file('/etc/sudoers.d/omnibus') }
  end

  context 'on macos intel' do
    platform 'mac_os_x', '12'
    automatic_attributes['kernel']['machine'] = 'x86_64'

    before do
      stub_guard(:gitlab_runner_signing_identity_ready?, false)
      stub_guard(:gitlab_runner_keychain_in_search_list?, false)
      stub_guard(:gitlab_runner_binary_signed?, false)
      stub_guard(:gitlab_runner_service_started?, false)
      stub_guard(:gitlab_runner_console_owned_by_build_user?, true)
    end

    it 're-signs the Intel binary path' do
      is_expected.to run_execute('resign gitlab-runner').with(
        command: %r{/usr/local/bin/gitlab-runner}
      )
    end
  end

  context 'on macos with signing disabled' do
    platform 'mac_os_x', '12'

    before do
      stub_guard(:gitlab_runner_service_started?, false)
      stub_guard(:gitlab_runner_console_owned_by_build_user?, true)
    end

    recipe do
      cinc_omnibus_gitlab_runner 'default' do
        manage_macos_signing false
      end
    end

    it { is_expected.to install_package('gitlab-runner') }
    it { is_expected.to_not run_execute('resign gitlab-runner') }
    it { is_expected.to_not create_cookbook_file('/Users/omnibus/finder-auth-flow.scpt') }
    it { is_expected.to run_execute('enable gitlab-runner service') }
  end

  context 'on freebsd' do
    platform 'freebsd', '12.1'

    it { expect { chef_run }.to_not raise_error }
    it { is_expected.to install_package('gitlab-runner') }
    it { is_expected.to enable_service('gitlab_runner') }
    it { is_expected.to start_service('gitlab_runner') }
    # No macOS signing/AppleScript on FreeBSD.
    it { is_expected.to_not run_execute('resign gitlab-runner') }

    # The build renames /opt/omnibus-toolchain aside and runs omnibus as root.
    it { is_expected.to install_package('sudo') }

    it 'grants the runner user passwordless sudo' do
      is_expected.to create_file('/usr/local/etc/sudoers.d/gitlab-runner').with(
        content: "gitlab-runner ALL = (ALL) NOPASSWD:ALL\n",
        owner: 'root',
        group: 'wheel',
        mode: '0440'
      )
    end
  end

  context 'on freebsd with manage_sudoers false' do
    platform 'freebsd', '12.1'

    recipe do
      cinc_omnibus_gitlab_runner 'default' do
        manage_sudoers false
      end
    end

    it { is_expected.to_not create_file('/usr/local/etc/sudoers.d/gitlab-runner') }
    it { is_expected.to_not install_package('sudo') }
  end

  context 'on windows' do
    platform 'windows'

    before { stub_guard(:gitlab_runner_windows_service_installed?, false) }

    it { expect { chef_run }.to_not raise_error }
    it { is_expected.to install_chocolatey_package('gitlab-runner') }
    it { is_expected.to run_powershell_script('install gitlab-runner service') }
    it { is_expected.to enable_service('gitlab-runner') }
    it { is_expected.to start_service('gitlab-runner') }
  end

  context 'on linux (no-op: runner lives on the Docker host)' do
    platform 'ubuntu', '24.04'

    it { expect { chef_run }.to_not raise_error }
    it { is_expected.to_not install_package('gitlab-runner') }
    it { is_expected.to_not run_execute('resign gitlab-runner') }
  end

  context 'with remove action on macos' do
    platform 'mac_os_x', '12'

    before do
      stub_guard(:gitlab_runner_service_active?, true)
      stub_guard(:gitlab_runner_signing_keychain_exists?, true)
    end

    recipe do
      cinc_omnibus_gitlab_runner 'default' do
        action :remove
      end
    end

    it { is_expected.to run_execute('stop gitlab-runner service') }
    it { is_expected.to run_execute('delete gitlab-runner signing keychain') }
    it { is_expected.to delete_file('/Users/omnibus/finder-auth-flow.scpt') }
    it { is_expected.to delete_file('/etc/sudoers.d/omnibus') }
    it { is_expected.to_not remove_package('gitlab-runner') }
  end

  context 'with remove action on freebsd' do
    platform 'freebsd', '12.1'

    recipe do
      cinc_omnibus_gitlab_runner 'default' do
        action :remove
      end
    end

    it { is_expected.to disable_service('gitlab_runner') }
    it { is_expected.to stop_service('gitlab_runner') }
    it { is_expected.to delete_file('/usr/local/etc/sudoers.d/gitlab-runner') }
    # Package removal is opt-in.
    it { is_expected.to_not remove_package('gitlab-runner') }
  end
end
