//
//  TranslateService.swift
//  boringNotch
//
//  Toolbox: Apple on-device translation (macOS 15+).
//  Handles input translation, image text translation and
//  cross-app selection translation (⌃⌥Y).
//

import AppKit
import ApplicationServices
import Combine
import Defaults
import SwiftUI

extension Notification.Name {
    static let openToolboxTab = Notification.Name("openToolboxTab")
}

@MainActor
final class TranslateService: ObservableObject {
    static let shared = TranslateService()

    @Published var inputText: String = ""
    @Published var translatedText: String = ""
    @Published var isTranslating: Bool = false
    @Published var lastError: String?

    /// Incremented to retrigger a SwiftUI translationTask.
    @Published var requestID = UUID()

    // MARK: - Begin translation (opens notch tab)

    func beginTranslation(of text: String) {
        inputText = text
        translatedText = ""
        lastError = nil
        requestID = UUID()
        NotificationCenter.default.post(
            name: .openToolboxTab,
            object: nil,
            userInfo: ["tab": NotchViews.translate]
        )
    }

    // MARK: - Cross-app selection translation (⌃⌥Y)

    func translateSelectionFromFrontApp() {
        guard ensureAccessibility(prompt: true) else {
            beginTranslation(of: "")
            lastError = "需要辅助功能权限才能读取其他应用的选中文本"
            return
        }

        let pasteboard = NSPasteboard.general
        let previousChangeCount = pasteboard.changeCount
        let previousItems = pasteboard.pasteboardItems?.compactMap { $0.copy() as? NSPasteboardItem } ?? []

        simulateCopy()

        Task {
            // Wait for the copy to land
            var waited = 0
            while pasteboard.changeCount == previousChangeCount && waited < 600 {
                try? await Task.sleep(for: .milliseconds(50))
                waited += 50
            }

            let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            // Restore previous clipboard contents
            pasteboard.clearContents()
            if !previousItems.isEmpty {
                pasteboard.writeObjects(previousItems)
            }

            if text.isEmpty {
                lastError = "没有读到选中文本"
                beginTranslation(of: "")
            } else {
                beginTranslation(of: text)
            }
        }
    }

    // MARK: - Helpers

    private func simulateCopy() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true) // C
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    @discardableResult
    func ensureAccessibility(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

// MARK: - Language presets

struct TranslateLanguage: Identifiable, Hashable {
    let id: String       // BCP-47-ish code used by Locale.Language
    let name: String

    static let presets: [TranslateLanguage] = [
        .init(id: "zh-Hans", name: "中文（简体）"),
        .init(id: "zh-Hant", name: "中文（繁体）"),
        .init(id: "en", name: "英语"),
        .init(id: "ja", name: "日语"),
        .init(id: "ko", name: "韩语"),
        .init(id: "fr", name: "法语"),
        .init(id: "de", name: "德语"),
        .init(id: "es", name: "西班牙语"),
        .init(id: "ru", name: "俄语"),
        .init(id: "pt", name: "葡萄牙语"),
    ]
}
