//
//  ToolboxView.swift
//  boringNotch
//
//  Toolbox: single notch entry hosting Screenshot / Translate / Clipboard.
//

import SwiftUI

struct ToolboxView: View {
    @ObservedObject private var coordinator = BoringViewCoordinator.shared

    var body: some View {
        VStack(spacing: 6) {
            Picker("", selection: $coordinator.toolboxTab) {
                Text("截图").tag(ToolboxTab.screenshot)
                Text("翻译").tag(ToolboxTab.translate)
                Text("剪贴板").tag(ToolboxTab.clipboard)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 40)

            Group {
                switch coordinator.toolboxTab {
                case .screenshot:
                    ScreenshotView()
                case .translate:
                    TranslateView()
                case .clipboard:
                    ClipboardView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
