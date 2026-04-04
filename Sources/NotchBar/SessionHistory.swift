import Foundation
import os.log

private let log = Logger(subsystem: "com.notchclaude", category: "history")

struct PastSession: Identifiable {
    let id: String  // session directory name
    let providerID: AgentProviderID
    let projectPath: String
    let projectName: String
    let lastModified: Date
}

class SessionHistoryManager {
    static let shared = SessionHistoryManager()

    /// Scan ~/.claude/projects/ for past session directories
    func listPastSessions() -> [PastSession] {
        let fm = FileManager.default
        let projectsDir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        guard let entries = try? fm.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            log.info("No projects directory found at \(projectsDir.path)")
            return []
        }

        var sessions: [PastSession] = []
        for entry in entries {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: entry.path, isDirectory: &isDir), isDir.boolValue else { continue }

            let name = entry.lastPathComponent
            // Project dirs are encoded paths like "-Users-foo-project"
            let decoded = name.replacingOccurrences(of: "-", with: "/")
            let projectPath = decoded.hasPrefix("/") ? decoded : "/\(decoded)"
            let projectName = (projectPath as NSString).lastPathComponent

            let modDate = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast

            sessions.append(PastSession(
                id: name,
                providerID: .claude,
                projectPath: projectPath,
                projectName: projectName,
                lastModified: modDate
            ))
        }

        return sessions.sorted { $0.lastModified > $1.lastModified }
    }

    /// Resume a session by opening a new terminal tab with claude --resume
    func resumeSession(_ session: PastSession) {
        let script = """
        tell application "Terminal"
            activate
            do script "cd \\"\(session.projectPath)\\" && claude --resume"
        end tell
        """
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
        if err != nil {
            // Try iTerm2
            let itermScript = """
            tell application "iTerm2"
                activate
                tell current window
                    create tab with default profile
                    tell current session
                        write text "cd \\"\(session.projectPath)\\" && claude --resume"
                    end tell
                end tell
            end tell
            """
            NSAppleScript(source: itermScript)?.executeAndReturnError(nil)
        }
    }
}
