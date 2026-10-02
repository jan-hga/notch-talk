//
//  TerminalLauncher.swift
//  ClaudeIsland
//
//  Starts a new Claude Code session in a terminal window
//

import AppKit
import Foundation
import os.log

enum TerminalLauncher {
    nonisolated static let logger = Logger(subsystem: "com.claudeisland", category: "TerminalLauncher")

    /// Open a terminal window in `directory` and run `claude` there.
    /// Uses iTerm2 when it is running, otherwise Terminal.app.
    @MainActor
    static func startClaude(in directory: String) async -> Bool {
        let iTermRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.googlecode.iterm2"
        }
        let script = iTermRunning ? iTermScript : terminalScript

        let result = await ProcessExecutor.shared.runWithResult(
            "/usr/bin/osascript",
            arguments: ["-e", script, "--", directory]
        )
        switch result {
        case .success(let output) where output.exitCode == 0:
            return true
        case .success(let output):
            logger.error("Launch failed: \(output.stderr ?? "", privacy: .public)")
            return false
        case .failure(let error):
            logger.error("Launch failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// The directory is passed as argv and quoted by AppleScript, so spaces and quotes are safe
    private static let terminalScript = """
    on run argv
        set cmd to "cd " & quoted form of item 1 of argv & " && claude"
        tell application "Terminal"
            activate
            do script cmd
        end tell
    end run
    """

    private static let iTermScript = """
    on run argv
        set cmd to "cd " & quoted form of item 1 of argv & " && claude"
        tell application "iTerm2"
            activate
            set newWindow to (create window with default profile)
            tell current session of newWindow to write text cmd
        end tell
    end run
    """
}
