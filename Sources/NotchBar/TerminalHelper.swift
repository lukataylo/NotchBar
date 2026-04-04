import AppKit
import ApplicationServices

/// Shared AppleScript helpers for Terminal.app / iTerm2 interaction.
enum TerminalHelper {
    /// Escape a string for safe embedding in AppleScript double-quoted strings.
    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Open a new terminal tab and run a command.
    /// Tries Terminal.app first, falls back to iTerm2.
    static func runCommand(_ command: String) {
        let escaped = escape(command)
        let script = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if error == nil { return }

        let iTermScript = """
        tell application "iTerm2"
            activate
            tell current window
                create tab with default profile
                tell current session
                    write text "\(escaped)"
                end tell
            end tell
        end tell
        """
        NSAppleScript(source: iTermScript)?.executeAndReturnError(nil)
    }
}
