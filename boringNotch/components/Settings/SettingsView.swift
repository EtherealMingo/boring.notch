//
//  SettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import AVFoundation
import Defaults
import EventKit
import GRDB
import KeyboardShortcuts
import LaunchAtLogin
import Sparkle
import SwiftUI
import SwiftUIIntrospect

struct SettingsView: View {
    @State private var selectedTab = "General"
    @State private var accentColorUpdateTrigger = UUID()

    let updaterController: SPUStandardUpdaterController?

    init(updaterController: SPUStandardUpdaterController? = nil) {
        self.updaterController = updaterController
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                NavigationLink(value: "General") {
                    Label("通用", systemImage: "gear")
                }
                NavigationLink(value: "Appearance") {
                    Label("外观", systemImage: "eye")
                }
                NavigationLink(value: "Media") {
                    Label("媒体", systemImage: "play.laptopcomputer")
                }
                NavigationLink(value: "Calendar") {
                    Label("日历", systemImage: "calendar")
                }
                NavigationLink(value: "HUD") {
                    Label("HUD 浮窗", systemImage: "dial.medium.fill")
                }
                NavigationLink(value: "Battery") {
                    Label("电池", systemImage: "battery.100.bolt")
                }
//                NavigationLink(value: "Downloads") {
//                    Label("Downloads", systemImage: "square.and.arrow.down")
//                }
                NavigationLink(value: "Shelf") {
                    Label("文件架", systemImage: "books.vertical")
                }
                NavigationLink(value: "Toolbox") {
                    Label("工具箱", systemImage: "wrench.and.screwdriver")
                }
                NavigationLink(value: "Shortcuts") {
                    Label("快捷键", systemImage: "keyboard")
                }
                // NavigationLink(value: "Extensions") {
                //     Label("Extensions", systemImage: "puzzlepiece.extension")
                // }
                NavigationLink(value: "Advanced") {
                    Label("高级", systemImage: "gearshape.2")
                }
                NavigationLink(value: "About") {
                    Label("关于", systemImage: "info.circle")
                }
            }
            .listStyle(SidebarListStyle())
            .tint(.effectiveAccent)
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(200)
        } detail: {
            Group {
                switch selectedTab {
                case "General":
                    GeneralSettings()
                case "Appearance":
                    Appearance()
                case "Media":
                    Media()
                case "Calendar":
                    CalendarSettings()
                case "HUD":
                    HUD()
                case "Battery":
                    Charge()
                case "Shelf":
                    Shelf()
                case "Toolbox":
                    ToolboxSettings()
                case "Shortcuts":
                    Shortcuts()
                case "Extensions":
                    GeneralSettings()
                case "Advanced":
                    Advanced()
                case "About":
                    if let controller = updaterController {
                        About(updaterController: controller)
                    } else {
                        // Fallback with a default controller
                        About(
                            updaterController: SPUStandardUpdaterController(
                                startingUpdater: false, updaterDelegate: nil,
                                userDriverDelegate: nil))
                    }
                default:
                    GeneralSettings()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("")
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 700)
        .background(Color(NSColor.windowBackgroundColor))
        .tint(.effectiveAccent)
        .id(accentColorUpdateTrigger)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AccentColorChanged"))) { _ in
            accentColorUpdateTrigger = UUID()
        }
    }
}

struct GeneralSettings: View {
    @State private var screens: [(uuid: String, name: String)] = NSScreen.screens.compactMap { screen in
        guard let uuid = screen.displayUUID else { return nil }
        return (uuid, screen.localizedName)
    }
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var coordinator = BoringViewCoordinator.shared

    @Default(.mirrorShape) var mirrorShape
    @Default(.showEmojis) var showEmojis
    @Default(.gestureSensitivity) var gestureSensitivity
    @Default(.minimumHoverDuration) var minimumHoverDuration
    @Default(.nonNotchHeight) var nonNotchHeight
    @Default(.nonNotchHeightMode) var nonNotchHeightMode
    @Default(.notchHeight) var notchHeight
    @Default(.notchHeightMode) var notchHeightMode
    @Default(.showOnAllDisplays) var showOnAllDisplays
    @Default(.automaticallySwitchDisplay) var automaticallySwitchDisplay
    @Default(.enableGestures) var enableGestures
    @Default(.openNotchOnHover) var openNotchOnHover
    

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { Defaults[.menubarIcon] },
                    set: { Defaults[.menubarIcon] = $0 }
                )) {
                    Text("显示菜单栏图标")
                }
                .tint(.effectiveAccent)
                Toggle(
                    "登录时启动",
                    isOn: Binding(
                        get: { LaunchAtLogin.isEnabled },
                        set: { LaunchAtLogin.isEnabled = $0 }
                    ))
                Defaults.Toggle(key: .showOnAllDisplays) {
                    Text("在所有显示器上显示")
                }
                .onChange(of: showOnAllDisplays) {
                    NotificationCenter.default.post(
                        name: Notification.Name.showOnAllDisplaysChanged, object: nil)
                }
                Picker("首选显示器", selection: $coordinator.preferredScreenUUID) {
                    ForEach(screens, id: \.uuid) { screen in
                        Text(screen.name).tag(screen.uuid as String?)
                    }
                }
                .onChange(of: NSScreen.screens) {
                    screens = NSScreen.screens.compactMap { screen in
                        guard let uuid = screen.displayUUID else { return nil }
                        return (uuid, screen.localizedName)
                    }
                }
                .disabled(showOnAllDisplays)
                
                Defaults.Toggle(key: .automaticallySwitchDisplay) {
                    Text("自动切换显示器")
                }
                    .onChange(of: automaticallySwitchDisplay) {
                        NotificationCenter.default.post(
                            name: Notification.Name.automaticallySwitchDisplayChanged, object: nil)
                    }
                    .disabled(showOnAllDisplays)
            } header: {
                Text("系统功能")
            }

            Section {
                Picker(
                    selection: $notchHeightMode,
                    label:
                        Text("有刘海屏幕的刘海高度")
                ) {
                    Text("匹配真实刘海高度")
                        .tag(WindowHeightMode.matchRealNotchSize)
                    Text("匹配菜单栏高度")
                        .tag(WindowHeightMode.matchMenuBar)
                    Text("自定义高度")
                        .tag(WindowHeightMode.custom)
                }
                .onChange(of: notchHeightMode) {
                    switch notchHeightMode {
                    case .matchRealNotchSize:
                        notchHeight = 38
                    case .matchMenuBar:
                        notchHeight = 44
                    case .custom:
                        notchHeight = 38
                    }
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
                if notchHeightMode == .custom {
                    Slider(value: $notchHeight, in: 15...45, step: 1) {
                        Text("自定义刘海尺寸 - \(notchHeight, specifier: "%.0f")")
                    }
                    .onChange(of: notchHeight) {
                        NotificationCenter.default.post(
                            name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
                Picker("Notch height on non-notch displays", selection: $nonNotchHeightMode) {
                    Text("匹配菜单栏高度")
                        .tag(WindowHeightMode.matchMenuBar)
                    Text("匹配真实刘海高度")
                        .tag(WindowHeightMode.matchRealNotchSize)
                    Text("自定义高度")
                        .tag(WindowHeightMode.custom)
                }
                .onChange(of: nonNotchHeightMode) {
                    switch nonNotchHeightMode {
                    case .matchMenuBar:
                        nonNotchHeight = 24
                    case .matchRealNotchSize:
                        nonNotchHeight = 32
                    case .custom:
                        nonNotchHeight = 32
                    }
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
                if nonNotchHeightMode == .custom {
                    Slider(value: $nonNotchHeight, in: 0...40, step: 1) {
                        Text("自定义刘海尺寸 - \(nonNotchHeight, specifier: "%.0f")")
                    }
                    .onChange(of: nonNotchHeight) {
                        NotificationCenter.default.post(
                            name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
            } header: {
                Text("刘海尺寸")
            }

            NotchBehaviour()

            gestureControls()
        }
        .toolbar {
            Button("退出应用") {
                NSApp.terminate(self)
            }
            .controlSize(.extraLarge)
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("通用")
        .onChange(of: openNotchOnHover) {
            if !openNotchOnHover {
                enableGestures = true
            }
        }
    }

    @ViewBuilder
    func gestureControls() -> some View {
        Section {
            Defaults.Toggle(key: .enableGestures) {
                Text("启用手势")
            }
                .disabled(!openNotchOnHover)
            if enableGestures {
                Toggle("水平滑动手势切换媒体", isOn: .constant(false))
                    .disabled(true)
                Defaults.Toggle(key: .closeGestureEnabled) {
                    Text("关闭手势")
                }
                Slider(value: $gestureSensitivity, in: 100...300, step: 100) {
                    HStack {
                        Text("手势灵敏度")
                        Spacer()
                        Text(
                            Defaults[.gestureSensitivity] == 100
                                ? "高" : Defaults[.gestureSensitivity] == 200 ? "中" : "低"
                        )
                        .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            HStack {
                Text("手势控制")
                customBadge(text: "Beta")
            }
        } footer: {
            Text(
                "双指在刘海上向上轻扫关闭；关闭**悬停展开刘海**选项后，双指向下轻扫展开"
            )
            .multilineTextAlignment(.trailing)
            .foregroundStyle(.secondary)
            .font(.caption)
        }
    }

    @ViewBuilder
    func NotchBehaviour() -> some View {
        Section {
            Defaults.Toggle(key: .openNotchOnHover) {
                Text("悬停时展开刘海")
            }
            Defaults.Toggle(key: .enableHaptics) {
                    Text("启用触觉反馈")
            }
            Toggle("记住上次标签页", isOn: $coordinator.openLastTabByDefault)
            if openNotchOnHover {
                Slider(value: $minimumHoverDuration, in: 0...1, step: 0.1) {
                    HStack {
                        Text("悬停延迟")
                        Spacer()
                        Text("\(minimumHoverDuration, specifier: "%.1f")s")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: minimumHoverDuration) {
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
            }
        } header: {
            Text("刘海行为")
        }
    }
}

struct Charge: View {
    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showBatteryIndicator) {
                    Text("显示电池指示")
                }
                Defaults.Toggle(key: .showPowerStatusNotifications) {
                    Text("显示电源状态通知")
                }
            } header: {
                Text("General")
            }
            Section {
                Defaults.Toggle(key: .showBatteryPercentage) {
                    Text("显示电池百分比")
                }
                Defaults.Toggle(key: .showPowerStatusIcons) {
                    Text("显示电源状态图标")
                }
            } header: {
                Text("电池信息")
            }
        }
        .onAppear {
            Task { @MainActor in
                await XPCHelperClient.shared.isAccessibilityAuthorized()
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("电池")
    }
}

//struct Downloads: View {
//    @Default(.selectedDownloadIndicatorStyle) var selectedDownloadIndicatorStyle
//    @Default(.selectedDownloadIconStyle) var selectedDownloadIconStyle
//    var body: some View {
//        Form {
//            warningBadge("We don't support downloads yet", "It will be supported later on.")
//            Section {
//                Defaults.Toggle(key: .enableDownloadListener) {
//                    Text("Show download progress")
//                }
//                    .disabled(true)
//                Defaults.Toggle(key: .enableSafariDownloads) {
//                    Text("Enable Safari Downloads")
//                }
//                    .disabled(!Defaults[.enableDownloadListener])
//                Picker("Download indicator style", selection: $selectedDownloadIndicatorStyle) {
//                    Text("Progress bar")
//                        .tag(DownloadIndicatorStyle.progress)
//                    Text("Percentage")
//                        .tag(DownloadIndicatorStyle.percentage)
//                }
//                Picker("Download icon style", selection: $selectedDownloadIconStyle) {
//                    Text("Only app icon")
//                        .tag(DownloadIconStyle.onlyAppIcon)
//                    Text("Only download icon")
//                        .tag(DownloadIconStyle.onlyIcon)
//                    Text("Both")
//                        .tag(DownloadIconStyle.iconAndAppIcon)
//                }
//
//            } header: {
//                HStack {
//                    Text("Download indicators")
//                    comingSoonTag()
//                }
//            }
//            Section {
//                List {
//                    ForEach([].indices, id: \.self) { index in
//                        Text("\(index)")
//                    }
//                }
//                .frame(minHeight: 96)
//                .overlay {
//                    if true {
//                        Text("No excluded apps")
//                            .foregroundStyle(Color(.secondaryLabelColor))
//                    }
//                }
//                .actionBar(padding: 0) {
//                    Group {
//                        Button {
//                        } label: {
//                            Image(systemName: "plus")
//                                .frame(width: 25, height: 16, alignment: .center)
//                                .contentShape(Rectangle())
//                                .foregroundStyle(.secondary)
//                        }
//
//                        Divider()
//                        Button {
//                        } label: {
//                            Image(systemName: "minus")
//                                .frame(width: 20, height: 16, alignment: .center)
//                                .contentShape(Rectangle())
//                                .foregroundStyle(.secondary)
//                        }
//                    }
//                }
//            } header: {
//                HStack(spacing: 4) {
//                    Text("Exclude apps")
//                    comingSoonTag()
//                }
//            }
//        }
//        .navigationTitle("Downloads")
//    }
//}

struct HUD: View {
    @EnvironmentObject var vm: BoringViewModel
    @Default(.inlineHUD) var inlineHUD
    @Default(.enableGradient) var enableGradient
    @Default(.optionKeyAction) var optionKeyAction
    @Default(.hudReplacement) var hudReplacement
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @State private var accessibilityAuthorized = false
    
    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("替换系统 HUD")
                            .font(.headline)
                        Text("用自定义样式替换 macOS 的音量、屏幕亮度和键盘亮度浮窗。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 40)
                    Defaults.Toggle("", key: .hudReplacement)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.large)
                    .disabled(!accessibilityAuthorized)
                }
                
                if !accessibilityAuthorized {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("替换系统 HUD 需要辅助功能权限。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button("请求辅助功能权限") {
                                XPCHelperClient.shared.requestAccessibilityAuthorization()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.top, 6)
                }
            }
            
            Section {
                Picker("Option 键行为", selection: $optionKeyAction) {
                    ForEach(OptionKeyAction.allCases) { opt in
                        Text(opt.localizedName).tag(opt)
                    }
                }
                
                Picker("进度条样式", selection: $enableGradient) {
                    Text("分层")
                        .tag(false)
                    Text("渐变")
                        .tag(true)
                }
                Defaults.Toggle(key: .systemEventIndicatorShadow) {
                    Text("启用发光效果")
                }
                Defaults.Toggle(key: .systemEventIndicatorUseAccent) {
                    Text("用强调色渲染进度条")
                }
            } header: {
                Text("General")
            }
            .disabled(!hudReplacement)
            
            Section {
                Defaults.Toggle(key: .showOpenNotchHUD) {
                    Text("在展开的刘海中显示 HUD")
                }
                Defaults.Toggle(key: .showOpenNotchHUDPercentage) {
                    Text("显示百分比")
                }
                .disabled(!Defaults[.showOpenNotchHUD])
            } header: {
                HStack {
                    Text("刘海展开时")
                    customBadge(text: "Beta")
                }
            }
            .disabled(!hudReplacement)
            
            Section {
                Picker("HUD 样式", selection: $inlineHUD) {
                    Text("默认")
                        .tag(false)
                    Text("内联")
                        .tag(true)
                }
                .onChange(of: Defaults[.inlineHUD]) {
                    if Defaults[.inlineHUD] {
                        withAnimation {
                            Defaults[.systemEventIndicatorShadow] = false
                            Defaults[.enableGradient] = false
                        }
                    }
                }
                
                Defaults.Toggle(key: .showClosedNotchHUDPercentage) {
                    Text("显示百分比")
                }
            } header: {
                Text("刘海关闭时")
            }
            .disabled(!Defaults[.hudReplacement])
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("HUD 浮窗")
        .task {
            accessibilityAuthorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
        }
        .onAppear {
            XPCHelperClient.shared.startMonitoringAccessibilityAuthorization()
        }
        .onDisappear {
            XPCHelperClient.shared.stopMonitoringAccessibilityAuthorization()
        }
        .onReceive(NotificationCenter.default.publisher(for: .accessibilityAuthorizationChanged)) { notification in
            if let granted = notification.userInfo?["granted"] as? Bool {
                accessibilityAuthorized = granted
            }
        }
    }
}

struct Media: View {
    @Default(.waitInterval) var waitInterval
    @Default(.mediaController) var mediaController
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.hideNotchOption) var hideNotchOption
    @Default(.enableSneakPeek) private var enableSneakPeek
    @Default(.sneakPeekStyles) var sneakPeekStyles

    @Default(.enableLyrics) var enableLyrics

    var body: some View {
        Form {
            Section {
                Picker("音乐来源", selection: $mediaController) {
                    ForEach(availableMediaControllers) { controller in
                        Text(controller.localizedName).tag(controller)
                    }
                }
                .onChange(of: mediaController) { _, _ in
                    NotificationCenter.default.post(
                        name: Notification.Name.mediaControllerChanged,
                        object: nil
                    )
                }
            } header: {
                Text("媒体来源")
            } footer: {
                if MusicManager.shared.isNowPlayingDeprecated {
                    HStack {
                        Text("使用 YouTube Music 需要安装此第三方应用：")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Link(
                            "https://github.com/pear-devs/pear-desktop",
                            destination: URL(string: "https://github.com/pear-devs/pear-desktop")!
                        )
                        .font(.caption)
                        .foregroundColor(.blue)  // Ensures it's visibly a link
                    }
                } else {
                    Text(
                        "「正在播放」是旧版本的唯一选项，兼容所有媒体应用。"
                    )
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }
            }
            
            Section {
                Toggle(
                    "显示音乐实时活动",
                    isOn: $coordinator.musicLiveActivityEnabled.animation()
                )
                Toggle("播放变化时显示抢先看", isOn: $enableSneakPeek)
                Picker("抢先看样式", selection: $sneakPeekStyles) {
                    ForEach(SneakPeekStyle.allCases) { style in
                        Text(style.localizedName).tag(style)
                    }
                }
                HStack {
                    Stepper(value: $waitInterval, in: 0...10, step: 1) {
                        HStack {
                            Text("媒体无操作超时")
                            Spacer()
                            Text("\(Defaults[.waitInterval], specifier: "%.0f") 秒")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Picker(
                    selection: $hideNotchOption,
                    label:
                        HStack {
                            Text("全屏行为")
                            customBadge(text: "Beta")
                        }
                ) {
                    Text("对所有应用隐藏").tag(HideNotchOption.always)
                    Text("仅对媒体应用隐藏").tag(
                        HideNotchOption.nowPlayingOnly)
                    Text("永不隐藏").tag(HideNotchOption.never)
                }
            } header: {
                Text("媒体播放实时活动")
            }
            
            Section {
                MusicSlotConfigurationView()
                Defaults.Toggle(key: .enableLyrics) {
                    HStack {
                        Text("在歌手名下方显示歌词")
                        customBadge(text: "Beta")
                    }
                }
            } header: {
                Text("媒体控制")
            }  footer: {
                Text("自定义音乐播放器中显示的控制按钮，音量控制会在使用时展开。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("媒体")
    }

    // Only show controller options that are available on this macOS version
    private var availableMediaControllers: [MediaControllerType] {
        if MusicManager.shared.isNowPlayingDeprecated {
            return MediaControllerType.allCases.filter { $0 != .nowPlaying }
        } else {
            return MediaControllerType.allCases
        }
    }
}

struct CalendarSettings: View {
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Default(.showCalendar) var showCalendar: Bool
    @Default(.hideCompletedReminders) var hideCompletedReminders
    @Default(.hideAllDayEvents) var hideAllDayEvents
    @Default(.autoScrollToNextEvent) var autoScrollToNextEvent

    var body: some View {
        Form {
            Defaults.Toggle(key: .showCalendar) {
                Text("显示日历")
            }
            Defaults.Toggle(key: .hideCompletedReminders) {
                Text("隐藏已完成的提醒")
            }
            Defaults.Toggle(key: .hideAllDayEvents) {
                Text("隐藏全天日程")
            }
            Defaults.Toggle(key: .autoScrollToNextEvent) {
                Text("自动滚动到下一个日程")
            }
            Defaults.Toggle(key: .showFullEventTitles) {
                Text("始终显示完整日程标题")
            }
            Section(header: Text("日历列表")) {
                if calendarManager.calendarAuthorizationStatus != .fullAccess {
                    Text("日历访问被拒绝，请在系统设置中开启。")
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("打开日历设置") {
                        if let settingsURL = URL(
                            string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
                        ) {
                            NSWorkspace.shared.open(settingsURL)
                        }
                    }
                } else {
                    List {
                        ForEach(calendarManager.eventCalendars, id: \.id) { calendar in
                            Toggle(
                                isOn: Binding(
                                    get: { calendarManager.getCalendarSelected(calendar) },
                                    set: { isSelected in
                                        Task {
                                            await calendarManager.setCalendarSelected(
                                                calendar, isSelected: isSelected)
                                        }
                                    }
                                )
                            ) {
                                Text(calendar.title)
                            }
                            .accentColor(lighterColor(from: calendar.color))
                            .disabled(!showCalendar)
                        }
                    }
                }
            }
            Section(header: Text("提醒事项")) {
                if calendarManager.reminderAuthorizationStatus != .fullAccess {
                    Text("提醒事项访问被拒绝，请在系统设置中开启。")
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("打开提醒事项设置") {
                        if let settingsURL = URL(
                            string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
                        ) {
                            NSWorkspace.shared.open(settingsURL)
                        }
                    }
                } else {
                    List {
                        ForEach(calendarManager.reminderLists, id: \.id) { calendar in
                            Toggle(
                                isOn: Binding(
                                    get: { calendarManager.getCalendarSelected(calendar) },
                                    set: { isSelected in
                                        Task {
                                            await calendarManager.setCalendarSelected(
                                                calendar, isSelected: isSelected)
                                        }
                                    }
                                )
                            ) {
                                Text(calendar.title)
                            }
                            .accentColor(lighterColor(from: calendar.color))
                            .disabled(!showCalendar)
                        }
                    }
                }
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("日历")
        .onAppear {
            Task {
                await calendarManager.checkCalendarAuthorization()
                await calendarManager.checkReminderAuthorization()
            }
        }
    }
}

func lighterColor(from nsColor: NSColor, amount: CGFloat = 0.14) -> Color {
    let srgb = nsColor.usingColorSpace(.sRGB) ?? nsColor
    var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0,0,0,0)
    srgb.getRed(&r, green: &g, blue: &b, alpha: &a)

    func lighten(_ c: CGFloat) -> CGFloat {
        let increased = c + (1.0 - c) * amount
        return min(max(increased, 0), 1)
    }

    let nr = lighten(r)
    let ng = lighten(g)
    let nb = lighten(b)

    return Color(red: Double(nr), green: Double(ng), blue: Double(nb), opacity: Double(a))
}

struct About: View {
    @State private var showBuildNumber: Bool = false
    let updaterController: SPUStandardUpdaterController
    @Environment(\.openWindow) var openWindow
    var body: some View {
        VStack {
            Form {
                Section {
                    HStack {
                        Text("版本代号")
                        Spacer()
                        Text(Defaults[.releaseName])
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("版本")
                        Spacer()
                        if showBuildNumber {
                            Text("(\(Bundle.main.buildVersionNumber ?? ""))")
                                .foregroundStyle(.secondary)
                        }
                        Text(Bundle.main.releaseVersionNumber ?? "unkown")
                            .foregroundStyle(.secondary)
                    }
                    .onTapGesture {
                        withAnimation {
                            showBuildNumber.toggle()
                        }
                    }
                } header: {
                    Text("版本信息")
                }

                UpdaterSettingsView(updater: updaterController.updater)

                HStack(spacing: 30) {
                    Spacer(minLength: 0)
                    Button {
                        if let url = URL(string: "https://github.com/EtherealMingo/boring.notch") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        VStack(spacing: 5) {
                            Image("Github")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 18)
                            Text("GitHub")
                        }
                        .contentShape(Rectangle())
                    }
                    Spacer(minLength: 0)
                }
                .buttonStyle(PlainButtonStyle())
            }
            VStack(spacing: 0) {
                Divider()
                Text("由 EtherealMingo 用 🫶🏻 制作")
                    .foregroundStyle(.secondary)
                    .padding(.top, 5)
                    .padding(.bottom, 7)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .toolbar {
            //            Button("Welcome window") {
            //                openWindow(id: "onboarding")
            //            }
            //            .controlSize(.extraLarge)
            CheckForUpdatesView(updater: updaterController.updater)
        }
        .navigationTitle("关于")
    }
}

struct Shelf: View {
    
    @Default(.shelfTapToOpen) var shelfTapToOpen: Bool
    @Default(.quickShareProvider) var quickShareProvider
    @Default(.expandedDragDetection) var expandedDragDetection: Bool
    @StateObject private var quickShareService = QuickShareService.shared

    private var selectedProvider: QuickShareProvider? {
        quickShareService.availableProviders.first(where: { $0.id == quickShareProvider })
    }
    
    init() {
        Task { await QuickShareService.shared.discoverAvailableProviders() }
    }
    
    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .boringShelf) {
                    Text("启用文件架")
                }
                Defaults.Toggle(key: .openShelfByDefault) {
                    Text("有内容时默认打开文件架")
                }
                Defaults.Toggle(key: .expandedDragDetection) {
                    Text("扩大拖拽感应区域")
                }
                .onChange(of: expandedDragDetection) {
                    NotificationCenter.default.post(
                        name: Notification.Name.expandedDragDetectionChanged,
                        object: nil
                    )
                }
                Defaults.Toggle(key: .copyOnDrag) {
                    Text("拖出时复制项目")
                }
                Defaults.Toggle(key: .autoRemoveShelfItems) {
                    Text("拖出后从文件架移除")
                }

            } header: {
                HStack {
                    Text("General")
                }
            }
            
            Section {
                Picker("快速分享服务", selection: $quickShareProvider) {
                    ForEach(quickShareService.availableProviders, id: \.id) { provider in
                        HStack {
                            Group {
                                if let imgData = provider.imageData, let nsImg = NSImage(data: imgData) {
                                    Image(nsImage: nsImg)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                } else {
                                    Image(systemName: "square.and.arrow.up")
                                }
                            }
                            .frame(width: 16, height: 16)
                            .foregroundColor(.accentColor)
                            Text(provider.id)
                        }
                        .tag(provider.id)
                    }
                }
                .pickerStyle(.menu)
                
                if let selectedProvider = selectedProvider {
                    HStack {
                        Group {
                            if let imgData = selectedProvider.imageData, let nsImg = NSImage(data: imgData) {
                                Image(nsImage: nsImg)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                        .frame(width: 16, height: 16)
                        .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("当前选择：\(selectedProvider.id)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("拖入文件架的文件将使用此服务分享")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                // Providers are always enabled; user can pick default service above.
                
            } header: {
                HStack {
                    Text("快速分享")
                }
            } footer: {
                Text("选择从文件架分享文件时使用的服务。点击文件架按钮选择文件，或直接拖入文件立即分享。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("文件架")
    }
}

//struct Extensions: View {
//    @State private var effectTrigger: Bool = false
//    var body: some View {
//        Form {
//            Section {
//                List {
//                    ForEach(extensionManager.installedExtensions.indices, id: \.self) { index in
//                        let item = extensionManager.installedExtensions[index]
//                        HStack {
//                            AppIcon(for: item.bundleIdentifier)
//                                .resizable()
//                                .frame(width: 24, height: 24)
//                            Text(item.name)
//                            ListItemPopover {
//                                Text("Description")
//                            }
//                            Spacer(minLength: 0)
//                            HStack(spacing: 6) {
//                                Circle()
//                                    .frame(width: 6, height: 6)
//                                    .foregroundColor(
//                                        isExtensionRunning(item.bundleIdentifier)
//                                            ? .green : item.status == .disabled ? .gray : .red
//                                    )
//                                    .conditionalModifier(isExtensionRunning(item.bundleIdentifier))
//                                { view in
//                                    view
//                                        .shadow(color: .green, radius: 3)
//                                }
//                                Text(
//                                    isExtensionRunning(item.bundleIdentifier)
//                                        ? "Running"
//                                        : item.status == .disabled ? "Disabled" : "Stopped"
//                                )
//                                .contentTransition(.numericText())
//                                .foregroundStyle(.secondary)
//                                .font(.footnote)
//                            }
//                            .frame(width: 60, alignment: .leading)
//
//                            Menu(
//                                content: {
//                                    Button("Restart") {
//                                        let ws = NSWorkspace.shared
//
//                                        if let ext = ws.runningApplications.first(where: {
//                                            $0.bundleIdentifier == item.bundleIdentifier
//                                        }) {
//                                            ext.terminate()
//                                        }
//
//                                        if let appURL = ws.urlForApplication(
//                                            withBundleIdentifier: item.bundleIdentifier)
//                                        {
//                                            ws.openApplication(
//                                                at: appURL, configuration: .init(),
//                                                completionHandler: nil)
//                                        }
//                                    }
//                                    .keyboardShortcut("R", modifiers: .command)
//                                    Button("Disable") {
//                                        if let ext = NSWorkspace.shared.runningApplications.first(
//                                            where: { $0.bundleIdentifier == item.bundleIdentifier })
//                                        {
//                                            ext.terminate()
//                                        }
//                                        extensionManager.installedExtensions[index].status =
//                                            .disabled
//                                    }
//                                    .keyboardShortcut("D", modifiers: .command)
//                                    Divider()
//                                    Button("Uninstall", role: .destructive) {
//                                        //
//                                    }
//                                },
//                                label: {
//                                    Image(systemName: "ellipsis.circle")
//                                        .foregroundStyle(.secondary)
//                                }
//                            )
//                            .controlSize(.regular)
//                        }
//                        .buttonStyle(PlainButtonStyle())
//                        .padding(.vertical, 5)
//                    }
//                }
//                .frame(minHeight: 120)
//                .actionBar {
//                    Button {
//                    } label: {
//                        HStack(spacing: 3) {
//                            Image(systemName: "plus")
//                            Text("Add manually")
//                        }
//                        .foregroundStyle(.secondary)
//                    }
//                    .disabled(true)
//                    Spacer()
//                    Button {
//                        withAnimation(.linear(duration: 1)) {
//                            effectTrigger.toggle()
//                        } completion: {
//                            effectTrigger.toggle()
//                        }
//                        extensionManager.checkIfExtensionsAreInstalled()
//                    } label: {
//                        HStack(spacing: 3) {
//                            Image(systemName: "arrow.triangle.2.circlepath")
//                                .rotationEffect(effectTrigger ? .degrees(360) : .zero)
//                        }
//                        .foregroundStyle(.secondary)
//                    }
//                }
//                .controlSize(.small)
//                .buttonStyle(PlainButtonStyle())
//                .overlay {
//                    if extensionManager.installedExtensions.isEmpty {
//                        Text("No extension installed")
//                            .foregroundStyle(Color(.secondaryLabelColor))
//                            .padding(.bottom, 22)
//                    }
//                }
//            } header: {
//                HStack(spacing: 0) {
//                    Text("Installed extensions")
//                    if !extensionManager.installedExtensions.isEmpty {
//                        Text(" – \(extensionManager.installedExtensions.count)")
//                            .foregroundStyle(.secondary)
//                    }
//                }
//            }
//        }
//        .accentColor(.effectiveAccent)
//        .navigationTitle("Extensions")
//        // TipsView()
//        // .padding(.horizontal, 19)
//    }
//}

struct Appearance: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.mirrorShape) var mirrorShape
    @Default(.sliderColor) var sliderColor
    @Default(.useMusicVisualizer) var useMusicVisualizer
    @Default(.customVisualizers) var customVisualizers
    @Default(.selectedVisualizer) var selectedVisualizer

    let icons: [String] = ["logo2"]
    @State private var selectedIcon: String = "logo2"
    @State private var selectedListVisualizer: CustomVisualizer? = nil
    @State private var isPresented: Bool = false
    @State private var name: String = ""
    @State private var url: String = ""
    @State private var speed: CGFloat = 1.0
    var body: some View {
        Form {
            Section {
                Toggle("始终显示标签页", isOn: $coordinator.alwaysShowTabs)
                Defaults.Toggle(key: .settingsIconInNotch) {
                    Text("在刘海中显示设置图标")
                }

            } header: {
                Text("General")
            }

            Section {
                Defaults.Toggle(key: .coloredSpectrogram) {
                    Text("彩色频谱")
                }
                Defaults
                    .Toggle("播放器着色", key: .playerColorTinting)
                Defaults.Toggle(key: .lightingEffect) {
                    Text("专辑封面背景模糊效果")
                }
                Picker("滑杆颜色", selection: $sliderColor) {
                    ForEach(SliderColorEnum.allCases, id: \.self) { option in
                        Text(option.localizedName)
                    }
                }
            } header: {
                Text("媒体")
            }

            Section {
                Toggle(
                    "使用音乐可视化频谱",
                    isOn: $useMusicVisualizer.animation()
                )
                .disabled(true)
                if !useMusicVisualizer {
                    if customVisualizers.count > 0 {
                        Picker(
                            "当前动画",
                            selection: $selectedVisualizer
                        ) {
                            ForEach(
                                customVisualizers,
                                id: \.self
                            ) { visualizer in
                                Text(visualizer.name)
                                    .tag(visualizer)
                            }
                        }
                    } else {
                        HStack {
                            Text("当前动画")
                            Spacer()
                            Text("暂无自定义动画")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("自定义音乐实时活动动画")
                    customBadge(text: "即将推出")
                }
            }

            Section {
                List {
                    ForEach(customVisualizers, id: \.self) { visualizer in
                        HStack {
                            LottieView(
                                url: visualizer.url, speed: visualizer.speed,
                                loopMode: .loop
                            )
                            .frame(width: 30, height: 30, alignment: .center)
                            Text(visualizer.name)
                            Spacer(minLength: 0)
                            if selectedVisualizer == visualizer {
                                Text("已选中")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                                    .padding(.trailing, 8)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.vertical, 2)
                        .background(
                            selectedListVisualizer != nil
                                ? selectedListVisualizer == visualizer
                                    ? Color.effectiveAccent : Color.clear : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedListVisualizer == visualizer {
                                selectedListVisualizer = nil
                                return
                            }
                            selectedListVisualizer = visualizer
                        }
                    }
                }
                .safeAreaPadding(
                    EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0)
                )
                .frame(minHeight: 120)
                .actionBar {
                    HStack(spacing: 5) {
                        Button {
                            name = ""
                            url = ""
                            speed = 1.0
                            isPresented.toggle()
                        } label: {
                            Image(systemName: "plus")
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                        }
                        Divider()
                        Button {
                            if selectedListVisualizer != nil {
                                let visualizer = selectedListVisualizer!
                                selectedListVisualizer = nil
                                customVisualizers.remove(
                                    at: customVisualizers.firstIndex(of: visualizer)!)
                                if visualizer == selectedVisualizer && customVisualizers.count > 0 {
                                    selectedVisualizer = customVisualizers[0]
                                }
                            }
                        } label: {
                            Image(systemName: "minus")
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                        }
                    }
                }
                .controlSize(.small)
                .buttonStyle(PlainButtonStyle())
                .overlay {
                    if customVisualizers.isEmpty {
                        Text("没有自定义动画")
                            .foregroundStyle(Color(.secondaryLabelColor))
                            .padding(.bottom, 22)
                    }
                }
                .sheet(isPresented: $isPresented) {
                    VStack(alignment: .leading) {
                        Text("添加新动画")
                            .font(.largeTitle.bold())
                            .padding(.vertical)
                        TextField("名称", text: $name)
                        TextField("Lottie JSON URL", text: $url)
                        HStack {
                            Text("速度")
                            Spacer(minLength: 80)
                            Text("\(speed, specifier: "%.1f")s")
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.secondary)
                            Slider(value: $speed, in: 0...2, step: 0.1)
                        }
                        .padding(.vertical)
                        HStack {
                            Button {
                                isPresented.toggle()
                            } label: {
                                Text("取消")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }

                            Button {
                                let visualizer: CustomVisualizer = .init(
                                    UUID: UUID(),
                                    name: name,
                                    url: URL(string: url)!,
                                    speed: speed
                                )

                                if !customVisualizers.contains(visualizer) {
                                    customVisualizers.append(visualizer)
                                }

                                isPresented.toggle()
                            } label: {
                                Text("添加")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .buttonStyle(BorderedProminentButtonStyle())
                        }
                    }
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .controlSize(.extraLarge)
                    .padding()
                }
            } header: {
                HStack(spacing: 0) {
                    Text("自定义动画（Lottie）")
                    if !Defaults[.customVisualizers].isEmpty {
                        Text(" – \(Defaults[.customVisualizers].count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Defaults.Toggle(key: .showMirror) {
                    Text("启用镜子")
                }
                    .disabled(!checkVideoInput())
                Picker("镜子形状", selection: $mirrorShape) {
                    Text("圆形")
                        .tag(MirrorShapeEnum.circle)
                    Text("方形")
                        .tag(MirrorShapeEnum.rectangle)
                }
                Defaults.Toggle(key: .showNotHumanFace) {
                    Text("闲置时显示表情动画")
                }
            } header: {
                HStack {
                    Text("更多功能")
                }
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("外观")
    }

    func checkVideoInput() -> Bool {
        if AVCaptureDevice.default(for: .video) != nil {
            return true
        }

        return false
    }
}

struct Advanced: View {
    @Default(.useCustomAccentColor) var useCustomAccentColor
    @Default(.customAccentColorData) var customAccentColorData
    @Default(.extendHoverArea) var extendHoverArea
    @Default(.showOnLockScreen) var showOnLockScreen
    @Default(.hideFromScreenRecording) var hideFromScreenRecording
    
    @State private var customAccentColor: Color = .accentColor
    @State private var selectedPresetColor: PresetAccentColor? = nil
    let icons: [String] = ["logo2"]
    @State private var selectedIcon: String = "logo2"
    
    // macOS accent colors
    enum PresetAccentColor: String, CaseIterable, Identifiable {
        case blue = "Blue"
        case purple = "Purple"
        case pink = "Pink"
        case red = "Red"
        case orange = "Orange"
        case yellow = "Yellow"
        case green = "Green"
        case graphite = "Graphite"
        
        var id: String { self.rawValue }
        
        var color: Color {
            switch self {
            case .blue: return Color(red: 0.0, green: 0.478, blue: 1.0)
            case .purple: return Color(red: 0.686, green: 0.322, blue: 0.871)
            case .pink: return Color(red: 1.0, green: 0.176, blue: 0.333)
            case .red: return Color(red: 1.0, green: 0.271, blue: 0.227)
            case .orange: return Color(red: 1.0, green: 0.584, blue: 0.0)
            case .yellow: return Color(red: 1.0, green: 0.8, blue: 0.0)
            case .green: return Color(red: 0.4, green: 0.824, blue: 0.176)
            case .graphite: return Color(red: 0.557, green: 0.557, blue: 0.576)
            }
        }
    }
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    // Toggle between system and custom
                    Picker("强调色", selection: $useCustomAccentColor) {
                        Text("跟随系统").tag(false)
                        Text("自定义").tag(true)
                    }
                    .pickerStyle(.segmented)
                    
                    if !useCustomAccentColor {
                        // System accent info
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                AccentCircleButton(
                                    isSelected: true,
                                    color: .accentColor,
                                    isSystemDefault: true
                                ) {}
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("正在使用系统强调色")
                                        .font(.body)
                                    Text("macOS 系统强调色")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    } else {
                        // Custom color options
                        VStack(alignment: .leading, spacing: 12) {
                            Text("预设颜色")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                            
                            HStack(spacing: 12) {
                                ForEach(PresetAccentColor.allCases) { preset in
                                    AccentCircleButton(
                                        isSelected: selectedPresetColor == preset,
                                        color: preset.color,
                                        isMulticolor: false
                                    ) {
                                        selectedPresetColor = preset
                                        customAccentColor = preset.color
                                        saveCustomColor(preset.color)
                                        forceUiUpdate()
                                    }
                                }
                                Spacer()
                            }
                            
                            Divider()
                                .padding(.vertical, 4)
                            
                            // Custom color picker
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("自选颜色")
                                        .font(.body)
                                    Text("选择任意颜色")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                ColorPicker(selection: Binding(
                                    get: { customAccentColor },
                                    set: { newColor in
                                        customAccentColor = newColor
                                        selectedPresetColor = nil
                                        saveCustomColor(newColor)
                                        forceUiUpdate()
                                    }
                                ), supportsOpacity: false) {
                                    ZStack {
                                        Circle()
                                            .fill(customAccentColor)
                                            .frame(width: 32, height: 32)
                                        
                                        if selectedPresetColor == nil {
                                            Circle()
                                                .strokeBorder(.primary.opacity(0.3), lineWidth: 2)
                                                .frame(width: 32, height: 32)
                                        }
                                    }
                                }
                                .labelsHidden()
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("强调色")
            } footer: {
                Text("可跟随系统强调色，也可自定义喜欢的颜色。")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .onAppear {
                initializeAccentColorState()
            }
            
            Section {
                Defaults.Toggle(key: .enableShadow) {
                    Text("启用窗口阴影")
                }
                Defaults.Toggle(key: .cornerRadiusScaling) {
                    Text("圆角缩放")
                }
            } header: {
                Text("窗口外观")
            }
            
            Section {
                HStack {
                    ForEach(icons, id: \.self) { icon in
                        Spacer()
                        VStack {
                            Image(icon)
                                .resizable()
                                .frame(width: 80, height: 80)
                                .background(
                                    RoundedRectangle(cornerRadius: 20, style: .circular)
                                        .strokeBorder(
                                            icon == selectedIcon ? Color.effectiveAccent : .clear,
                                            lineWidth: 2.5
                                        )
                                )

                            Text("默认")
                                .fontWeight(.medium)
                                .font(.caption)
                                .foregroundStyle(icon == selectedIcon ? .white : .secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(icon == selectedIcon ? Color.effectiveAccent : .clear)
                                )
                        }
                        .onTapGesture {
                            withAnimation {
                                selectedIcon = icon
                            }
                            NSApp.applicationIconImage = NSImage(named: icon)
                        }
                        Spacer()
                    }
                }
                .disabled(true)
            } header: {
                HStack {
                    Text("应用图标")
                    customBadge(text: "即将推出")
                }
            }
            
            Section {
                Defaults.Toggle(key: .extendHoverArea) {
                    Text("扩大悬停区域")
                }
                Defaults.Toggle(key: .hideTitleBar) {
                    Text("隐藏标题栏")
                }
                Defaults.Toggle(key: .showOnLockScreen) {
                    Text("在锁屏显示刘海")
                }
                Defaults.Toggle(key: .hideFromScreenRecording) {
                    Text("录屏时隐藏")
                }
            } header: {
                Text("窗口行为")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("高级")
        .onAppear {
            loadCustomColor()
        }
    }
    
    private func forceUiUpdate() {
        // Force refresh the UI
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("AccentColorChanged"), object: nil)
        }
    }
    
    private func saveCustomColor(_ color: Color) {
        let nsColor = NSColor(color)
        if let colorData = try? NSKeyedArchiver.archivedData(withRootObject: nsColor, requiringSecureCoding: false) {
            Defaults[.customAccentColorData] = colorData
            forceUiUpdate()
        }
    }
    
    private func loadCustomColor() {
        if let colorData = Defaults[.customAccentColorData],
           let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
            customAccentColor = Color(nsColor: nsColor)
            
            // Check if loaded color matches a preset
            selectedPresetColor = nil
            for preset in PresetAccentColor.allCases {
                if colorsAreEqual(Color(nsColor: nsColor), preset.color) {
                    selectedPresetColor = preset
                    break
                }
            }
        }
    }
    
    private func colorsAreEqual(_ color1: Color, _ color2: Color) -> Bool {
        let nsColor1 = NSColor(color1).usingColorSpace(.sRGB) ?? NSColor(color1)
        let nsColor2 = NSColor(color2).usingColorSpace(.sRGB) ?? NSColor(color2)
        
        return abs(nsColor1.redComponent - nsColor2.redComponent) < 0.01 &&
               abs(nsColor1.greenComponent - nsColor2.greenComponent) < 0.01 &&
               abs(nsColor1.blueComponent - nsColor2.blueComponent) < 0.01
    }
    
    private func initializeAccentColorState() {
        if !useCustomAccentColor {
            selectedPresetColor = nil // Multicolor is selected when useCustomAccentColor is false
        } else {
            loadCustomColor()
        }
    }
}

// MARK: - Accent Circle Button Component
struct AccentCircleButton: View {
    let isSelected: Bool
    let color: Color
    var isSystemDefault: Bool = false
    var isMulticolor: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Color circle
                Circle()
                    .fill(color)
                    .frame(width: 32, height: 32)
                
                // Subtle border
                Circle()
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                    .frame(width: 32, height: 32)
                
                // Apple-style highlight ring around the middle when selected
                if isSelected {
                    Circle()
                        .strokeBorder(
                            Color.white.opacity(0.5),
                            lineWidth: 2
                        )
                        .frame(width: 28, height: 28)
                }
            }
        }
        .buttonStyle(.plain)
        .help(isSystemDefault ? "使用 macOS 系统强调色" : "")
    }
}

struct ToolboxSettings: View {
    @Default(.toolboxRegionShortcutEnabled) var regionShortcutEnabled
    @Default(.toolboxSelectionTranslateEnabled) var selectionTranslateEnabled
    @Default(.clipboardHistoryEnabled) var clipboardHistoryEnabled

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .toolboxRegionShortcutEnabled) {
                    Text("启用区域截图快捷键")
                }
                KeyboardShortcuts.Recorder("区域截图：", name: .regionScreenshot)
                    .disabled(!regionShortcutEnabled)
                KeyboardShortcuts.Recorder("贴出剪贴板图片：", name: .pasteFromClipboardPin)
                KeyboardShortcuts.Recorder("显示/隐藏全部贴图：", name: .toggleAllPins)
            } header: {
                Text("截图")
            } footer: {
                Text(
                    "截图会在标注编辑器中打开，可标注、OCR 取字、翻译，或把截图贴到所有窗口之上。"
                )
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .font(.caption)
            }

            Section {
                Defaults.Toggle(key: .toolboxSelectionTranslateEnabled) {
                    Text("启用划词翻译快捷键")
                }
                KeyboardShortcuts.Recorder("划词翻译：", name: .selectionTranslate)
                    .disabled(!selectionTranslateEnabled)
            } header: {
                Text("翻译")
            } footer: {
                Text(
                    "使用 Apple 端侧翻译（需 macOS 15 或更高版本）。在任意应用中选中文字后按快捷键即可翻译。"
                )
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .font(.caption)
            }

            Section {
                Defaults.Toggle(key: .clipboardHistoryEnabled) {
                    Text("记录剪贴板历史")
                }
                .onChange(of: clipboardHistoryEnabled) {
                    if clipboardHistoryEnabled {
                        ClipboardManager.shared.start()
                    } else {
                        ClipboardManager.shared.stop()
                    }
                }
                Defaults.Toggle(key: .clipboardExpireAfter24h) {
                    Text("24 小时后自动清空历史")
                }
                .disabled(!clipboardHistoryEnabled)
                KeyboardShortcuts.Recorder("剪贴板面板：", name: .clipboardHistoryPanel)
                    .disabled(!clipboardHistoryEnabled)
            } header: {
                Text("剪贴板")
            } footer: {
                Text(
                    "记录文本、链接和图片。在剪贴板标签页中点击条目即可粘贴回来源应用。最多保留 500 条，置顶条目不会被自动清除。"
                )
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .font(.caption)
            }

            ClipboardIgnoreListSection()
                .disabled(!clipboardHistoryEnabled)
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("工具箱")
    }
}

private struct ClipboardIgnoreListSection: View {
    @State private var apps: [IgnoredApp] = []
    @State private var newBundleID: String = ""

    var body: some View {
        Section {
            ForEach(apps, id: \.bundleId) { app in
                HStack {
                    Text(app.bundleId)
                    Spacer()
                    Button(role: .destructive) {
                        remove(app)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
            HStack {
                TextField("com.example.app", text: $newBundleID)
                    .textFieldStyle(.roundedBorder)
                Button("添加") {
                    add(newBundleID)
                }
                .disabled(newBundleID.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Button("添加当前前台应用") {
                if let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                   bundleID != Bundle.main.bundleIdentifier {
                    add(bundleID)
                }
            }
        } header: {
            Text("剪贴板忽略列表")
        } footer: {
            Text("这些应用处于前台时，复制的内容不会被记录。")
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        apps = (try? DatabaseManager.shared.dbQueue.read { db in
            try IgnoredApp.order(IgnoredApp.Columns.bundleId).fetchAll(db)
        }) ?? []
    }

    private func add(_ raw: String) {
        let bundleID = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleID.isEmpty else { return }
        try? DatabaseManager.shared.dbQueue.write { db in
            var app = IgnoredApp(bundleId: bundleID, addedAt: Date())
            try? app.insert(db)
        }
        newBundleID = ""
        reload()
    }

    private func remove(_ app: IgnoredApp) {
        try? DatabaseManager.shared.dbQueue.write { db in
            try? app.delete(db)
        }
        reload()
    }
}

struct Shortcuts: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("切换抢先看：", name: .toggleSneakPeek)
            } header: {
                Text("媒体")
            } footer: {
                Text(
                    "抢先看会在刘海下方短暂显示正在播放的标题和歌手。"
                )
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .font(.caption)
            }
            Section {
                KeyboardShortcuts.Recorder("展开/收起刘海：", name: .toggleNotchOpen)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("快捷键")
    }
}

func proFeatureBadge() -> some View {
    Text("升级到 Pro")
        .foregroundStyle(Color(red: 0.545, green: 0.196, blue: 0.98))
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 4).stroke(
                Color(red: 0.545, green: 0.196, blue: 0.98), lineWidth: 1))
}

func comingSoonTag() -> some View {
    Text("Coming soon")
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
}

func customBadge(text: String) -> some View {
    Text(text)
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
}

func warningBadge(_ text: String, _ description: String) -> some View {
    Section {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.yellow)
            VStack(alignment: .leading) {
                Text(text)
                    .font(.headline)
                Text(description)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

#Preview {
    HUD()
}
