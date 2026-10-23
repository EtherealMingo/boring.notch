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

    @State private var sourceLanguage: TranslateLanguage = .presets[0]   // 中文简体
    @State private var targetLanguage: TranslateLanguage = .presets[2]   // 英语
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        content
            .translationTask(configuration) { session in
                await performTranslation(using: session)
            }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 10) {
            // Language row
            HStack(spacing: 8) {
                languagePicker(selection: $sourceLanguage)
                Button {
                    swap(&sourceLanguage, &targetLanguage)
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.gray)
                languagePicker(selection: $targetLanguage)

                Spacer()

                Button {
                    triggerTranslation()
                } label: {
                    Label("翻译", systemImage: "character.bubble")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(service.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || service.isTranslating)
            }

            // Input (left) and result (right), side by side
            HStack(alignment: .top, spacing: 10) {
                TextEditor(text: $service.inputText)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Group {
                    if service.isTranslating {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("翻译中…").font(.caption).foregroundStyle(.gray)
                            Spacer()
                        }
                    } else if !service.translatedText.isEmpty {
                        ScrollView {
                            Text(service.translatedText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    } else if let error = service.lastError {
                        Text(error).font(.caption).foregroundStyle(.orange)
                    } else {
                        Text("输入文字，或在其他应用选中文本后按 ⌃⌥Y")
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                }
                .padding(6)
                .background(.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: .infinity)

            if !service.translatedText.isEmpty {
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
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .onChange(of: service.requestID) { _, _ in
            // Text arrived from screenshot OCR or selection grab
            if !service.inputText.isEmpty {
                triggerTranslation()
            }
        }
    }

    private func languagePicker(selection: Binding<TranslateLanguage>) -> some View {
        Menu {
            ForEach(TranslateLanguage.presets) { lang in
                Button(lang.name) { selection.wrappedValue = lang }
            }
        } label: {
            Text(selection.wrappedValue.name)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.white.opacity(0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func triggerTranslation() {
        guard #available(macOS 15.0, *) else { return }
        service.isTranslating = true
        service.lastError = nil
        // Invalidate to force retrigger even with same languages
        configuration?.invalidate()
        configuration = TranslationSession.Configuration(
            source: Locale.Language(identifier: sourceLanguage.id),
            target: Locale.Language(identifier: targetLanguage.id)
        )
    }

    @available(macOS 15.0, *)
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
