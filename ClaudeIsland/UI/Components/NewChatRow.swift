//
//  NewChatRow.swift
//  ClaudeIsland
//
//  "New chat" row: the working folder is chosen once, and the terminal only
//  opens when the user presses the start button.
//

import AppKit
import SwiftUI

struct NewChatRow: View {
    @AppStorage("workingDirectory") private var workingDirectory: String = ""
    @State private var isExpanded = false
    @State private var isHovered = false

    private var hasFolder: Bool {
        !workingDirectory.isEmpty && FileManager.default.fileExists(atPath: workingDirectory)
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 12))
                        .foregroundColor(textColor)
                        .frame(width: 16)

                    Text(L10n.tr("New chat"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(textColor)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
                )
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if hasFolder {
                        folderLine
                        ChatActionButton(title: L10n.tr("Start in Terminal"), isPrimary: true) {
                            Task { _ = await TerminalLauncher.startClaude(in: workingDirectory) }
                        }
                    } else {
                        ChatActionButton(title: L10n.tr("Choose folder…"), isPrimary: true) {
                            chooseFolder()
                        }
                    }
                }
                .padding(.leading, 28)
                .padding(.trailing, 12)
                .padding(.top, 4)
                .padding(.bottom, 4)
            }
        }
    }

    private var textColor: Color {
        .white.opacity(isHovered ? 1.0 : 0.7)
    }

    private var folderLine: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.tr("Working folder"))
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.35))
                Text(shortened(workingDirectory))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer()
            Button {
                chooseFolder()
            } label: {
                Text(L10n.tr("Change"))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
    }

    private func shortened(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = L10n.tr("Choose project folder")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: hasFolder ? workingDirectory : NSHomeDirectory())

        // The notch sits above normal windows and would cover the picker
        let notchWindow = NSApp.windows.first { $0 is NotchPanel }
        let originalLevel = notchWindow?.level ?? (.mainMenu + 3)
        let wasIgnoring = notchWindow?.ignoresMouseEvents ?? true
        notchWindow?.level = .normal
        notchWindow?.ignoresMouseEvents = true

        let response = panel.runModal()

        notchWindow?.level = originalLevel
        notchWindow?.ignoresMouseEvents = wasIgnoring

        if response == .OK, let url = panel.url {
            workingDirectory = url.path
        }
    }
}

private struct ChatActionButton: View {
    let title: String
    let isPrimary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isPrimary ? .black : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.white.opacity(isPrimary ? 0.95 : 0.1)))
        }
        .buttonStyle(.plain)
    }
}
