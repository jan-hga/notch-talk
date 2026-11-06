//
//  NotchModalGuard.swift
//  ClaudeIsland
//
//  Keeps the notch open while a system folder picker is showing. Clicks inside
//  the picker land outside the notch panel and would otherwise close it.
//

import AppKit

@MainActor
enum NotchModalGuard {
    /// True while a modal picker is on screen; the notch ignores outside clicks
    private(set) static var isActive = false

    /// Run an open panel above the notch without letting the notch close
    static func run(_ panel: NSOpenPanel) -> NSApplication.ModalResponse {
        runModal { panel.runModal() }
    }

    /// Run an alert above the notch (the notch would otherwise cover it)
    static func run(_ alert: NSAlert) -> NSApplication.ModalResponse {
        runModal { alert.runModal() }
    }

    static func runModal<T>(_ body: () -> T) -> T {
        // The notch sits at .mainMenu + 3 and would cover the panel, so lower
        // it and let clicks pass through while the panel is modal.
        let notchWindow = NSApp.windows.first { $0 is NotchPanel }
        let originalLevel = notchWindow?.level ?? (.mainMenu + 3)
        let wasIgnoring = notchWindow?.ignoresMouseEvents ?? true
        notchWindow?.level = .normal
        notchWindow?.ignoresMouseEvents = true
        isActive = true

        let response = body()

        isActive = false
        notchWindow?.level = originalLevel
        notchWindow?.ignoresMouseEvents = wasIgnoring
        return response
    }
}
