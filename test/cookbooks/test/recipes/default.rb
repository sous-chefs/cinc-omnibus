# frozen_string_literal: true

cinc_omnibus_builder 'default' do
  # The GitLab Runner needs a GUI login (macOS LaunchAgent) and brew/keychain
  # ownership that the headless exec-kitchen runners don't have; it's covered by
  # the unit specs instead. Host-prep verification doesn't need it.
  manage_gitlab_runner false
end
