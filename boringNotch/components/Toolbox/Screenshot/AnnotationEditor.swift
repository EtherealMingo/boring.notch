//
//  AnnotationEditor.swift
//  boringNotch
//
//  Toolbox: native annotation editor for screenshots.
//  Tools: pen / rectangle / arrow / text. Actions: copy, save, pin, OCR, translate.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Annotation model

enum AnnotationTool: String, CaseIterable {
    case pen, rect, arrow, text

    var icon: String {
        switch self {
        case .pen: return "pencil.tip"
        case .rect: return "rectangle"
        case .arrow: return "arrow.up.right"
        case .text: return "textformat"
        }
    }
}

struct AnnotationStroke: Identifiable {
    let id = UUID()
    var tool: AnnotationTool
    var color: Color
    var lineWidth: CGFloat
    var points: [CGPoint]          // pen: many points; rect/arrow: [start, end]
    var text: String = ""          // text tool
}

// MARK: - Window controller

@MainActor
final class AnnotationEditorWindowController {
    static let shared = AnnotationEditorWindowController()

    private var window: NSWindow?

    func present(with image: NSImage) {
        let view = AnnotationEditorView(image: image) { [weak self] in
            self?.window?.close()
            self?.window = nil
        }

        let size = NSSize(
            width: min(image.size.width + 40, NSScreen.main?.visibleFrame.width ?? 1200 - 80),
            height: min(image.size.height + 96, (NSScreen.main?.visibleFrame.height ?? 800) - 100)
        )

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "截图编辑"
        window.titlebarAppearsTransparent = true
        window.center()
        window.contentView = NSHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

// MARK: - Editor view

struct AnnotationEditorView: View {
    let image: NSImage
    let onClose: () -> Void

    @State private var strokes: [AnnotationStroke] = []
    @State private var currentTool: AnnotationTool = .pen
    @State private var currentColor: Color = .red
    @State private var lineWidth: CGFloat = 3
    @State private var activeStroke: AnnotationStroke?
    @State private var ocrText: String = ""
    @State private var showOCRResult = false
    @State private var statusMessage: String?

    private let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .white, .black]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            canvasArea
            Divider()
            bottomBar
        }
        .frame(minWidth: 480, minHeight: 320)
        .sheet(isPresented: $showOCRResult) {
            ocrSheet
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            ForEach(AnnotationTool.allCases, id: \.self) { tool in
                Button {
                    currentTool = tool
                } label: {
                    Image(systemName: tool.icon)
                        .frame(width: 28, height: 24)
                }
                .buttonStyle(.bordered)
                .tint(currentTool == tool ? .accentColor : .gray)
            }

            Divider().frame(height: 20)

            ForEach(colors, id: \.self) { color in
                Circle()
                    .fill(color)
                    .frame(width: 16, height: 16)
                    .overlay {
                        if currentColor == color {
                            Circle().stroke(Color.accentColor, lineWidth: 2)
                        }
                    }
                    .onTapGesture { currentColor = color }
            }

            Slider(value: $lineWidth, in: 1...10) {
                Text("粗细")
            }
            .frame(width: 100)

            Spacer()

            Button("撤销") { _ = strokes.popLast() }
                .disabled(strokes.isEmpty)
            Button("清空") { strokes.removeAll() }
                .disabled(strokes.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: Canvas

    private var canvasArea: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / image.size.width, geo.size.height / image.size.height)
            let displaySize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let origin = CGPoint(
                x: (geo.size.width - displaySize.width) / 2,
                y: (geo.size.height - displaySize.height) / 2
            )

            ZStack(alignment: .topLeading) {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: displaySize.width, height: displaySize.height)
                    .offset(x: origin.x, y: origin.y)

                Canvas { context, _ in
                    for stroke in strokes {
                        draw(stroke, in: &context, scale: scale, origin: origin)
                    }
                    if let active = activeStroke {
                        draw(active, in: &context, scale: scale, origin: origin)
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            handleDrag(value, scale: scale, origin: origin)
                        }
                        .onEnded { _ in
                            if var stroke = activeStroke {
                                if stroke.tool == .text {
                                    stroke.text = "文本"
                                    promptForText(stroke)
                                } else {
                                    strokes.append(stroke)
                                }
                            }
                            activeStroke = nil
                        }
                )
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func handleDrag(_ value: DragGesture.Value, scale: CGFloat, origin: CGPoint) {
        let toImageCoords: (CGPoint) -> CGPoint = { p in
            CGPoint(x: (p.x - origin.x) / scale, y: (p.y - origin.y) / scale)
        }
        let start = toImageCoords(value.startLocation)
        let current = toImageCoords(value.location)

        if activeStroke == nil {
            activeStroke = AnnotationStroke(
                tool: currentTool, color: currentColor, lineWidth: lineWidth,
                points: [start]
            )
        }
        switch currentTool {
        case .pen:
            activeStroke?.points.append(current)
        case .rect, .arrow, .text:
            activeStroke?.points = [start, current]
        }
    }

    private func promptForText(_ stroke: AnnotationStroke) {
        let alert = NSAlert()
        alert.messageText = "添加文本标注"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        alert.accessoryView = input
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn, !input.stringValue.isEmpty {
            var s = stroke
            s.text = input.stringValue
            strokes.append(s)
        }
    }

    private func draw(_ stroke: AnnotationStroke, in context: inout GraphicsContext, scale: CGFloat, origin: CGPoint) {
        let mapped = stroke.points.map {
            CGPoint(x: $0.x * scale + origin.x, y: $0.y * scale + origin.y)
        }
        guard mapped.count >= 1 else { return }

        let swiftUIColor = stroke.color
        let width = stroke.lineWidth

        switch stroke.tool {
        case .pen:
            guard mapped.count > 1 else { return }
            var path = Path()
            path.move(to: mapped[0])
            for p in mapped.dropFirst() { path.addLine(to: p) }
            context.stroke(path, with: .color(swiftUIColor), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))

        case .rect:
            guard mapped.count > 1 else { return }
            let rect = CGRect(
                x: min(mapped[0].x, mapped[1].x), y: min(mapped[0].y, mapped[1].y),
                width: abs(mapped[1].x - mapped[0].x), height: abs(mapped[1].y - mapped[0].y)
            )
            context.stroke(Path(rect), with: .color(swiftUIColor), lineWidth: width)

        case .arrow:
            guard mapped.count > 1 else { return }
            var path = Path()
            path.move(to: mapped[0])
            path.addLine(to: mapped[1])
            // arrow head
            let angle = atan2(mapped[1].y - mapped[0].y, mapped[1].x - mapped[0].x)
            let headLen: CGFloat = 12 + width
            let a1 = angle + .pi * 0.85
            let a2 = angle - .pi * 0.85
            path.move(to: mapped[1])
            path.addLine(to: CGPoint(x: mapped[1].x + headLen * cos(a1), y: mapped[1].y + headLen * sin(a1)))
            path.move(to: mapped[1])
            path.addLine(to: CGPoint(x: mapped[1].x + headLen * cos(a2), y: mapped[1].y + headLen * sin(a2)))
            context.stroke(path, with: .color(swiftUIColor), style: StrokeStyle(lineWidth: width, lineCap: .round))

        case .text:
            guard mapped.count > 1 else { return }
            context.draw(
                Text(stroke.text).foregroundColor(swiftUIColor).font(.system(size: 14 + width * 2, weight: .bold)),
                at: CGPoint(x: (mapped[0].x + mapped[1].x) / 2, y: (mapped[0].y + mapped[1].y) / 2)
            )
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            if let statusMessage {
                Text(statusMessage).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("识字复制") { runOCR() }
            if #available(macOS 15.0, *) {
                Button("翻译") { translateImage() }
            }
            Button("钉在屏幕上") { pinImage() }
            Button("保存…") { saveImage() }
            Button("复制") { copyImage() }
                .keyboardShortcut(.defaultAction)
            Button("关闭") { onClose() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: Flatten & actions

    private func flattenedImage() -> NSImage {
        let size = image.size
        let result = NSImage(size: size)
        result.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size))

        for stroke in strokes {
            let nsColor = NSColor(stroke.color)
            nsColor.setStroke()
            let pts = stroke.points.map { CGPoint(x: $0.x, y: size.height - $0.y) }
            guard pts.count > 1 else { continue }
            switch stroke.tool {
            case .pen:
                let path = NSBezierPath()
                path.move(to: pts[0])
                for p in pts.dropFirst() { path.line(to: p) }
                path.lineWidth = stroke.lineWidth
                path.lineCapStyle = .round
                path.stroke()
            case .rect:
                let rect = CGRect(
                    x: min(pts[0].x, pts[1].x), y: min(pts[0].y, pts[1].y),
                    width: abs(pts[1].x - pts[0].x), height: abs(pts[1].y - pts[0].y)
                )
                let path = NSBezierPath(rect: rect)
                path.lineWidth = stroke.lineWidth
                path.stroke()
            case .arrow:
                let path = NSBezierPath()
                path.move(to: pts[0])
                path.line(to: pts[1])
                let angle = atan2(pts[1].y - pts[0].y, pts[1].x - pts[0].x)
                let headLen: CGFloat = 12 + stroke.lineWidth
                path.move(to: pts[1])
                path.line(to: CGPoint(x: pts[1].x + headLen * cos(angle + .pi * 0.85), y: pts[1].y + headLen * sin(angle + .pi * 0.85)))
                path.move(to: pts[1])
                path.line(to: CGPoint(x: pts[1].x + headLen * cos(angle - .pi * 0.85), y: pts[1].y + headLen * sin(angle - .pi * 0.85)))
                path.lineWidth = stroke.lineWidth
                path.lineCapStyle = .round
                path.stroke()
            case .text:
                let attrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: nsColor,
                    .font: NSFont.systemFont(ofSize: 14 + stroke.lineWidth * 2, weight: .bold)
                ]
                let mid = CGPoint(x: (pts[0].x + pts[1].x) / 2, y: (pts[0].y + pts[1].y) / 2)
                let str = NSAttributedString(string: stroke.text, attributes: attrs)
                let strSize = str.size()
                str.draw(at: CGPoint(x: mid.x - strSize.width / 2, y: mid.y - strSize.height / 2))
            }
        }
        result.unlockFocus()
        return result
    }

    private func copyImage() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([flattenedImage()])
        flash("已复制到剪贴板")
    }

    private func saveImage() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "截图-\(Date().formatted(.dateTime.year().month().day().hour().minute().second())).png"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            if let tiff = flattenedImage().tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: url)
                flash("已保存")
            }
        }
    }

    private func pinImage() {
        PinnedShotWindow.pin(image: flattenedImage())
        flash("已钉在屏幕最上层，点击图钉窗口左上角关闭")
    }

    private func runOCR() {
        OCRService.recognizeText(in: flattenedImage()) { text in
            ocrText = text
            if text.isEmpty {
                flash("没有识别到文字")
            } else {
                showOCRResult = true
            }
        }
    }

    @available(macOS 15.0, *)
    private func translateImage() {
        OCRService.recognizeText(in: flattenedImage()) { text in
            guard !text.isEmpty else {
                flash("没有识别到文字，无法翻译")
                return
            }
            Task { @MainActor in
                TranslateService.shared.beginTranslation(of: text)
                onClose()
            }
        }
    }

    private func flash(_ message: String) {
        statusMessage = message
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            await MainActor.run {
                if statusMessage == message { statusMessage = nil }
            }
        }
    }

    private var ocrSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("识别结果").font(.headline)
            ScrollView {
                Text(ocrText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                if #available(macOS 15.0, *) {
                    Button("翻译这段文字") {
                        showOCRResult = false
                        Task { @MainActor in
                            TranslateService.shared.beginTranslation(of: ocrText)
                            onClose()
                        }
                    }
                }
                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ocrText, forType: .string)
                    showOCRResult = false
                }
                Button("关闭") { showOCRResult = false }
            }
        }
        .padding(20)
        .frame(width: 420, height: 320)
    }
}
