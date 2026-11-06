//
//  KeepAwakeManager.swift
//  ClaudeIsland
//
//  "Keep Mac Awake": lets Claude keep working with the lid closed.
//
//  An IOPMAssertion alone does not stop the sleep that closing the lid
//  triggers, so this uses `pmset -a disablesleep 1`, which needs root. The
//  first time the setting is turned on, macOS asks once for an administrator
//  password to install a sudoers rule that allows exactly
//  `pmset -a disablesleep 0|1` without a password. After that the app can
//  switch it silently. When the app quits, or the setting is turned off,
//  sleep is enabled again.
//
//  While it is on and the lid is closed, the built-in display is dimmed to its
//  lowest brightness; opening the lid restores the previous brightness.
//

import AppKit
import Combine
import CoreGraphics
import Foundation
import IOKit
import IOKit.pwr_mgt

@MainActor
final class KeepAwakeManager: ObservableObject {
    static let shared = KeepAwakeManager()

    /// Whether the setting is on (persisted)
    @Published private(set) var isEnabled: Bool = AppSettings.keepMacAwake
    /// True while the admin prompt / pmset call is running
    @Published private(set) var isBusy: Bool = false

    nonisolated private static let sudoersPath = "/etc/sudoers.d/notch-talk"
    nonisolated private static let pmsetPath = "/usr/bin/pmset"
    nonisolated private static let sudoPath = "/usr/bin/sudo"

    private var idleAssertion: IOPMAssertionID = 0
    private var lidTimer: Timer?
    private var lidWasClosed = false
    private var savedBrightness: Float?

    private init() {}

    // MARK: - Lifecycle

    /// Call once at launch: re-applies the saved setting, or clears a
    /// `disablesleep` that a crash may have left behind.
    func start() {
        if isEnabled {
            Task { await activate(promptIfNeeded: false) }
        } else {
            Task.detached {
                if Self.sleepCurrentlyDisabled() {
                    _ = Self.runPmset(disable: false)
                }
            }
        }
    }

    /// Call from applicationWillTerminate: always give the Mac its sleep back.
    func shutdown() {
        stopLidMonitoring()
        restoreBrightness()
        releaseIdleAssertion()
        if isEnabled {
            _ = Self.runPmset(disable: false)
        }
    }

    // MARK: - Toggle

    func toggle() {
        guard !isBusy else { return }
        Task {
            if isEnabled {
                await deactivate()
            } else {
                guard confirmWarning() else { return }
                await activate(promptIfNeeded: true)
            }
        }
    }

    /// Explains the consequences before the setting is turned on.
    /// Returns false if the user cancels.
    private func confirmWarning() -> Bool {
        guard !AppSettings.keepAwakeWarningSuppressed else { return true }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.tr("Turn on Keep Mac Awake?")
        alert.informativeText = [
            L10n.tr("Your Mac will no longer sleep, not even with the lid closed, so Claude can keep working."),
            "",
            "• " + L10n.tr("The battery keeps draining. Use it on power if you can."),
            "• " + L10n.tr("A closed Mac that keeps running can get very hot. Never put it in a bag or sleeve while this is on."),
            "• " + L10n.tr("The display is dimmed to its lowest brightness when you close the lid, but it may not turn off completely."),
            "• " + L10n.tr("The first time, macOS asks once for your administrator password."),
            "",
            L10n.tr("Normal sleep comes back as soon as you turn this off or quit Notch Talk."),
        ].joined(separator: "\n")
        alert.addButton(withTitle: L10n.tr("Turn On"))
        alert.addButton(withTitle: L10n.tr("Cancel"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = L10n.tr("Don't show again")

        let confirmed = alert.runModal() == .alertFirstButtonReturn
        if confirmed, alert.suppressionButton?.state == .on {
            AppSettings.keepAwakeWarningSuppressed = true
        }
        return confirmed
    }

    private func activate(promptIfNeeded: Bool) async {
        isBusy = true
        defer { isBusy = false }

        var ok = await Task.detached { Self.runPmset(disable: true) }.value
        if !ok && promptIfNeeded {
            let installed = await Task.detached { Self.installSudoersRule() }.value
            if installed {
                ok = await Task.detached { Self.runPmset(disable: true) }.value
            }
        }

        // Even without pmset the idle assertion keeps an open Mac awake,
        // but the setting only counts as on if lid-closed sleep is blocked.
        guard ok else {
            if !promptIfNeeded {
                // Launch without the rule present: keep the idle part only
                createIdleAssertion()
                startLidMonitoring()
            } else {
                setEnabled(false)
            }
            return
        }

        createIdleAssertion()
        startLidMonitoring()
        setEnabled(true)
    }

    private func deactivate() async {
        isBusy = true
        defer { isBusy = false }

        stopLidMonitoring()
        restoreBrightness()
        releaseIdleAssertion()
        _ = await Task.detached { Self.runPmset(disable: false) }.value
        setEnabled(false)
    }

    private func setEnabled(_ value: Bool) {
        isEnabled = value
        AppSettings.keepMacAwake = value
    }

    // MARK: - pmset / sudoers

    nonisolated private static func runPmset(disable: Bool) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: sudoPath)
        process.arguments = ["-n", pmsetPath, "-a", "disablesleep", disable ? "1" : "0"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    nonisolated private static func sleepCurrentlyDisabled() -> Bool {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: pmsetPath)
        process.arguments = ["-g"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(data: data, encoding: .utf8) ?? ""
            return output.split(separator: "\n").contains {
                let parts = $0.split(separator: " ", omittingEmptySubsequences: true)
                return parts.count >= 2 && parts[0] == "SleepDisabled" && parts[1] == "1"
            }
        } catch {
            return false
        }
    }

    /// Asks once for an admin password and installs a narrow sudoers rule.
    nonisolated private static func installSudoersRule() -> Bool {
        let user = NSUserName()
        guard !user.isEmpty, user.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "." }) else {
            return false
        }

        let rule = "\(user) ALL=(root) NOPASSWD: \(pmsetPath) -a disablesleep 0, \(pmsetPath) -a disablesleep 1\n"
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("notch-talk-sudoers-\(UUID().uuidString)")
        do {
            try rule.write(to: tempURL, atomically: true, encoding: .utf8)
        } catch {
            return false
        }
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let temp = tempURL.path
        let shell = "/usr/sbin/visudo -cf '\(temp)' && /usr/bin/install -m 0440 -o root -g wheel '\(temp)' '\(sudoersPath)'"
        let prompt = L10n.tr("Notch Talk needs administrator rights once so the Mac can stay awake with the lid closed.")
        let source = "do shell script \"\(escapeAppleScript(shell))\" with prompt \"\(escapeAppleScript(prompt))\" with administrator privileges"

        let succeeded: Bool = DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                NSApp.activate(ignoringOtherApps: true)
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                return result != nil && error == nil
            }
        }
        return succeeded
    }

    nonisolated private static func escapeAppleScript(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    // MARK: - Idle sleep assertion

    private func createIdleAssertion() {
        guard idleAssertion == 0 else { return }
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Notch Talk: Keep Mac Awake" as CFString,
            &id
        )
        if result == kIOReturnSuccess {
            idleAssertion = id
        }
    }

    private func releaseIdleAssertion() {
        guard idleAssertion != 0 else { return }
        IOPMAssertionRelease(idleAssertion)
        idleAssertion = 0
    }

    // MARK: - Lid monitoring

    private func startLidMonitoring() {
        guard lidTimer == nil else { return }
        lidWasClosed = Self.isLidClosed()
        if lidWasClosed { dimDisplay() }
        lidTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkLid() }
        }
    }

    private func stopLidMonitoring() {
        lidTimer?.invalidate()
        lidTimer = nil
        lidWasClosed = false
    }

    private func checkLid() {
        let closed = Self.isLidClosed()
        guard closed != lidWasClosed else { return }
        lidWasClosed = closed
        if closed {
            dimDisplay()
        } else {
            restoreBrightness()
        }
    }

    nonisolated private static func isLidClosed() -> Bool {
        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != 0 else { return false }
        defer { IOObjectRelease(rootDomain) }
        guard let value = IORegistryEntryCreateCFProperty(
            rootDomain, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? Bool else {
            return false
        }
        return value
    }

    // MARK: - Brightness

    private func dimDisplay() {
        guard let display = BuiltInBrightness.builtInDisplay() else { return }
        if savedBrightness == nil {
            savedBrightness = BuiltInBrightness.get(display)
        }
        BuiltInBrightness.set(display, 0.0)
    }

    private func restoreBrightness() {
        guard let brightness = savedBrightness else { return }
        savedBrightness = nil
        guard let display = BuiltInBrightness.builtInDisplay() else { return }
        BuiltInBrightness.set(display, brightness)
    }
}

// MARK: - Built-in display brightness (DisplayServices, loaded at runtime)

private enum BuiltInBrightness {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let handle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY
    )

    private static let getFn: GetFn? = {
        guard let handle, let sym = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(sym, to: GetFn.self)
    }()

    private static let setFn: SetFn? = {
        guard let handle, let sym = dlsym(handle, "DisplayServicesSetBrightness") else { return nil }
        return unsafeBitCast(sym, to: SetFn.self)
    }()

    static func builtInDisplay() -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return nil }
        return displays.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    static func get(_ display: CGDirectDisplayID) -> Float? {
        guard let getFn else { return nil }
        var value: Float = 0
        return getFn(display, &value) == 0 ? value : nil
    }

    static func set(_ display: CGDirectDisplayID, _ value: Float) {
        _ = setFn?(display, max(0, min(1, value)))
    }
}
