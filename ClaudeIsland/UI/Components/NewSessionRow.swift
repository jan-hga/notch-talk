//
//  NewSessionRow.swift
//  ClaudeIsland
//
//  Row that starts a new Claude Code session in a chosen folder
//

import AppKit
import SwiftUI

struct NewSessionRow: View {
    /// Folders of existing sessions, most recent first
    let recentDirectories: [String]

    @State private var isExpanded = false
    @State private var isHovered = false

    private var shownDirectories: [String] {
        var seen = Set<String>()
        return recentDirectories
            .filter { seen.insert($0).inserted }
            .prefix(4)
            .map { $0 }
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

                    Text(L10n.tr("New session"))
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
                VStack(spacing: 2) {
                    ForEach(shownDirectories, id: \.self) { directory in
                        NewSessionOption(label: displayName(for: directory), sublabel: shortened(directory)) {
                            start(in: directory)
                        }
                    }
                    NewSessionOption(label: L10n.tr("Home folder"), sublabel: "~") {
                        start(in: NSHomeDirectory())
                    }
                    NewSessionOption(label: L10n.tr("Choose folder…"), sublabel: nil) {
                        chooseFolder()
                    }
                }
                .padding(.leading, 28)
                .padding(.top, 4)
            }
        }
    }

    private var textColor: Color {
        .white.opacity(isHovered ? 1.0 : 0.7)
    }

    private func displayName(for directory: String) -> String {
        URL(fileURLWithPath: directory).lastPathComponent
    }

    private func shortened(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private func start(in directory: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            isExpanded = false
        }
        Task {
            _ = await TerminalLauncher.startClaude(in: directory)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = L10n.tr("Choose project folder")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())

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
            start(in: url.path)
        }
    }
}

private struct NewSessionOption: View {
    let label: String
    let sublabel: String?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(isHovered ? 1.0 : 0.7))
                    .lineLimit(1)

                Spacer()

                if let sublabel {
                    Text(sublabel)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.white.opacity(0.06) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
