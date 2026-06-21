-- Forces the macOS TCC "Automation" prompt that lets gitlab-runner control
-- Finder (omnibus drives Finder when styling the .dmg window). Run this ONCE,
-- at the console, as the build user, after the cookbook first re-signs the
-- gitlab-runner binary with the stable signing identity, then click "Allow".
-- Because the binary is re-signed with that same identity on every upgrade,
-- the grant then persists across `brew upgrade gitlab-runner` and the prompt
-- does not reappear.
tell application "Finder"
	reopen
	activate
	set selection to {}
end tell
