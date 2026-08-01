# QuickTime Recording plugin

QuickTime Recording exposes three no-view commands: New Screen Recording, New Audio Recording and New
Movie Recording. Each command sends the corresponding AppleScript to QuickTime Player through the
system `/usr/bin/osascript`, then exits; there is no persistent helper, monitor or recording state in
Spotter.

macOS asks Spotter for Automation access on first use. QuickTime Player independently owns Screen &
System Audio, Microphone and Camera grants. Failures are reported in a native alert with a direct link
to Automation Settings. Each command has its own stable global shortcut action.
