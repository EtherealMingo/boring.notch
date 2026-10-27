//
//  Constants.swift
//  boringNotch
//
//  Created by Richard Kunkli on 16/08/2024.
//

import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let clipboardHistoryPanel = Self("clipboardHistoryPanel", default: .init(.v, modifiers: [.command, .shift]))
    static let toggleMicrophone = Self("toggleMicrophone", default: .init(.f5, modifiers: [.function]))
    static let decreaseBacklight = Self("decreaseBacklight", default: .init(.f1, modifiers: [.command]))
    static let increaseBacklight = Self("increaseBacklight", default: .init(.f2, modifiers: [.command]))
    static let toggleSneakPeek = Self("toggleSneakPeek", default: .init(.h, modifiers: [.command, .shift]))
    static let toggleNotchOpen = Self("toggleNotchOpen", default: .init(.i, modifiers: [.command, .shift]))
    // MARK: Toolbox
    static let regionScreenshot = Self("regionScreenshot", default: .init(.two, modifiers: [.command, .shift]))
    static let selectionTranslate = Self("selectionTranslate", default: .init(.y, modifiers: [.control, .option]))
    static let pasteFromClipboardPin = Self("pasteFromClipboardPin", default: .init(.t, modifiers: [.command, .shift]))
    static let toggleAllPins = Self("toggleAllPins", default: .init(.h, modifiers: [.control, .command]))
}
