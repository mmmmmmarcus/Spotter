# QuickTime Recording plugin

Enabled by default.

QuickTime Recording exposes three no-view commands: New Screen Recording, New Audio Recording and New
Movie Recording. Each command sends the corresponding AppleScript to QuickTime Player through the
system `/usr/bin/osascript`, invokes QuickTime's native File-menu command, opens the matching recorder
without starting capture, then exits; there is no persistent helper, monitor or recording state in
Spotter. A short timeout prevents a modal QuickTime panel from retaining a Spotter task indefinitely.

macOS asks Spotter for Automation access to System Events on first use. QuickTime Player independently owns Screen &
System Audio, Microphone and Camera grants. Failures are reported in a native alert with a direct link
to Automation Settings. Each command has its own stable global shortcut action.
