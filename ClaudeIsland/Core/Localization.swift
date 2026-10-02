//
//  Localization.swift
//  ClaudeIsland
//
//  Runtime language switching. English text is the lookup key; translations
//  live in Resources/<code>.lproj/Localizable.strings.
//

import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case en, de, fr, es, it, pt, nl, sv, da, fi, pl, cs, tr, ru, uk, ja, ko
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case hi

    nonisolated var id: String { rawValue }

    /// Name shown in the picker, always in the language itself
    nonisolated var nativeName: String {
        switch self {
        case .system: return "Automatic"
        case .en: return "English"
        case .de: return "Deutsch"
        case .fr: return "Français"
        case .es: return "Español"
        case .it: return "Italiano"
        case .pt: return "Português"
        case .nl: return "Nederlands"
        case .sv: return "Svenska"
        case .da: return "Dansk"
        case .fi: return "Suomi"
        case .pl: return "Polski"
        case .cs: return "Čeština"
        case .tr: return "Türkçe"
        case .ru: return "Русский"
        case .uk: return "Українська"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .hi: return "हिन्दी"
        }
    }

    /// The concrete language to use; `.system` follows the macOS preference list
    nonisolated var resolved: AppLanguage {
        guard self == .system else { return self }

        for identifier in Locale.preferredLanguages {
            let lower = identifier.lowercased()
            if lower.hasPrefix("zh") {
                let traditional = lower.contains("hant") || lower.contains("-tw") || lower.contains("-hk") || lower.contains("-mo")
                return traditional ? .zhHant : .zhHans
            }
            let code = String(lower.prefix(2))
            if let match = AppLanguage.allCases.first(where: { $0 != .system && $0.rawValue == code }) {
                return match
            }
            if code == "nb" || code == "nn" || code == "no" { continue }
        }
        return .en
    }
}

enum L10n {
    nonisolated(unsafe) private static var bundles: [String: Bundle] = [:]
    private nonisolated static let lock = NSLock()

    /// Translate an English key into the selected language and fill `%@` / `%d` placeholders
    nonisolated static func tr(_ key: String, _ args: CVarArg...) -> String {
        let language = AppSettings.language.resolved
        var text = key

        if language != .en, let bundle = bundle(for: language) {
            text = bundle.localizedString(forKey: key, value: key, table: nil)
        }
        return args.isEmpty ? text : String(format: text, arguments: args)
    }

    private nonisolated static func bundle(for language: AppLanguage) -> Bundle? {
        lock.lock()
        defer { lock.unlock() }

        if let cached = bundles[language.rawValue] { return cached }
        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return nil }
        bundles[language.rawValue] = bundle
        return bundle
    }
}
