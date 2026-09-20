# frozen_string_literal: true

require 'json'

provides :cinc_omnibus_docker_host
unified_mode true

include CincOmnibus::Cookbook::Helpers

property :instance_name, String, name_property: true
property :docker_engine_version, [String, nil]
property :docker_data_root, [String, nil]
property :docker_daemon_config, Hash, default: {}
property :containers_feature_source, [String, nil]
property :reboot_after_feature_install, [true, false], default: true
property :allow_hyperv, [true, false], default: false
property :manage_defender, [true, false], default: true
property :defender_exclusions, Array, default: lazy { windows_docker_defender_exclusions(docker_data_root) }
property :defender_process_exclusions, Array, default: []
property :disable_defender_realtime, [true, false], default: true
property :remove_defender, [true, false], default: false
property :defender_feature_name, String, default: 'Windows-Defender'
property :remove_package, [true, false], default: false

default_action :create

action_class do
  include CincOmnibus::Cookbook::Helpers

  # daemon.json is only written when there is something to put in it, so a
  # hand-managed file on an existing host is left alone.
  def docker_daemon_config
    config = new_resource.docker_daemon_config.dup
    config['data-root'] = new_resource.docker_data_root if new_resource.docker_data_root
    config
  end
end

# Prepares a Windows Server host to run omnibus builds in Windows containers
# (cincproject/omnibus-windows under the docker-windows executor): the
# Containers feature, Defender out of the build path, and docker-engine.
action :create do
  raise 'cinc_omnibus_docker_host is Windows-only' unless windows?

  if !new_resource.allow_hyperv && windows_hyperv_installed?
    raise 'Hyper-V is installed. Process isolation needs no hypervisor, and with ' \
          'Hyper-V present Server Standard caps Hyper-V-isolated containers at two. ' \
          'Remove it (Uninstall-WindowsFeature -Name Hyper-V -Restart) or set allow_hyperv true.'
  end

  # Both feature changes below need a reboot before Docker can start; the
  # request fires at the end of the run. Declared first: an immediate
  # notification in unified mode needs its target already in the collection.
  reboot 'cinc-omnibus docker host' do
    reason 'Windows feature change (Containers/Defender) needs a reboot before Docker can start'
    action :nothing
  end

  # The choco docker-engine package does not enable this, unlike Microsoft's
  # install-docker-ce.ps1: Docker installs cleanly and then fails to start.
  # `source` covers images with the payload stripped (InstallState Removed),
  # e.g. "wim:D:\sources\install.wim:4".
  windows_feature_powershell 'Containers' do
    source new_resource.containers_feature_source if new_resource.containers_feature_source
    notifies :request_reboot, 'reboot[cinc-omnibus docker host]', :immediately if new_resource.reboot_after_feature_install
  end

  if new_resource.manage_defender
    # Exclusions first, even when removing Defender, so the window before the
    # reboot is covered. Paths with spaces (Program Files) are quoted here;
    # Chef's windows_defender_exclusion does not quote them.
    unless new_resource.defender_exclusions.empty?
      missing = windows_defender_missing_exclusions('ExclusionPath', new_resource.defender_exclusions)

      powershell_script 'add docker defender path exclusions' do
        code "#{missing}; if ($missing) { Add-MpPreference -ExclusionPath $missing }"
        only_if "#{missing}; [bool]$missing"
        only_if { windows_defender_present? }
      end
    end

    # A container's writable layer is a mounted VHDX, so path exclusions never
    # reach the files the compilers touch; process exclusions by image name
    # (gcc.exe, ld.exe, bash.exe, ...) are the lever for that.
    unless new_resource.defender_process_exclusions.empty?
      missing = windows_defender_missing_exclusions('ExclusionProcess', new_resource.defender_process_exclusions)

      powershell_script 'add docker defender process exclusions' do
        code "#{missing}; if ($missing) { Add-MpPreference -ExclusionProcess $missing }"
        only_if "#{missing}; [bool]$missing"
        only_if { windows_defender_present? }
      end
    end

    if new_resource.remove_defender
      # No on-host AV at all afterwards: reasonable on an isolated build host,
      # not on anything general-purpose. Uninstall-WindowsFeature is not
      # blocked by Tamper Protection. A no-op once the feature is gone.
      windows_feature_powershell new_resource.defender_feature_name do
        action :remove
        notifies :request_reboot, 'reboot[cinc-omnibus docker host]', :immediately if new_resource.reboot_after_feature_install
      end
    elsif new_resource.disable_defender_realtime
      # Chef's windows_defender resource maps realtime_protection to
      # DisableIOAVProtection, not DisableRealtimeMonitoring, hence the direct
      # Set-MpPreference. Tamper Protection silently ignores it, so warn and
      # skip instead of re-running every converge.
      log 'defender tamper protection blocks Set-MpPreference' do
        message 'Tamper Protection is enabled: real-time monitoring stays on. Turn it off in the ' \
                'Windows Security UI or Intune, or set remove_defender true (feature removal is not blocked).'
        level :warn
        only_if { windows_defender_present? && windows_defender_tamper_protected? }
      end

      powershell_script 'disable defender real-time monitoring' do
        code 'Set-MpPreference -DisableRealtimeMonitoring $true -DisableBehaviorMonitoring $true'
        not_if '$p = Get-MpPreference; [bool]($p.DisableRealtimeMonitoring -and $p.DisableBehaviorMonitoring)'
        not_if { windows_defender_tamper_protected? }
        only_if { windows_defender_present? }
      end
    end
  end

  chocolatey_installer 'install'

  # The package registers the docker service (start=auto) without starting it.
  # Skipped when a docker service chocolatey does not own already exists.
  chocolatey_package 'docker-engine' do
    version new_resource.docker_engine_version if new_resource.docker_engine_version
    not_if { windows_docker_installed_outside_chocolatey? }
  end

  # Written before the first start so nothing has to move. A custom data-root
  # must be on c: or a bare drive letter for the docker-windows executor's
  # builds_dir/cache_dir/volumes; the runner docs carry the details.
  daemon_config = docker_daemon_config

  unless daemon_config.empty?
    directory ::File.dirname(windows_docker_daemon_config_path) do
      recursive true
    end

    directory new_resource.docker_data_root do
      recursive true
    end if new_resource.docker_data_root

    file windows_docker_daemon_config_path do
      content "#{JSON.pretty_generate(daemon_config)}\n"
      notifies :restart, 'service[docker]', :delayed
    end
  end

  # dockerd cannot start until the Containers feature is live, i.e. after the
  # reboot; the next converge picks it up.
  log 'docker start deferred until reboot' do
    message 'A reboot is pending; the docker service will be started on the next converge.'
    level :warn
    only_if { windows_reboot_pending? }
  end

  service 'docker' do
    action [:enable, :start]
    not_if { windows_reboot_pending? }
  end
end

action :remove do
  raise 'cinc_omnibus_docker_host is Windows-only' unless windows?

  service 'docker' do
    action [:stop, :disable]
  end

  file windows_docker_daemon_config_path do
    action :delete
  end

  if new_resource.manage_defender
    unless new_resource.defender_exclusions.empty?
      powershell_script 'remove docker defender path exclusions' do
        code "Remove-MpPreference -ExclusionPath #{powershell_string_array(new_resource.defender_exclusions)}"
        only_if { windows_defender_present? }
      end
    end

    unless new_resource.defender_process_exclusions.empty?
      powershell_script 'remove docker defender process exclusions' do
        code "Remove-MpPreference -ExclusionProcess #{powershell_string_array(new_resource.defender_process_exclusions)}"
        only_if { windows_defender_present? }
      end
    end

    # Feature removal is not reversed here; reinstalling Defender is a
    # deliberate operator step.
    if new_resource.disable_defender_realtime && !new_resource.remove_defender
      powershell_script 'enable defender real-time monitoring' do
        code 'Set-MpPreference -DisableRealtimeMonitoring $false -DisableBehaviorMonitoring $false'
        only_if '$p = Get-MpPreference; [bool]($p.DisableRealtimeMonitoring -or $p.DisableBehaviorMonitoring)'
        not_if { windows_defender_tamper_protected? }
        only_if { windows_defender_present? }
      end
    end
  end

  chocolatey_package 'docker-engine' do
    action :remove
  end if new_resource.remove_package
end
