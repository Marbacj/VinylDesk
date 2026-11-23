import AppKit
import SwiftUI

struct MinimalCardView: View {
    let bridge: AppleMusicBridge
    let settings: AppSettings
    let dragSession: WindowDragSession
    let onSelectMode: (DisplayMode) -> Void

    @State private var isHovered: Bool = false
    @State private var isDraggingBar: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    private var scale: CGFloat { settings.widgetSize.scaleFactor }
    private var cardWidth: CGFloat { 316 * scale }
    private var artworkSize: CGFloat { 58 * scale }
    private var cornerRadius: CGFloat { 18 * scale }
    private var isPlaying: Bool { bridge.playbackStatus == .playing }

    private var ambientSwiftUIColor: Color {
        if let nsColor = bridge.ambientColor {
            return Color(nsColor: nsColor)
        }
        return Color.accentColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9 * scale) {
            // Main horizontal row: Artwork + Metadata/Controls + Progress
            HStack(spacing: 12 * scale) {
                artworkThumbnail

                VStack(alignment: .leading, spacing: 5 * scale) {
                    // Title row (+ subtle mode switch button on hover)
                    HStack(spacing: 6 * scale) {
                        MarqueeText(
                            text: bridge.currentTrack?.title ?? "",
                            font: .system(size: 13.8 * scale, weight: .semibold, design: settings.fontStyle.design),
                            color: .primary
                        )

                        if isHovered {
                            HStack(spacing: 4 * scale) {
                                Button {
                                    onSelectMode(.vinyl)
                                } label: {
                                    Image(systemName: "opticaldisc")
                                        .font(.system(size: 11.5 * scale, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 20 * scale, height: 20 * scale)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help("切换至黑胶唱片摆件")

                                Button {
                                    onSelectMode(.dynamicIsland)
                                } label: {
                                    Image(systemName: "capsule.tophalf.filled")
                                        .font(.system(size: 11.5 * scale, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 20 * scale, height: 20 * scale)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help("切换至灵动岛")
                            }
                            .transition(.opacity)
                        }
                    }

                    // Middle row: cleanly crossfades between Artist (resting) and Playback Controls (hovered)
                    ZStack(alignment: .leading) {
                        Text(bridge.currentTrack?.artist ?? "")
                            .font(.system(size: 11.5 * scale, weight: .regular, design: settings.fontStyle.design))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .opacity(isHovered ? 0 : 1)

                        if isHovered {
                            HStack(spacing: 16 * scale) {
                                ControlIconButton(
                                    systemName: "backward.fill",
                                    size: 11.5 * scale,
                                    tint: .primary
                                ) {
                                    bridge.previousTrack()
                                }

                                ControlIconButton(
                                    systemName: isPlaying ? "pause.fill" : "play.fill",
                                    size: 13 * scale,
                                    tint: .primary
                                ) {
                                    bridge.togglePlayPause()
                                }

                                ControlIconButton(
                                    systemName: "forward.fill",
                                    size: 11.5 * scale,
                                    tint: .primary
                                ) {
                                    bridge.nextTrack()
                                }

                                Spacer(minLength: 0)

                                Text(formatTime(bridge.currentPosition))
                                    .font(.system(size: 10 * scale, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .transition(.opacity)
                        }
                    }
                    .frame(height: 20 * scale)

                    // Ultra-thin scrubbable progress bar
                    scrubbableProgressBar
                }
            }

            // Embedded bottom lyric line inside the card
            if settings.showLyrics, let line = bridge.currentLyricLine {
                VStack(spacing: 6 * scale) {
                    Rectangle()
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.09 : 0.07))
                        .frame(height: 0.6)

                    LyricsOverlayView(
                        line: line,
                        showTranslation: settings.showBilingualLyrics,
                        style: .cardEmbedded,
                        fontStyle: settings.fontStyle,
                        textEffect: settings.textEffect,
                        ambientColor: bridge.ambientColor,
                        scale: scale
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.horizontal, 13 * scale)
        .padding(.vertical, 12 * scale)
        .frame(width: cardWidth)
        .background {
            ZStack {
                VisualEffectView(
                    material: .hudWindow,
                    blendingMode: .behindWindow,
                    state: .active
                )

                // Subtle ambient glow from album artwork
                RadialGradient(
                    colors: [
                        ambientSwiftUIColor.opacity(colorScheme == .dark ? 0.24 : 0.15),
                        ambientSwiftUIColor.opacity(colorScheme == .dark ? 0.06 : 0.03),
                        .clear
                    ],
                    center: .topLeading,
                    startRadius: 8,
                    endRadius: cardWidth * 0.85
                )
                .animation(.easeInOut(duration: 0.65), value: bridge.ambientColor)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.11),
                    lineWidth: 0.7
                )
        )
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.45 : 0.16),
            radius: 18 * scale,
            x: 0,
            y: 8 * scale
        )
        .padding(16 * scale)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.18)) {
                isHovered = hovering
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: bridge.currentLyricLine != nil && settings.showLyrics)
    }

    private var artworkThumbnail: some View {
        Group {
            if let artwork = bridge.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                PlaceholderArtworkView(iconSize: 22 * scale)
            }
        }
        .frame(width: artworkSize, height: artworkSize)
        .clipShape(RoundedRectangle(cornerRadius: 11 * scale, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11 * scale, style: .continuous)
                .strokeBorder(.white.opacity(colorScheme == .dark ? 0.14 : 0.35), lineWidth: 0.6)
        )
        .shadow(color: .black.opacity(0.22), radius: 6 * scale, x: 0, y: 3 * scale)
        .id(bridge.currentTrack?.cacheKey ?? "none")
        .animation(.easeInOut(duration: 0.3), value: bridge.currentTrack?.cacheKey)
        .tapOrWindowDrag(dragSession: dragSession) {
            bridge.openAppleMusic()
        }
    }

    private var scrubbableProgressBar: some View {
        let barHeight: CGFloat = (isHovered || isDraggingBar) ? 4.5 * scale : 2.6 * scale

        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.12))
                    .frame(height: barHeight)

                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.82 : 0.72))
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
        .frame(height: 10 * scale)
        .animation(.easeOut(duration: 0.14), value: isHovered || isDraggingBar)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
