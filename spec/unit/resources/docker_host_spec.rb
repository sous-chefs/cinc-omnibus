# frozen_string_literal: true

require 'spec_helper'

describe 'cinc_omnibus_docker_host' do
  step_into :cinc_omnibus_docker_host
  platform 'windows'

  # The guards shell out to PowerShell at converge time; stub them like the
  # gitlab_runner spec does. String guards need stub_command.
  def stub_guard(name, value)
    allow_any_instance_of(CincOmnibus::Cookbook::Helpers).to receive(name).and_return(value)
  end

  before do
    # Exclusion guards: something is missing. Real-time guards: currently on.
    stub_command(/\[bool\]\$missing/).and_return(true)
    stub_command(/DisableRealtimeMonitoring -and/).and_return(false)
    stub_command(/DisableRealtimeMonitoring -or/).and_return(true)
    stub_guard(:windows_hyperv_installed?, false)
    stub_guard(:windows_defender_present?, true)
    stub_guard(:windows_defender_tamper_protected?, false)
    stub_guard(:windows_reboot_pending?, false)
    stub_guard(:windows_docker_installed_outside_chocolatey?, false)
  end

  recipe do
    cinc_omnibus_docker_host 'default'
  end

  context 'with defaults' do
    it { expect { chef_run }.to_not raise_error }

    it 'installs the Containers feature and asks for the reboot it needs' do
      expect(chef_run).to install_windows_feature_powershell('Containers')
      expect(chef_run.windows_feature_powershell('Containers'))
        .to notify('reboot[cinc-omnibus docker host]').to(:request_reboot).immediately
    end

    # File::ALT_SEPARATOR is nil on Linux (the chefspec host) so
    # windows_safe_path_join leaves forward slashes in place.
    it 'excludes the docker dirs from Defender, quoting the Program Files path' do
      expect(chef_run).to run_powershell_script('add docker defender path exclusions')
        .with(code: %r{@\('C:/ProgramData/docker', 'C:/Program Files/docker'\)})
    end

    it { is_expected.to_not run_powershell_script('add docker defender process exclusions') }

    it 'turns real-time and behavior monitoring off' do
      expect(chef_run).to run_powershell_script('disable defender real-time monitoring')
        .with(code: 'Set-MpPreference -DisableRealtimeMonitoring $true -DisableBehaviorMonitoring $true')
    end

    it { is_expected.to_not remove_windows_feature_powershell('Windows-Defender') }
    it { is_expected.to_not write_log('defender tamper protection blocks Set-MpPreference') }

    it { is_expected.to install_chocolatey_installer('install') }
    it { is_expected.to install_chocolatey_package('docker-engine') }

    # No data-root and no daemon options: leave any hand-managed daemon.json alone.
    it { is_expected.to_not create_file('C:/ProgramData/docker/config/daemon.json') }

    it { is_expected.to enable_service('docker') }
    it { is_expected.to start_service('docker') }
    it { is_expected.to_not write_log('docker start deferred until reboot') }
  end

  context 'with a reboot pending' do
    before { stub_guard(:windows_reboot_pending?, true) }

    # dockerd cannot start until the Containers feature is live.
    it { is_expected.to write_log('docker start deferred until reboot') }
    it { is_expected.to_not start_service('docker') }
  end

  context 'with reboot_after_feature_install false' do
    recipe do
      cinc_omnibus_docker_host 'default' do
        reboot_after_feature_install false
      end
    end

    it 'installs the feature without requesting a reboot' do
      expect(chef_run).to install_windows_feature_powershell('Containers')
      expect(chef_run.windows_feature_powershell('Containers'))
        .to_not notify('reboot[cinc-omnibus docker host]').to(:request_reboot)
    end
  end

  context 'with a feature source' do
    recipe do
      cinc_omnibus_docker_host 'default' do
        containers_feature_source 'wim:D:\sources\install.wim:4'
      end
    end

    it 'passes it through for a payload-stripped image' do
      expect(chef_run).to install_windows_feature_powershell('Containers')
        .with(source: 'wim:D:\sources\install.wim:4')
    end
  end

  context 'with Hyper-V installed' do
    before { stub_guard(:windows_hyperv_installed?, true) }

    it { expect { chef_run }.to raise_error(/Hyper-V is installed/) }

    context 'and allow_hyperv true' do
      recipe do
        cinc_omnibus_docker_host 'default' do
          allow_hyperv true
        end
      end

      it { expect { chef_run }.to_not raise_error }
    end
  end

  context 'with a data-root and daemon options' do
    recipe do
      cinc_omnibus_docker_host 'default' do
        docker_data_root 'E:\docker'
        docker_daemon_config('group' => 'docker-users')
      end
    end

    it 'writes daemon.json and restarts docker' do
      expect(chef_run).to create_directory('E:\docker')
      expect(chef_run).to create_directory('C:/ProgramData/docker/config')
      expect(chef_run).to create_file('C:/ProgramData/docker/config/daemon.json')
        .with(content: "{\n  \"group\": \"docker-users\",\n  \"data-root\": \"E:\\\\docker\"\n}\n")
      expect(chef_run.file('C:/ProgramData/docker/config/daemon.json'))
        .to notify('service[docker]').to(:restart).delayed
    end

    it 'adds the data-root to the Defender exclusions' do
      expect(chef_run).to run_powershell_script('add docker defender path exclusions')
        .with(code: /'E:\\docker'/)
    end
  end

  context 'with process exclusions' do
    recipe do
      cinc_omnibus_docker_host 'default' do
        defender_process_exclusions %w(gcc.exe ld.exe)
      end
    end

    it do
      expect(chef_run).to run_powershell_script('add docker defender process exclusions')
        .with(code: /Add-MpPreference -ExclusionProcess/)
    end
  end

  context 'with remove_defender true' do
    recipe do
      cinc_omnibus_docker_host 'default' do
        remove_defender true
      end
    end

    # Exclusions still go in first: they cover the window before the reboot.
    it { is_expected.to run_powershell_script('add docker defender path exclusions') }
    it { is_expected.to_not run_powershell_script('disable defender real-time monitoring') }

    it 'uninstalls the feature and asks for a reboot' do
      expect(chef_run).to remove_windows_feature_powershell('Windows-Defender')
      expect(chef_run.windows_feature_powershell('Windows-Defender'))
        .to notify('reboot[cinc-omnibus docker host]').to(:request_reboot).immediately
    end
  end

  context 'with Tamper Protection on' do
    before { stub_guard(:windows_defender_tamper_protected?, true) }

    # Set-MpPreference would be silently ignored, so warn once instead of
    # re-running every converge.
    it { is_expected.to write_log('defender tamper protection blocks Set-MpPreference') }
    it { is_expected.to_not run_powershell_script('disable defender real-time monitoring') }
  end

  context 'with Defender removed' do
    before { stub_guard(:windows_defender_present?, false) }

    it { is_expected.to_not run_powershell_script('add docker defender path exclusions') }
    it { is_expected.to_not run_powershell_script('disable defender real-time monitoring') }
  end

  context 'with manage_defender false' do
    recipe do
      cinc_omnibus_docker_host 'default' do
        manage_defender false
      end
    end

    it { is_expected.to_not run_powershell_script('add docker defender path exclusions') }
    it { is_expected.to_not run_powershell_script('disable defender real-time monitoring') }
    it { is_expected.to install_chocolatey_package('docker-engine') }
  end

  context 'with docker installed outside chocolatey' do
    before { stub_guard(:windows_docker_installed_outside_chocolatey?, true) }

    # e.g. Microsoft's install-docker-ce.ps1 or the GitHub Actions image.
    it { is_expected.to_not install_chocolatey_package('docker-engine') }
    it { is_expected.to start_service('docker') }
  end

  context 'with a pinned engine version' do
    recipe do
      cinc_omnibus_docker_host 'default' do
        docker_engine_version '29.8.1'
      end
    end

    it { is_expected.to install_chocolatey_package('docker-engine').with(version: ['29.8.1']) }
  end

  context 'on linux' do
    platform 'ubuntu', '24.04'

    it { expect { chef_run }.to raise_error(/Windows-only/) }
  end

  context 'on :remove' do
    recipe do
      cinc_omnibus_docker_host 'default' do
        action :remove
      end
    end

    it { is_expected.to stop_service('docker') }
    it { is_expected.to disable_service('docker') }
    it { is_expected.to delete_file('C:/ProgramData/docker/config/daemon.json') }
    it { is_expected.to run_powershell_script('remove docker defender path exclusions') }
    it { is_expected.to run_powershell_script('enable defender real-time monitoring') }
    # Package removal is opt-in.
    it { is_expected.to_not remove_chocolatey_package('docker-engine') }
  end

  context 'on :remove with remove_package' do
    recipe do
      cinc_omnibus_docker_host 'default' do
        remove_package true
        action :remove
      end
    end

    it { is_expected.to remove_chocolatey_package('docker-engine') }
  end
end
