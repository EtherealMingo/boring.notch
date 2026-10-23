//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import SwiftUI

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
}

let tabs = [
    TabModel(label: "Home", icon: "house.fill", view: .home),
    TabModel(label: "Shelf", icon: "tray.fill", view: .shelf),
    TabModel(label: "工具箱", icon: "wrench.and.screwdriver.fill", view: .toolbox)
]

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Namespace var animation
    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                    // Read selection OUTSIDE the background closure: reading
                    // `coordinator` inside a closure modifier lets SwiftUI skip
                    // re-evaluating it, which leaves the capsule one switch
                    // behind the actual content.
                    let isSelected = coordinator.currentView == tab.view
                    TabButton(label: tab.label, icon: tab.icon, selected: isSelected) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            coordinator.currentView = tab.view
                        }
                    }
                    .frame(height: 26)
                    .foregroundStyle(isSelected ? .white : .gray)
                    .background(
                        Capsule()
                            .fill(isSelected ? Color.white.opacity(0.16) : Color.clear)
                    )
            }
        }
        .clipShape(Capsule())
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
