# Testing

Please refer to [the community cookbook documentation on testing](https://github.com/chef-cookbooks/community_cookbook_documentation/blob/main/TESTING.MD).

## Windows: manual test on an OpenStack VM

The GitHub Actions `windows-latest` image already ships Docker with the Containers feature enabled,
so CI only exercises the adopt-existing-docker path. The Containers feature install, the reboot
gate, the Chocolatey `docker-engine` install and the runner service are only reached on a fresh
Windows Server, which is what this walkthrough covers. Kitchen runs **on the VM itself** through
`kitchen.exec.yml` (kitchen-openstack has no WinRM support, and the OSL Windows images hand out no
admin password), exactly as the GHA job does.

1. Boot a fresh `Windows 2022 Server` (or `Windows 2025 Server`) instance with at least 4 vCPUs,
   8 GB RAM and 80 GB of disk (the builder image alone is 8 to 12 GB, plus a writable layer per
   running build). Hyper-V must not be enabled; process isolation needs no hypervisor.

   ```sh
   openstack server create --image 'Windows 2022 Server' --flavor <flavor> \
     --network "$OS_NETWORK_REF" --key-name "$OS_SSH_KEYPAIR" cinc-omnibus-win
   ```

2. Log in over RDP, then from an elevated PowerShell install Cinc Workstation and check out the
   branch under test. Workstation bundles Git for Windows and `cinc exec` puts it on PATH, so
   nothing else needs installing:

   ```powershell
   [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
   . { Invoke-WebRequest -UseBasicParsing -Uri https://omnitruck.cinc.sh/install.ps1 } | Invoke-Expression
   install -project cinc-workstation
   # The MSI adds C:\cinc-project\cinc-workstation\bin to the machine PATH; this shell predates that.
   $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
   cinc exec git clone -b <branch> https://github.com/sous-chefs/cinc-omnibus.git C:\cinc-omnibus
   cd C:\cinc-omnibus
   $env:KITCHEN_LOCAL_YAML = 'kitchen.exec.yml'
   $env:CHEF_LICENSE = 'accept-no-persist'
   ```

3. First converge. The test recipe sets `reboot_after_feature_install false` so Kitchen's own
   session survives; expect the Containers feature to install and the run to end with the
   `docker start deferred until reboot` warning, since Chef sees the pending reboot:

   ```powershell
   cinc exec kitchen converge default-windows-latest
   Restart-Computer
   ```

4. After the reboot, converge again and verify. The second run starts Docker and the runner
   service; the InSpec controls check the feature, the `docker` service, process isolation, the
   Defender exclusions and real-time state, and the `gitlab-runner` service:

   ```powershell
   cinc exec kitchen converge default-windows-latest
   cinc exec kitchen verify default-windows-latest
   ```

5. Prove a container actually runs under process isolation, then (optionally) register the two
   runners by hand from `runner-config.example.toml` in the docker-images repository and run a
   real product job:

   ```powershell
   docker run --rm --isolation=process mcr.microsoft.com/windows/servercore:ltsc2022 cmd /c ver
   ```

6. Delete the instance when done: `openstack server delete cinc-omnibus-win`.

To exercise the automatic reboot path instead, run the bootstrap (`bootstrap/install.ps1` with
`REPO_BRANCH` set) on a second fresh VM: it converges the resource with `reboot_after_feature_install`
at its default, so Chef runs `shutdown /r /t 0` as the run ends and exits with code 35.
