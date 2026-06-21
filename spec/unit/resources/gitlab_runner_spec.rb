# frozen_string_literal: true

require 'spec_helper'

describe 'cinc_omnibus_gitlab_runner' do
  step_into :cinc_omnibus_gitlab_runner

  recipe do
    cinc_omnibus_gitlab_runner 'default'
  end

  context 'on macos arm64' do
    platform 'mac_os_x', '12'

    before do
      stub_command(/security find-identity/).and_return(false)
      stub_command(/codesign -d/).and_return(false)
      stub_command(/brew services list/).and_return(false)
      stub_command(%r{stat -f %u /dev/console}).and_return(true)
    end

    it { expect { chef_run }.to_not raise_error }
    it { is_expected.to install_package('gitlab-runner') }

    it 'creates the stable signing identity' do
      is_expected.to run_bash('create gitlab-runner signing identity')
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
  end

  context 'on macos intel' do
    platform 'mac_os_x', '12'
    automatic_attributes['kernel']['machine'] = 'x86_64'

    before do
      stub_command(/security find-identity/).and_return(false)
      stub_command(/codesign -d/).and_return(false)
      stub_command(/brew services list/).and_return(false)
      stub_command(%r{stat -f %u /dev/console}).and_return(true)
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
      stub_command(/brew services list/).and_return(false)
      stub_command(%r{stat -f %u /dev/console}).and_return(true)
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
  end

  context 'on windows' do
    platform 'windows'

    before { stub_command(/Get-Service/).and_return(false) }

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

  context 'with remove action on freebsd' do
    platform 'freebsd', '12.1'

    recipe do
      cinc_omnibus_gitlab_runner 'default' do
        action :remove
      end
    end

    it { is_expected.to disable_service('gitlab_runner') }
    it { is_expected.to stop_service('gitlab_runner') }
    # Package removal is opt-in.
    it { is_expected.to_not remove_package('gitlab-runner') }
  end
end
