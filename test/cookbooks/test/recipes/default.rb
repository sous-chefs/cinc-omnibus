# frozen_string_literal: true

cinc_omnibus_builder 'default' do
  # On macOS the GitLab Runner needs a GUI login (LaunchAgent) and brew/keychain
  # ownership that the headless exec-kitchen runners don't have, and FreeBSD has
  # no GHA runner; both are covered by the unit specs. On Windows it is an idle
  # SYSTEM service until registered, so the Docker host test keeps it.
  manage_gitlab_runner platform?('windows')

  # Kitchen runs on the host itself under the exec driver, so a reboot at the
  # end of the run would kill the session (and a GitHub Actions job). Chef
  # still sees the pending reboot and defers the docker start; on a fresh VM
  # converge, reboot by hand, then converge and verify (see TESTING.md).
  reboot_after_feature_install false

  # The GitHub Actions windows-latest image ships with Hyper-V installed; the
  # resource's guard is covered by the unit specs, and InSpec checks the thing
  # that matters, that Docker still defaults to process isolation.
  allow_hyperv true
end
