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
    case link = "链接"
    case image = "图片"
    case favorite = "收藏"
}

struct ClipboardView: View {
    @ObservedObject private var manager = ClipboardManager.shared
    @State private var filter: ClipboardFilter = .all
    @State private var searchText: String = ""
    @Default(.clipboardHistoryEnabled) private var clipboardEnabled

    private var filteredItems: [ClipboardItem] {
        manager.items.filter { item in
            switch filter {
            case .all: break
            case .text: guard item.type == .text else { return false }
            case .link: guard item.type == .link else { return false }
            case .image: guard item.type == .image else { return false }
            case .favorite: guard item.isFavorite else { return false }
            }
            if !searchText.isEmpty, item.type != .image {
                return item.text?.localizedCaseInsensitiveContains(searchText) == true
            }
            return true
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
            }

            if filteredItems.isEmpty {
                Spacer()
                Text(manager.items.isEmpty ? "还没有记录，去复制点什么吧" : "没有匹配的内容")
                    .font(.caption)
                    .foregroundStyle(.gray)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredItems) { item in
                            ClipboardRow(item: item)
                                .onTapGesture {
                                    manager.pasteIntoPreviousApp(item)
                                }
                                .contextMenu {
                                    Button("复制") { manager.copyToPasteboard(item) }
                                    Button(item.isFavorite ? "取消收藏" : "收藏") { manager.toggleFavorite(item) }
                                    if item.type == .image {
                                        Button("识字复制") { runOCROnImageItem(item) }
                                    }
                                    Divider()
                                    Button("删除", role: .destructive) { manager.delete(item) }
                                }
                        }
                    }
                }
            }

            HStack {
                Text("点击条目回到原应用粘贴 · \(manager.items.count) 条记录")
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
        .onAppear { ClipboardManager.shared.start() }
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
    @ObservedObject private var manager = ClipboardManager.shared

    var body: some View {
        HStack(spacing: 10) {
            // Type icon / thumbnail
            Group {
                if item.type == .image, let image = manager.imageFor(item) {
                    Image(nsImage: image)
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
                    if let app = item.sourceAppName {
                        Text(app)
                    }
                    Text(item.timestamp, format: .relative(presentation: .named))
                }
                .font(.caption2)
                .foregroundStyle(.gray)
            }

            Spacer()

            if item.isFavorite {
                Image(systemName: "star.fill")
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
        case .link: return "link"
        case .image: return "photo"
        }
    }

    private var previewText: String {
        if item.type == .image { return "图片" }
        return item.text?.replacingOccurrences(of: "\n", with: " ") ?? ""
    }
}

#Preview {
    ClipboardView()
        .frame(width: 600, height: 260)
        .background(.black)
        .preferredColorScheme(.dark)
}
