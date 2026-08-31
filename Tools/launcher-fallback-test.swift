// Compile: swiftc -swift-version 6 Spotter/Core/LauncherFallback.swift Spotter/Core/TerminalCommandRunner.swift Tools/launcher-fallback-test.swift -o /tmp/launcher-fallback-test && /tmp/launcher-fallback-test
import Foundation

@main
struct LauncherFallbackTests {
    static func main() {
        var failures = 0
        func check(_ message: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(message)")
            } else {
                failures += 1
                print("FAIL  \(message)")
            }
        }

        check("empty input has no fallbacks", LauncherFallback.suggestions(for: " \n ").isEmpty)

        let suggestions = LauncherFallback.suggestions(for: "  echo \"你好\" && pwd  \n")
        check("all four fallbacks are present", suggestions.count == 4)
        check(
            "fallback order is stable",
            suggestions.map(\.action) == [.aiChat, .chatGPT, .terminal, .fileSearch])
        check(
            "outer whitespace is trimmed without changing the command",
            suggestions.allSatisfy { $0.query == "echo \"你好\" && pwd" })
        check("fallback IDs are unique", Set(suggestions.map(\.id)).count == suggestions.count)

        let hostile = "printf '%s\\n' \"$HOME\"; echo \\ done"
        let terminal = TerminalCommandRunner.invocation(for: hostile, terminal: .terminal)
        check("Terminal invocation exists for non-empty input", terminal != nil)
        check("Terminal handoff goes through osascript", terminal?.executablePath == "/usr/bin/osascript")
        check(
            "Terminal command is passed after the argv separator",
            terminal?.arguments.suffix(2).first == "--")
        check("Terminal command stays one exact argv value", terminal?.arguments.last == hostile)
        check(
            "empty Terminal input is rejected",
            TerminalCommandRunner.invocation(for: " \n ", terminal: .terminal) == nil)

        let iterm = TerminalCommandRunner.invocation(for: hostile, terminal: .iterm)
        check("iTerm2 handoff goes through osascript", iterm?.executablePath == "/usr/bin/osascript")
        check("iTerm2 command stays one exact argv value", iterm?.arguments.last == hostile)
        check(
            "iTerm2 script never interpolates the command",
            iterm?.arguments.contains { $0.contains(hostile) && $0 != hostile } == false)

        let ghostty = TerminalCommandRunner.invocation(for: hostile, terminal: .ghostty)
        check("Ghostty launches through open", ghostty?.executablePath == "/usr/bin/open")
        check(
            "Ghostty gets the command as its own shell input",
            ghostty?.arguments.contains("-e") == true
                && ghostty?.arguments.last?.hasPrefix(hostile) == true)
        check(
            "Ghostty keeps the window alive after the command",
            ghostty?.arguments.last?.hasSuffix("exec /bin/zsh -i") == true)

        let kitty = TerminalCommandRunner.invocation(for: hostile, terminal: .kitty)
        check("kitty launches through open without -e", kitty?.arguments.contains("-e") == false)

        print(failures == 0 ? "\nLauncher Fallbacks: ALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
