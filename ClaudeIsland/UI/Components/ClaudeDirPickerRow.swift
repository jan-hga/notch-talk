//
//  ClaudeDirPickerRow.swift
//  ClaudeIsland
//
//  Settings row for choosing Claude's config directory. Shows a menu with
//  "Auto-detect" and "Choose folder..." options. Default falls back to
//  CLAUDE_CONFIG_DIR, ~/.config/claude/, then ~/.claude/.
//

import AppKit
import SwiftUI

struct ClaudeDirPickerRow: View {
    @State private var currentValue: String = AppSettings.claudeDirectoryName
    @State private var isHovered: Bool = false

    var body: some View {
        Menu {
            Button {
                applyChoice(path: "")
            } label: {
                if isCustom {
                    Text("Auto-detect")
                } else {
                    Label("Auto-detect", systemImage: "checkmark")
                }
            }

            Divider()

            Button("Choose folder…") {
                openFolderPicker()
            }

            if isCustom {
                Divider()
                Text("Current: \(displayValue)")
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .font(.system(size: 12))
                    .foregroundColor(textColor)
                    .frame(width: 16)

                Text("Claude Directory")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(textColor)

                Spacer()

                Text(displayValue)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onAppear { currentValue = AppSettings.claudeDirectoryName }
    }

    // MARK: - Presentation

    private var textColor: Color {
        .white.opacity(isHovered ? 1.0 : 0.7)
    }

    private var isCustom: Bool {
        !currentValue.isEmpty && currentValue != ".claude"
    }

    /// Human-readable representation of the active directory — the user's
    /// path shortened to `~/…` when under the home dir, or "Auto-detect"
    /// when no override is set.
    private var displayValue: String {
        guard isCustom else { return "Auto-detect" }

        let path = currentValue.hasPrefix("/")
            ? currentValue
            : NSHomeDirectory() + "/" + currentValue

        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    // MARK: - Actions

    private func openFolderPicker() {
        let panel = NSOpenPanel()
        panel.title = "Choose Claude Config Directory"
        panel.message = "Select the folder Claude Code uses (typically ~/.claude or ~/.config/claude)."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.canCreateDirectories = false
        panel.directoryURL = ClaudePaths.claudeDir

        // The notch sits at .mainMenu + 3 (27) and would block/obscure the
        // picker. Drop it for the duration of the modal so the panel is on
        // top and fully interactive, then restore.
        let notchWindow = NSApp.windows.first { $0 is NotchPanel }
        let originalLevel = notchWindow?.level ?? (.mainMenu + 3)
        let wasIgnoring = notchWindow?.ignoresMouseEvents ?? true
        notchWindow?.level = .normal
        notchWindow?.ignoresMouseEvents = true

        let response = panel.runModal()

        notchWindow?.level = originalLevel
        notchWindow?.ignoresMouseEvents = wasIgnoring

        if response == .OK, let url = panel.url {
            applyChoice(path: url.path)
        }
    }

    private func applyChoice(path: String) {
        currentValue = path
        AppSettings.claudeDirectoryName = path
        ClaudePaths.invalidateCache()
        HookInstaller.installIfNeeded()
    }
}
