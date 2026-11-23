import AppKit
import SwiftUI

struct WidgetRootView: View {
    let bridge: AppleMusicBridge
    let settings: AppSettings
    let dragSession: WindowDragSession
    let onContentSizeChange: (CGSize) -> Void

    var body: some View {
        Group {
            switch settings.displayMode {
            case .vinyl:
                VinylRecordView(
                    bridge: bridge,
                    settings: settings,
                    dragSession: dragSession,
                    onToggleMode: {
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                            settings.displayMode = .minimalCard
                        }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))

            case .minimalCard:
                MinimalCardView(
                    bridge: bridge,
                    settings: settings,
                    dragSession: dragSession,
                    onToggleMode: {
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                            settings.displayMode = .vinyl
                        }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .fixedSize()
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { _ in
                    dragSession.handleDragChanged()
                }
                .onEnded { _ in
                    dragSession.handleDragEnded()
                }
        )
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        onContentSizeChange(geo.size)
                    }
                    .onChange(of: geo.size) { _, newSize in
                        onContentSizeChange(newSize)
                    }
            }
        )
        .contextMenu {
            Button(settings.displayMode == .vinyl ? "切换至极简桌面小挂件" : "切换至黑胶唱片摆件") {
                settings.displayMode = settings.displayMode.toggled
            }

            Divider()

            Button(settings.windowLayer == .desktop ? "切换为悬浮置顶" : "切换为贴桌面层") {
                settings.windowLayer = (settings.windowLayer == .desktop) ? .floating : .desktop
            }

            Button(settings.isPositionLocked ? "解锁位置" : "锁定位置") {
                settings.isPositionLocked.toggle()
            }

            Divider()

            Button(settings.showLyrics ? "隐藏歌词" : "显示歌词") {
                settings.showLyrics.toggle()
                bridge.refreshLyricsForCurrentTrack()
            }

            if settings.showLyrics {
                Button(settings.showBilingualLyrics ? "关闭双语翻译" : "开启双语翻译") {
                    settings.showBilingualLyrics.toggle()
                    bridge.refreshLyricsForCurrentTrack()
                }
            }

            Menu("字体风格") {
                ForEach(FontStyleOption.allCases, id: \.self) { style in
                    Button {
                        settings.fontStyle = style
                    } label: {
                        if settings.fontStyle == style {
                            Label(style.title, systemImage: "checkmark")
                        } else {
                            Text(style.title)
                        }
                    }
                }
            }

            Menu("歌词文字特效") {
                ForEach(TextEffectStyle.allCases, id: \.self) { effect in
                    Button {
                        settings.textEffect = effect
                    } label: {
                        if settings.textEffect == effect {
                            Label(effect.title, systemImage: "checkmark")
                        } else {
                            Text(effect.title)
                        }
                    }
                }
            }

            Divider()

            Button("打开 Apple Music") {
                bridge.openAppleMusic()
            }
        }
    }
}

/// Unified tap-or-drag modifier for clickable artwork: short clicks (< 4pt) open Apple Music, drags smoothly move the window.
struct TapOrWindowDragModifier: ViewModifier {
    let dragSession: WindowDragSession
    let onTap: () -> Void

    @State private var pressStartScreenPoint: NSPoint?
    @State private var didStartWindowDrag: Bool = false

    func body(content: Content) -> some View {
        content.gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    let current = NSEvent.mouseLocation
                    if pressStartScreenPoint == nil {
                        pressStartScreenPoint = current
                        didStartWindowDrag = false
                        return
                    }
                    if !didStartWindowDrag, let start = pressStartScreenPoint {
                        let dist = hypot(current.x - start.x, current.y - start.y)
                        if dist >= 4.0 {
                            didStartWindowDrag = true
                            dragSession.handleDragChanged()
                        }
                    } else if didStartWindowDrag {
                        dragSession.handleDragChanged()
                    }
                }
                .onEnded { _ in
                    if didStartWindowDrag {
                        dragSession.handleDragEnded()
                    } else {
                        onTap()
                    }
                    pressStartScreenPoint = nil
                    didStartWindowDrag = false
                }
        )
    }
}

extension View {
    func tapOrWindowDrag(dragSession: WindowDragSession, onTap: @escaping () -> Void) -> some View {
        modifier(TapOrWindowDragModifier(dragSession: dragSession, onTap: onTap))
    }
}
