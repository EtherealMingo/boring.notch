//
//  ClipboardView.swift
//  boringNotch
//
//  Toolbox: clipboard history tab inside the open notch (Maccy style).
//

import SwiftUI
import Defaults

enum ClipboardFilter: String, CaseIterable {
    case all = "全部"
    case text = "文本"
    case rtf = "富文本"
    case link = "链接"
    case image = "图片"
    case file = "文件"
    case pinned = "固定"
}

struct ClipboardView: View {
    @ObservedObject private var manager = ClipboardManager.shared
    @State private var filter: ClipboardFilter = .all
    @State private var searchText: String = ""
    @State private var selectedID: Int64?
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool
    @Default(.clipboardHistoryEnabled) private var clipboardEnabled

    private var displayedItems: [ClipboardItem] {
        let base = manager.searchResults ?? manager.items
        return base.filter { item in
            switch filter {
            case .all: return true
            case .text: return item.type == .text
            case .rtf: return item.type == .rtf
            case .link: return item.type == .url
            case .image: return item.type == .image
            case .file: return item.type == .filePath
            case .pinned: return item.isPinned
            }
        }
    }

    var body: some View {
        if !clipboardEnabled {
            disabledView
        } else {
            mainView
        }
    }

    private var disabledView: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .font(.title2)
                .foregroundStyle(.gray)
            Text("剪贴板历史默认关闭，开启后开始记录新的复制内容")
                .font(.caption)
                .foregroundStyle(.gray)
            Button("开启剪贴板历史") {
                clipboardEnabled = true
                ClipboardManager.shared.start()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mainView: some View {
        VStack(spacing: 8) {
            if let notice = manager.databaseRebuiltNotice {
                banner(notice, dismissable: true)
            }
            if let message = manager.bannerMessage {
                banner(message, dismissable: false)
            }

            // Filter + search row
            HStack(spacing: 6) {
                ForEach(ClipboardFilter.allCases, id: \.self) { f in
                    Text(f.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(filter == f ? Color.accentColor.opacity(0.7) : Color.white.opacity(0.08))
                        .clipShape(Capsule())
                        .onTapGesture { filter = f }
                }
                Spacer()
                TextField("搜索", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(width: 140)
                    .background(.white.opacity(0.08))
                    .clipShape(Capsule())
                    .focused($searchFocused)
                    .onSubmit { pasteSelection() }
            }

            if displayedItems.isEmpty {
                Spacer()
                if !searchText.isEmpty {
                    Text("无结果")
                        .font(.caption)
                        .foregroundStyle(.gray)
                    Button("清空搜索") {
                        searchText = ""
                        manager.search("")
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                } else {
                    Text(manager.items.isEmpty ? "还没有记录，去复制点什么吧" : "没有匹配的内容")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(displayedItems.enumerated()), id: \.element.id) { index, item in
                            ClipboardRow(
                                item: item,
                                shortcutIndex: index < 9 ? index + 1 : nil,
                                thumbnail: manager.thumbnail(for: item),
                                appName: manager.sourceAppName(for: item.sourceAppBundleID)
                            )
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selectedID == item.id ? Color.white.opacity(0.08) : Color.clear)
                                )
                                .onTapGesture {
                                    manager.pasteIntoPreviousApp(item)
                                }
                                .contextMenu {
                                    Button("复制") { manager.copyToPasteboard(item) }
                                    Button(item.isPinned ? "取消固定" : "固定") { manager.togglePin(item) }
                                    if item.type == .image {
                                        Button("识字复制") { runOCROnImageItem(item) }
                                    }
                                    Divider()
                                    Button("标记敏感并立即删除", role: .destructive) {
                                        manager.markSensitiveAndDelete(item)
                                    }
                                    Button("删除", role: .destructive) { manager.delete(item) }
                                }
                        }
                    }
                }
            }

            HStack {
                Text("回车粘贴 · ⌘1–⌘9 直达 · \(manager.items.count) 条记录")
                    .font(.caption2)
                    .foregroundStyle(.gray)
                Spacer()
                Button("清空") { manager.clearHistory() }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(shortcutButtons)
        .onAppear {
            ClipboardManager.shared.start()
            searchFocused = true
        }
        .onChange(of: searchText) { _, newValue in
            searchTask?.cancel()
            searchTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                manager.search(newValue)
                if selectedID == nil { selectedID = displayedItems.first?.id }
            }
        }
        .onKeyPress(.upArrow) {
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.return) {
            pasteSelection()
            return .handled
        }
        .onKeyPress(.delete) {
            guard searchText.isEmpty else { return .ignored }
            deleteSelection()
            return .handled
        }
        .onKeyPress(.deleteForward) {
            deleteSelection()
            return .handled
        }
    }

    private func banner(_ text: String, dismissable: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle.fill")
                .font(.caption2)
            Text(text)
                .font(.caption2)
            Spacer()
            if dismissable {
                Button {
                    manager.acknowledgeDatabaseRebuiltNotice()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.accentColor.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var shortcutButtons: some View {
        // ⌘1–⌘9 paste the first nine visible items. The buttons are invisible;
        // the default style would otherwise render empty pills mid-panel.
        Group {
            ForEach(Array(displayedItems.prefix(9).enumerated()), id: \.element.id) { index, item in
                Button(action: { manager.pasteIntoPreviousApp(item) }) {
                    EmptyView()
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                .buttonStyle(.plain)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }
        }
    }

    private func moveSelection(by offset: Int) {
        let items = displayedItems
        guard !items.isEmpty else { return }
        guard let selectedID, let current = items.firstIndex(where: { $0.id == selectedID }) else {
            self.selectedID = offset >= 0 ? items.first?.id : items.last?.id
            return
        }
        let next = min(max(current + offset, 0), items.count - 1)
        self.selectedID = items[next].id
    }

    private func pasteSelection() {
        let items = displayedItems
        guard let item = items.first(where: { $0.id == selectedID }) ?? items.first else { return }
        manager.pasteIntoPreviousApp(item)
    }

    private func deleteSelection() {
        guard let item = displayedItems.first(where: { $0.id == selectedID }) else { return }
        manager.delete(item)
        selectedID = nil
    }

    private func runOCROnImageItem(_ item: ClipboardItem) {
        guard let image = manager.imageFor(item) else { return }
        OCRService.recognizeText(in: image) { text in
            guard !text.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }
}

private struct ClipboardRow: View {
    let item: ClipboardItem
    let shortcutIndex: Int?
    let thumbnail: NSImage?
    let appName: String?

    var body: some View {
        HStack(spacing: 10) {
            // Type icon / thumbnail
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 32)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Image(systemName: iconName)
                        .frame(width: 44, height: 32)
                        .background(.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(previewText)
                    .font(.caption)
                    .lineLimit(2)
                    .truncationMode(.tail)
                HStack(spacing: 6) {
                    if let appName {
                        Text(appName)
                    }
                    Text(item.timestamp, format: .relative(presentation: .named))
                }
                .font(.caption2)
                .foregroundStyle(.gray)
            }

            Spacer()

            if let shortcutIndex {
                Text("⌘\(shortcutIndex)")
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }

    private var iconName: String {
        switch item.type {
        case .text: return "text.alignleft"
        case .rtf: return "doc.richtext"
        case .url: return "link"
        case .image: return "photo"
        case .filePath: return "doc"
        }
    }

    private var previewText: String {
        // Two visible lines never need the full payload: long CJK strings cost
        // tens of milliseconds each in CoreText truncation measurement.
        switch item.type {
        case .image: return "图片"
        case .filePath:
            let paths = (item.text ?? "").components(separatedBy: "\n")
            if paths.count > 1 {
                return "\(paths.count) 个文件：\(paths.first?.prefix(120) ?? "")"
            }
            return String(item.text?.prefix(160) ?? "")
        default:
            return String(item.text?.prefix(160) ?? "").replacingOccurrences(of: "\n", with: " ")
        }
    }
}

#Preview {
    ClipboardView()
        .frame(width: 600, height: 260)
        .background(.black)
        .preferredColorScheme(.dark)
}
