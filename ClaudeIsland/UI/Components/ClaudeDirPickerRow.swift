//
//  ClaudeDirPickerRow.swift
//  ClaudeIsland
//
//  Lets users configure the Claude config directory name (e.g. ".claude-internal"
//  for enterprise/custom Claude distributions). Defaults to ".claude".
//

import SwiftUI

struct ClaudeDirPickerRow: View {
    @State private var dirName: String = AppSettings.claudeDirectoryName
    @State private var isEditing: Bool = false
    @State private var isHovered: Bool = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button {
            isEditing = true
            isFocused = true
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

                if isEditing {
                    TextField("", text: $dirName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 140)
                        .focused($isFocused)
                        .onSubmit { commitEdit() }
                        .onExitCommand { cancelEdit() }
                } else {
                    Text(dirName)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)

                    Image(systemName: "pencil")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onAppear { dirName = AppSettings.claudeDirectoryName }
    }

    private var textColor: Color {
        .white.opacity(isHovered ? 1.0 : 0.7)
    }

    private func commitEdit() {
        let trimmed = dirName.trimmingCharacters(in: .whitespaces)
        dirName = trimmed.isEmpty ? ".claude" : trimmed
        AppSettings.claudeDirectoryName = dirName
        ClaudePaths.invalidateCache()
        HookInstaller.installIfNeeded()
        isEditing = false
        isFocused = false
    }

    private func cancelEdit() {
        dirName = AppSettings.claudeDirectoryName
        isEditing = false
        isFocused = false
    }
}
