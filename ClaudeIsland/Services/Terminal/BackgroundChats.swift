//
//  BackgroundChats.swift
//  ClaudeIsland
//
//  Runs Claude Code sessions as background processes without a terminal
//  window, the same way the Claude desktop app does: `claude -p` with
//  stream-json over pipes. The session still reports through the hooks, so it
//  shows up in the notch like any other.
//

import Foundation
import os.log

/// Thread-safe set of session ids this app started itself
enum BackgroundChatRegistry {
    nonisolated(unsafe) private static var ids = Set<String>()
    private nonisolated static let lock = NSLock()

    nonisolated static func contains(_ sessionId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return ids.contains(sessionId)
    }

    nonisolated static func add(_ sessionId: String) {
        lock.lock()
        ids.insert(sessionId)
        lock.unlock()
    }

    nonisolated static func remove(_ sessionId: String) {
        lock.lock()
        ids.remove(sessionId)
        lock.unlock()
    }
}

@MainActor
final class BackgroundChats {
    static let shared = BackgroundChats()

    private var chats: [String: BackgroundChat] = [:]

    private init() {}

    /// Start a new chat in `cwd` with a first message. Returns the session id, or nil if claude could not be launched.
    func start(cwd: String, firstMessage: String) -> String? {
        let sessionId = UUID().uuidString.lowercased()
        guard let chat = BackgroundChat(sessionId: sessionId, cwd: cwd, onExit: { [weak self] in
            Task { @MainActor [weak self] in self?.chats.removeValue(forKey: sessionId) }
        }) else { return nil }

        BackgroundChatRegistry.add(sessionId)
        chats[sessionId] = chat
        chat.send(firstMessage)
        return sessionId
    }

    @discardableResult
    func send(_ text: String, to sessionId: String) -> Bool {
        guard let chat = chats[sessionId] else { return false }
        chat.send(text)
        return true
    }

    func stop(sessionId: String) {
        chats[sessionId]?.terminate()
    }

    /// Called when the app quits; a stopped chat can be resumed later from its saved history
    func terminateAll() {
        chats.values.forEach { $0.terminate() }
    }
}

/// One `claude` process. Output is drained so the pipe never fills up.
final class BackgroundChat: @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.claudeisland", category: "BackgroundChat")

    private let sessionId: String
    private let process = Process()
    private let stdin = Pipe()
    private let stdout = Pipe()
    private let stderr = Pipe()
    private let writeQueue = DispatchQueue(label: "background-chat.write")
    private var buffer = Data()

    init?(sessionId: String, cwd: String, onExit: @escaping @Sendable () -> Void) {
        self.sessionId = sessionId

        // A login shell gives claude the user's normal PATH (python3 for the hooks, node, ...)
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            "-l", "-c", "exec claude \"$@\"", "claude",
            "-p",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--verbose",
            "--permission-prompt-tool", "stdio",
            "--session-id", sessionId
        ]
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            self?.consume(data)
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            if handle.availableData.isEmpty { handle.readabilityHandler = nil }
        }
        process.terminationHandler = { _ in
            BackgroundChatRegistry.remove(sessionId)
            onExit()
        }

        do {
            try process.run()
        } catch {
            Self.logger.error("Could not start claude: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Send one user message (a queued message is handled after the current turn)
    func send(_ text: String) {
        let message: [String: Any] = [
            "type": "user",
            "message": ["role": "user", "content": text]
        ]
        write(message)
    }

    func terminate() {
        try? stdin.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
    }

    // MARK: - Output

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            handle(line: Data(line))
        }
    }

    private func handle(line: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              json["type"] as? String == "control_request",
              let requestId = json["request_id"] as? String,
              let request = json["request"] as? [String: Any],
              request["subtype"] as? String == "can_use_tool" else { return }

        // The notch's approval buttons answer through the PermissionRequest hook before this
        // request is sent. If it still arrives, nobody approved in time, so deny.
        respond(requestId: requestId, behavior: "deny", message: "Not approved in Notch Talk.")
    }

    private func respond(requestId: String, behavior: String, message: String) {
        write([
            "type": "control_response",
            "response": [
                "subtype": "success",
                "request_id": requestId,
                "response": ["behavior": behavior, "message": message]
            ]
        ])
    }

    private func write(_ object: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0A)
        writeQueue.async { [stdin] in
            try? stdin.fileHandleForWriting.write(contentsOf: data)
        }
    }
}
