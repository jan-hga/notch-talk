//
//  NewChatView.swift
//  ClaudeIsland
//
//  Empty chat for a new conversation. The workspace (folder) sits at the top
//  and can be changed. The first message starts Claude in the background,
//  no terminal window involved.
//

import AppKit
import SwiftUI

struct NewChatView: View {
    @ObservedObject var sessionMonitor: ClaudeSessionMonitor
    @ObservedObject var viewModel: NotchViewModel

    /// Last workspace used; empty means the home folder
    @AppStorage("workingDirectory") private var storedDirectory: String = ""
    @State private var text = ""
    @State private var isStarting = false
    @State private var failed = false
    @State private var startedSessionId: String?
    @FocusState private var isInputFocused: Bool

    private var workspace: String {
        if !storedDirectory.isEmpty, FileManager.default.fileExists(atPath: storedDirectory) {
            return storedDirectory
        }
        return NSHomeDirectory()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer()
            if isStarting {
                startingBar
            } else {
                if failed {
                    Text(L10n.tr("Couldn't start Claude"))
                        .font(.system(size: 12))
                        .foregroundColor(.red.opacity(0.8))
                        .padding(.bottom, 6)
                }
                inputBar
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isInputFocused = true
            }
        }
        .onReceive(sessionMonitor.$instances) { sessions in
            guard let sessionId = startedSessionId,
                  let created = sessions.first(where: { $0.sessionId == sessionId }) else { return }
            viewModel.showChat(for: created)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.exitChat()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)

            WorkspaceChip(name: displayName(workspace), path: shortened(workspace), isEnabled: !isStarting) {
                chooseWorkspace()
            }

            if !storedDirectory.isEmpty && !isStarting {
                Button {
                    storedDirectory = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
                .help(L10n.tr("Remove folder"))
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.2))
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField(L10n.tr("Message Claude..."), text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(.white)
                .focused($isInputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
                .onSubmit { send() }

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(trimmed.isEmpty ? .white.opacity(0.2) : .white.opacity(0.9))
            }
            .buttonStyle(.plain)
            .disabled(trimmed.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.2))
    }

    private var startingBar: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(.white.opacity(0.6))
            Text(L10n.tr("Starting..."))
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.5))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .background(Color.black.opacity(0.2))
    }

    // MARK: - Actions

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func send() {
        let message = trimmed
        guard !message.isEmpty, !isStarting else { return }

        failed = false

        guard let sessionId = BackgroundChats.shared.start(cwd: workspace, firstMessage: message) else {
            failed = true
            return
        }
        startedSessionId = sessionId
        isStarting = true

        // The session reports through the hooks; if it never shows up, let the user retry
        Task {
            try? await Task.sleep(for: .seconds(30))
            if isStarting && viewModel.contentType == .newChat {
                BackgroundChats.shared.stop(sessionId: sessionId)
                startedSessionId = nil
                isStarting = false
                failed = true
            }
        }
    }

    private func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.title = L10n.tr("Choose project folder")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: workspace)

        let response = NotchModalGuard.run(panel)

        if response == .OK, let url = panel.url {
            storedDirectory = url.path
        }
    }

    // MARK: - Helpers

    private func displayName(_ path: String) -> String {
        path == NSHomeDirectory() ? "~" : URL(fileURLWithPath: path).lastPathComponent
    }

    private func shortened(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

}

/// Folder name with a chevron; pressing it opens the folder picker
private struct WorkspaceChip: View {
    let name: String
    let path: String
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))

                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(isHovered ? 1.0 : 0.85))
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(isHovered ? 0.14 : 0.08)))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(path)
        .onHover { isHovered = $0 }
    }
}
