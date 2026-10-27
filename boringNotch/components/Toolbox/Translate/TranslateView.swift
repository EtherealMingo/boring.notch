//
//  TranslateView.swift
//  boringNotch
//
//  Toolbox: translation tab inside the open notch.
//  Uses Apple Translation framework (on-device, macOS 15+).
//

import SwiftUI
import Translation

struct TranslateView: View {
    var body: some View {
        if #available(macOS 15.0, *) {
            TranslateView15()
        } else {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                Text("Apple 本机翻译需要 macOS 15 或更高版本")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

@available(macOS 15.0, *)
private struct TranslateView15: View {
    @ObservedObject private var service = TranslateService.shared

    /// nil = 自动检测（仅源语言允许）
    @State private var sourceLanguage: TranslateLanguage?
    @State private var targetLanguage: TranslateLanguage = .presets[2]   // 英语
    @State private var configuration: TranslationSession.Configuration?
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        content
            .translationTask(configuration) { session in
                await performTranslation(using: session)
            }
    }

    @ViewBuilder
    private var content: some View {
        HStack(spacing: 0) {
            sourceColumn
            divider
            resultColumn
        }
        .background(.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(manualTriggerButton)
        .onChange(of: service.inputText) { _, newValue in
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                debounceTask?.cancel()
                service.translatedText = ""
                service.isTranslating = false
                service.lastError = nil
            } else {
                scheduleTranslation()
            }
        }
        .onChange(of: sourceLanguage) { _, _ in scheduleTranslation(immediate: true) }
        .onChange(of: targetLanguage) { _, _ in scheduleTranslation(immediate: true) }
        .onChange(of: service.requestID) { _, _ in
            // Text arrived from screenshot OCR or selection grab
            if !service.inputText.isEmpty {
                scheduleTranslation(immediate: true)
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .frame(width: 1)
            .padding(.vertical, 6)
    }

    // MARK: - Source column

    private var sourceColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                languagePicker(selection: $sourceLanguage, allowsAutoDetect: true)
                Spacer(minLength: 0)
                iconButton("doc.on.clipboard", help: "粘贴") {
                    if let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
                        service.inputText = text
                    }
                }
                if !service.inputText.isEmpty {
                    iconButton("xmark", help: "清空") {
                        service.inputText = ""
                        service.translatedText = ""
                        service.lastError = nil
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            TextEditor(text: $service.inputText)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 4)
                .padding(.top, 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("原文")

            HStack {
                if !service.inputText.isEmpty {
                    Text("\(service.inputText.count) 字")
                        .font(.caption2)
                        .foregroundStyle(.gray)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
            .frame(height: 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Result column

    private var resultColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                languagePicker(
                    selection: Binding(
                        get: { targetLanguage },
                        set: { if let lang = $0 { targetLanguage = lang } }
                    ),
                    allowsAutoDetect: false
                )
                Spacer(minLength: 0)
                iconButton("arrow.left.arrow.right", help: "交换语言并翻译") {
                    swapLanguages()
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            Group {
                if service.isTranslating {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("翻译中…").font(.caption).foregroundStyle(.gray)
                        Spacer()
                    }
                    .padding(.top, 8)
                } else if !service.translatedText.isEmpty {
                    ScrollView {
                        Text(service.translatedText)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding(.top, 6)
                } else if let error = service.lastError {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(error).font(.caption).foregroundStyle(.orange)
                        Button("重试") { scheduleTranslation(immediate: true) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                } else {
                    Text("输入文字，或在其他应用选中文本后按 ⌃⌥Y")
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityLabel("译文")

            HStack {
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(service.translatedText, forType: .string)
                } label: {
                    Label("复制译文", systemImage: "doc.on.doc").font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(service.translatedText.isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
            .frame(height: 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Controls

    private var manualTriggerButton: some View {
        Button("") { scheduleTranslation(immediate: true) }
            .keyboardShortcut(.return, modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }

    private func iconButton(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.gray)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private func languagePicker(selection: Binding<TranslateLanguage?>, allowsAutoDetect: Bool) -> some View {
        Menu {
            if allowsAutoDetect {
                Button("自动检测") { selection.wrappedValue = nil }
                Divider()
            }
            ForEach(TranslateLanguage.presets) { lang in
                Button(lang.name) { selection.wrappedValue = lang }
            }
        } label: {
            HStack(spacing: 3) {
                Text(selection.wrappedValue?.name ?? "自动检测")
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.08))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(allowsAutoDetect ? "源语言" : "目标语言")
    }

    // MARK: - Translation

    private func swapLanguages() {
        let oldTarget = targetLanguage
        targetLanguage = sourceLanguage ?? (oldTarget.id == "zh-Hans" ? .presets[2] : .presets[0])
        sourceLanguage = oldTarget
        if !service.translatedText.isEmpty {
            service.inputText = service.translatedText
            service.translatedText = ""
        }
        scheduleTranslation(immediate: true)
    }

    private func scheduleTranslation(immediate: Bool = false) {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            if !immediate {
                try? await Task.sleep(for: .milliseconds(600))
            }
            guard !Task.isCancelled else { return }
            triggerTranslation()
        }
    }

    private func triggerTranslation() {
        guard #available(macOS 15.0, *) else { return }
        let text = service.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        service.isTranslating = true
        service.lastError = nil
        // Invalidate to force retrigger even with same languages
        configuration?.invalidate()
        configuration = TranslationSession.Configuration(
            source: sourceLanguage.map { Locale.Language(identifier: $0.id) },
            target: Locale.Language(identifier: targetLanguage.id)
        )
    }

    private func performTranslation(using session: TranslationSession) async {
        let text = await MainActor.run { service.inputText }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await MainActor.run { service.isTranslating = false }
            return
        }
        do {
            let response = try await session.translate(text)
            await MainActor.run {
                service.translatedText = response.targetText
                service.isTranslating = false
            }
        } catch {
            await MainActor.run {
                service.lastError = "翻译失败：\(error.localizedDescription)（首次使用可能需要在系统提示中下载语言包）"
                service.isTranslating = false
            }
        }
    }
}

#Preview {
    TranslateView()
        .frame(width: 600, height: 240)
        .background(.black)
        .preferredColorScheme(.dark)
}
