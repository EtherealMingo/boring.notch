//
//  ToolboxView.swift
//  boringNotch
//
//  Toolbox: single notch entry hosting Screenshot / Translate / Clipboard.
//

import SwiftUI

struct ToolboxView: View {
    @ObservedObject private var coordinator = BoringViewCoordinator.shared

    private let tabs: [(tab: ToolboxTab, label: String)] = [
        (.screenshot, "截图"),
        (.translate, "翻译"),
        (.clipboard, "剪贴板")
    ]

    var body: some View {
        VStack(spacing: 6) {
            // Custom segmented tabs — the native segmented Picker renders its
            // selection almost invisibly on this dark, non-activating panel.
            HStack(spacing: 4) {
                ForEach(tabs, id: \.tab) { tab, label in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            coordinator.toolboxTab = tab
                        }
                    } label: {
                        Text(label)
                            .font(.caption)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                            .foregroundStyle(coordinator.toolboxTab == tab ? .white : .gray)
                            .background(
                                Capsule()
                                    .fill(coordinator.toolboxTab == tab
                                          ? Color.white.opacity(0.16)
                                          : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Capsule().fill(Color.white.opacity(0.08)))

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
            // Crossfade between tools — no height change inside the toolbox,
            // just a soft content swap.
            .id(coordinator.toolboxTab)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.15), value: coordinator.toolboxTab)
        }
    }
}
