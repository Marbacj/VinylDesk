import AppKit
import SwiftUI

struct WidgetRootView: View {
    let bridge: AppleMusicBridge
    let settings: AppSettings
    let dragSession: WindowDragSession
    let notchStore: NotchMetricsStore
    let onContentSizeChange: (CGSize) -> Void
    let onDynamicIslandExpansionChange: (Bool) -> Void

    var body: some View {
        Group {
            switch settings.displayMode {
            case .vinyl:
                VinylRecordView(
                    bridge: bridge,
                    settings: settings,
                    dragSession: dragSession,
                    onSelectMode: { mode in
                        switchMode(to: mode)
                    }
                )
                .fixedSize()
                .contentShape(Rectangle())
                .gesture(windowDragGesture)
                .background(sizeReporter)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))

            case .minimalCard:
                MinimalCardView(
                    bridge: bridge,
                    settings: settings,
                    dragSession: dragSession,
                    onSelectMode: { mode in
                        switchMode(to: mode)
                    }
                )
                .fixedSize()
                .contentShape(Rectangle())
                .gesture(windowDragGesture)
                .background(sizeReporter)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))

            case .dynamicIsland:
                DynamicIslandView(
                    bridge: bridge,
                    settings: settings,
                    metrics: notchStore.metrics,
                    onExpansionChange: onDynamicIslandExpansionChange,
                    onSelectMode: { mode in
                        switchMode(to: mode)
                    }
                )
                .transition(.opacity)
            }
        }
        .contextMenu {
            Menu("显示形态") {
                ForEach(DisplayMode.allCases, id: \.self) { mode in
                    Button {
                        switchMode(to: mode)
                    } label: {
                        if settings.displayMode == mode {
                            Label(mode.title, systemImage: "checkmark")
                        } else {
                            Text(mode.title)
                        }
                    }
                }
            }

            if settings.displayMode != .dynamicIsland {
                Divider()

                Button(settings.windowLayer == .desktop ? "切换为悬浮置顶" : "切换为贴桌面层") {
                    settings.windowLayer = (settings.windowLayer == .desktop) ? .floating : .desktop
                }

                Button(settings.isPositionLocked ? "解锁位置" : "锁定位置") {
                    settings.isPositionLocked.toggle()
                }
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

    private var windowDragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { _ in
                dragSession.handleDragChanged()
            }
            .onEnded { _ in
                dragSession.handleDragEnded()
            }
    }

    private var sizeReporter: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear {
                    onContentSizeChange(geo.size)
                }
                .onChange(of: geo.size) { _, newSize in
                    onContentSizeChange(newSize)
                }
        }
    }

    private func switchMode(to mode: DisplayMode) {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
            settings.displayMode = mode
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
