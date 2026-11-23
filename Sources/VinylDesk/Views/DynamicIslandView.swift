import AppKit
import Observation
import SwiftUI

public struct ScreenNotchMetrics: Equatable, Sendable {
    public let screenFrame: CGRect
    public let hasHardwareNotch: Bool
    public let notchWidth: CGFloat
    public let notchHeight: CGFloat

    public static func current(for screen: NSScreen? = nil) -> ScreenNotchMetrics {
        let targetScreen = screen
            ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let targetScreen else {
            return ScreenNotchMetrics(
                screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                hasHardwareNotch: false,
                notchWidth: 190,
                notchHeight: 34
            )
        }

        let topInset = targetScreen.safeAreaInsets.top
        if topInset > 0,
           let leftArea = targetScreen.auxiliaryTopLeftArea,
           let rightArea = targetScreen.auxiliaryTopRightArea {
            let computedNotchWidth = max(140, targetScreen.frame.width - leftArea.width - rightArea.width)
            let computedNotchHeight = max(topInset, max(leftArea.height, rightArea.height))
            return ScreenNotchMetrics(
                screenFrame: targetScreen.frame,
                hasHardwareNotch: true,
                notchWidth: computedNotchWidth,
                notchHeight: computedNotchHeight
            )
        }

        let menuBarHeight = max(28, min(36, targetScreen.frame.maxY - targetScreen.visibleFrame.maxY))
        return ScreenNotchMetrics(
            screenFrame: targetScreen.frame,
            hasHardwareNotch: false,
            notchWidth: 164,
            notchHeight: menuBarHeight
        )
    }
}

/// Authentic macOS Dynamic Island shape: concave top ears hugging the screen bezel + smooth rounded bottom corners.
struct DynamicIslandShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let topR = min(topCornerRadius, rect.height / 2, rect.width / 4)
        let botR = min(bottomCornerRadius, rect.height / 2, (rect.width - topR * 2) / 2)

        var path = Path()
        // Start at outer top-left ear
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Concave inward curve on top-left
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topR, y: rect.minY + topR),
            control: CGPoint(x: rect.minX + topR, y: rect.minY)
        )

        // Left vertical edge down to bottom-left corner
        path.addLine(to: CGPoint(x: rect.minX + topR, y: rect.maxY - botR))

        // Bottom-left rounded corner
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topR + botR, y: rect.maxY),
            control: CGPoint(x: rect.minX + topR, y: rect.maxY)
        )

        // Bottom horizontal edge
        path.addLine(to: CGPoint(x: rect.maxX - topR - botR, y: rect.maxY))

        // Bottom-right rounded corner
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topR, y: rect.maxY - botR),
            control: CGPoint(x: rect.maxX - topR, y: rect.maxY)
        )

        // Right vertical edge up to top-right ear
        path.addLine(to: CGPoint(x: rect.maxX - topR, y: rect.minY + topR))

        // Concave outward curve on top-right
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topR, y: rect.minY)
        )

        path.closeSubpath()
        return path
    }
}

/// Smooth 4-bar audio visualizer that animates gently while playing and rests at 0% CPU when paused.
private struct AudioWaveformView: View {
    let isPlaying: Bool
    let tint: Color
    let height: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !isPlaying)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.2) {
                ForEach(0..<4, id: \.self) { index in
                    let phase = Double(index) * 1.15
                    let wave = isPlaying
                        ? (0.28 + 0.72 * abs(sin(t * (3.6 + Double(index) * 0.55) + phase)))
                        : 0.22
                    Capsule(style: .continuous)
                        .fill(tint.opacity(isPlaying ? 0.92 : 0.45))
                        .frame(width: 2.4, height: max(3.0, height * CGFloat(wave)))
                }
            }
            .frame(height: height, alignment: .center)
            .animation(.easeInOut(duration: 0.25), value: isPlaying)
        }
    }
}

struct DynamicIslandView: View {
    let bridge: AppleMusicBridge
    let settings: AppSettings
    let metrics: ScreenNotchMetrics
    let onExpansionChange: (Bool) -> Void
    let onSelectMode: (DisplayMode) -> Void

    @State private var isExpanded: Bool = false
    @State private var isDraggingBar: Bool = false
    @State private var collapseWorkItem: DispatchWorkItem?

    private var isPlaying: Bool { bridge.playbackStatus == .playing }
    private var hasActiveLyric: Bool { settings.showLyrics && bridge.currentLyricLine != nil }

    private var accentColor: Color {
        if let nsColor = bridge.ambientColor {
            return Color(nsColor: nsColor)
        }
        return Color(red: 0.98, green: 0.34, blue: 0.42)
    }

    private var topEarRadius: CGFloat { isExpanded ? 14 : 9 }
    private var bottomCornerRadius: CGFloat { isExpanded ? 24 : 13 }

    private var collapsedWidth: CGFloat {
        if metrics.hasHardwareNotch {
            // Hugs the physical camera notch + left artwork wing + right waveform wing + top ears
            return metrics.notchWidth + 96
        } else {
            return 244
        }
    }

    private var collapsedHeight: CGFloat {
        max(metrics.notchHeight, 33)
    }

    private var expandedWidth: CGFloat {
        max(396, metrics.notchWidth + 200)
    }

    private var expandedHeight: CGFloat {
        let baseTop = metrics.hasHardwareNotch ? max(metrics.notchHeight - 6, 22) : 14
        let hasTranslation = settings.showBilingualLyrics && (bridge.currentLyricLine?.translation?.isEmpty == false)
        let lyricExtra: CGFloat = hasActiveLyric ? (hasTranslation ? 42 : 26) : 0
        return baseTop + 132 + lyricExtra
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .top) {
                // Solid OLED-black island body fused seamlessly into the top bezel
                DynamicIslandShape(
                    topCornerRadius: topEarRadius,
                    bottomCornerRadius: bottomCornerRadius
                )
                .fill(.black)
                .overlay {
                    // Subtle ambient sheen inside expanded island
                    if isExpanded {
                        DynamicIslandShape(
                            topCornerRadius: topEarRadius,
                            bottomCornerRadius: bottomCornerRadius
                        )
                        .fill(
                            RadialGradient(
                                colors: [
                                    accentColor.opacity(0.22),
                                    accentColor.opacity(0.04),
                                    .clear
                                ],
                                center: .topLeading,
                                startRadius: 10,
                                endRadius: expandedWidth * 0.78
                            )
                        )
                        .allowsHitTesting(false)
                    }
                }
                .overlay {
                    DynamicIslandShape(
                        topCornerRadius: topEarRadius,
                        bottomCornerRadius: bottomCornerRadius
                    )
                    .stroke(
                        .white.opacity(isExpanded ? 0.13 : 0.06),
                        lineWidth: 0.65
                    )
                    .allowsHitTesting(false)
                }
                .shadow(
                    color: .black.opacity(isExpanded ? 0.52 : 0.25),
                    radius: isExpanded ? 20 : 6,
                    x: 0,
                    y: isExpanded ? 10 : 3
                )

                // Content inside the island
                if isExpanded {
                    expandedContent
                        .padding(.horizontal, topEarRadius + 16)
                        .padding(.top, metrics.hasHardwareNotch ? max(metrics.notchHeight - 4, 24) : 14)
                        .padding(.bottom, 14)
                        .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
                } else {
                    collapsedContent
                        .padding(.horizontal, topEarRadius + 10)
                        .frame(height: collapsedHeight)
                        .transition(.opacity)
                }
            }
            .frame(
                width: isExpanded ? expandedWidth : collapsedWidth,
                height: isExpanded ? expandedHeight : collapsedHeight,
                alignment: .top
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                handleHoverChange(hovering)
            }

            // When collapsed & lyrics enabled, gently float single-line subtitle right below the notch
            if !isExpanded, hasActiveLyric, let line = bridge.currentLyricLine {
                LyricsOverlayView(
                    line: line,
                    showTranslation: settings.showBilingualLyrics,
                    style: .vinylFloating,
                    fontStyle: settings.fontStyle,
                    textEffect: settings.textEffect,
                    ambientColor: bridge.ambientColor,
                    scale: 0.92
                )
                .frame(maxWidth: max(collapsedWidth + 80, 340))
                .transition(.opacity.combined(with: .offset(y: -4)))
                .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.38, dampingFraction: 0.80), value: isExpanded)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: hasActiveLyric)
        .onDisappear {
            collapseWorkItem?.cancel()
            collapseWorkItem = nil
        }
    }

    // MARK: - Collapsed Notch Content

    private var collapsedContent: some View {
        HStack(spacing: 8) {
            // Left wing: crisp mini artwork
            Group {
                if let artwork = bridge.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    PlaceholderArtworkView(iconSize: 10)
                }
            }
            .frame(width: 20, height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            )

            if metrics.hasHardwareNotch {
                // Keep camera cutout center completely clear
                Spacer(minLength: metrics.notchWidth - 4)
            } else {
                Text(bridge.currentTrack?.title ?? "")
                    .font(.system(size: 11.5, weight: .medium, design: settings.fontStyle.design))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Right wing: live animated waveform visualizer
            AudioWaveformView(isPlaying: isPlaying, tint: accentColor, height: 14)
        }
    }

    // MARK: - Expanded Dynamic Island Player

    private var expandedContent: some View {
        VStack(spacing: 11) {
            // Top row: Artwork + Track Info + Mode Switcher + Waveform
            HStack(spacing: 12) {
                Group {
                    if let artwork = bridge.artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        PlaceholderArtworkView(iconSize: 22)
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.16), lineWidth: 0.6)
                )
                .shadow(color: accentColor.opacity(0.35), radius: 10, x: 0, y: 4)
                .onTapGesture {
                    bridge.openAppleMusic()
                }

                VStack(alignment: .leading, spacing: 3) {
                    MarqueeText(
                        text: bridge.currentTrack?.title ?? "",
                        font: .system(size: 14, weight: .semibold, design: settings.fontStyle.design),
                        color: .white
                    )

                    Text(bridge.currentTrack?.artist ?? "")
                        .font(.system(size: 11.8, weight: .regular, design: settings.fontStyle.design))
                        .foregroundStyle(.white.opacity(0.66))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 10) {
                    AudioWaveformView(isPlaying: isPlaying, tint: accentColor, height: 16)

                    // Quick mode switches right inside the island
                    HStack(spacing: 6) {
                        IslandIconButton(systemName: "opticaldisc", helpText: "切换至黑胶唱片摆件") {
                            onSelectMode(.vinyl)
                        }
                        IslandIconButton(systemName: "rectangle.inset.filled", helpText: "切换至极简桌面小挂件") {
                            onSelectMode(.minimalCard)
                        }
                    }
                }
            }

            // Middle row: Scrubbable timeline with timestamps
            HStack(spacing: 8) {
                Text(formatTime(bridge.currentPosition))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 32, alignment: .leading)

                islandProgressBar

                Text(formatTime(bridge.currentTrack?.duration ?? 0))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 32, alignment: .trailing)
            }

            // Controls row
            HStack(spacing: 28) {
                IslandIconButton(
                    systemName: settings.showLyrics ? "quote.bubble.fill" : "quote.bubble",
                    size: 12,
                    tint: settings.showLyrics ? accentColor : .white.opacity(0.5),
                    helpText: settings.showLyrics ? "隐藏歌词" : "显示歌词"
                ) {
                    settings.showLyrics.toggle()
                    bridge.refreshLyricsForCurrentTrack()
                }

                HStack(spacing: 24) {
                    ControlIconButton(systemName: "backward.fill", size: 14, tint: .white) {
                        bridge.previousTrack()
                    }
                    ControlIconButton(systemName: isPlaying ? "pause.fill" : "play.fill", size: 19, tint: .white) {
                        bridge.togglePlayPause()
                    }
                    ControlIconButton(systemName: "forward.fill", size: 14, tint: .white) {
                        bridge.nextTrack()
                    }
                }

                IslandIconButton(
                    systemName: "music.note",
                    size: 12,
                    tint: .white.opacity(0.6),
                    helpText: "打开 Apple Music"
                ) {
                    bridge.openAppleMusic()
                }
            }

            // Embedded synced lyric row inside expanded Dynamic Island
            if hasActiveLyric, let line = bridge.currentLyricLine {
                VStack(spacing: 2) {
                    Text(line.text)
                        .font(.system(size: 12, weight: .medium, design: settings.fontStyle.design))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .id("island-orig-\(line.id)")
                        .transition(.opacity.combined(with: .offset(y: 4)))

                    if settings.showBilingualLyrics, let trans = line.translation, !trans.isEmpty {
                        Text(trans)
                            .font(.system(size: 10.5, weight: .regular, design: settings.fontStyle.design))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .id("island-trans-\(line.id)")
                            .transition(.opacity.combined(with: .offset(y: 3)))
                    }
                }
                .padding(.top, 2)
                .animation(.spring(response: 0.4, dampingFraction: 0.86), value: line.id)
            }
        }
    }

    private var islandProgressBar: some View {
        let barHeight: CGFloat = isDraggingBar ? 5.5 : 3.5

        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.18))
                    .frame(height: barHeight)

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.92), accentColor.opacity(0.95)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(
                        width: max(barHeight, geo.size.width * CGFloat(bridge.progress)),
                        height: barHeight
                    )
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDraggingBar {
                            isDraggingBar = true
                            bridge.beginScrubbing()
                        }
                        let ratio = geo.size.width > 0 ? Double(value.location.x / geo.size.width) : 0
                        bridge.updateScrubbing(progress: ratio)
                    }
                    .onEnded { value in
                        let ratio = geo.size.width > 0 ? Double(value.location.x / geo.size.width) : 0
                        isDraggingBar = false
                        bridge.commitScrubbing(progress: ratio)
                    }
            )
        }
        .frame(height: 12)
        .animation(.easeOut(duration: 0.14), value: isDraggingBar)
    }

    // MARK: - Debounced Hover Expand / Collapse

    private func handleHoverChange(_ hovering: Bool) {
        collapseWorkItem?.cancel()
        collapseWorkItem = nil

        if hovering {
            if !isExpanded {
                onExpansionChange(true)
                isExpanded = true
            }
        } else {
            let item = DispatchWorkItem {
                if !isDraggingBar {
                    isExpanded = false
                    onExpansionChange(false)
                }
            }
            collapseWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24, execute: item)
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct IslandIconButton: View {
    let systemName: String
    var size: CGFloat = 11
    var tint: Color = .white.opacity(0.68)
    let helpText: String
    let action: () -> Void

    @State private var hovered: Bool = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(hovered ? .white : tint)
                .frame(width: 22, height: 22)
                .background(.white.opacity(hovered ? 0.14 : 0.0), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(helpText)
        .onHover { hovered = $0 }
    }
}
