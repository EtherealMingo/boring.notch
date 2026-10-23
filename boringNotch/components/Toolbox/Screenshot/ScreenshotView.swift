//
//  ScreenshotView.swift
//  boringNotch
//
//  Toolbox: screenshot tab inside the open notch.
//

import SwiftUI

struct ScreenshotView: View {
    @ObservedObject private var manager = ScreenshotManager.shared

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                captureButton(title: "区域截图", icon: "rectangle.dashed", hint: "⌘⇧X") {
                    manager.capture(.region)
                }
                captureButton(title: "窗口截图", icon: "macwindow") {
                    manager.capture(.window)
                }
                captureButton(title: "全屏截图", icon: "display") {
                    manager.capture(.fullscreen)
                }
            }

            if let image = manager.lastCapturedImage {
                HStack(spacing: 12) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.15)))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("最近一次截图").font(.caption).foregroundStyle(.gray)
                        HStack(spacing: 8) {
                            miniAction("重新编辑", icon: "pencil") {
                                AnnotationEditorWindowController.shared.present(with: image)
                            }
                            miniAction("复制", icon: "doc.on.doc") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.writeObjects([image])
                            }
                            miniAction("钉图", icon: "pin") {
                                PinnedShotWindow.pin(image: image)
                            }
                        }
                    }
                    Spacer()
                }
            } else {
                Text("截图后可标注、识字、翻译、钉在屏幕最上层")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func captureButton(title: String, icon: String, hint: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(title).font(.caption)
                if let hint {
                    Text(hint).font(.caption2).foregroundStyle(.gray)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func miniAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.caption)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

#Preview {
    ScreenshotView()
        .frame(width: 600, height: 160)
        .background(.black)
        .preferredColorScheme(.dark)
}
