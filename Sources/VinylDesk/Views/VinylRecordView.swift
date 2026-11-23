import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class VinylSpinDriver {
    private(set) var angleDegrees: Double = 0
    private var angularVelocity: Double = 0 // degrees per second
    private var targetIsPlaying: Bool = false
    private var lastTick: CFTimeInterval = 0
    private var timer: Timer?

    private let cruiseSpeed: Double = 34.0 // calm, realistic visual speed

    func setPlaying(_ playing: Bool) {
        targetIsPlaying = playing
        if playing || angularVelocity > 0.15 {
            startTimerIfNeeded()
        }
    }

    func stopImmediately() {
        timer?.invalidate()
        timer = nil
        angularVelocity = 0
    }

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        lastTick = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.step()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func step() {
        let now = CACurrentMediaTime()
        let dt = min(max(now - lastTick, 0), 0.05)
        lastTick = now

        if targetIsPlaying {
            angularVelocity += (cruiseSpeed - angularVelocity) * min(1.0, dt * 4.2)
        } else {
            angularVelocity *= exp(-dt * 3.6)
            if angularVelocity < 0.15 {
                angularVelocity = 0
                timer?.invalidate()
                timer = nil
                return
            }
        }

        angleDegrees = (angleDegrees + angularVelocity * dt).truncatingRemainder(dividingBy: 360.0)
    }
}

struct VinylRecordView: View {
    let bridge: AppleMusicBridge
    let settings: AppSettings
    let dragSession: WindowDragSession
    let onSelectMode: (DisplayMode) -> Void

    @State private var isHovered: Bool = false
    @State private var spinDriver = VinylSpinDriver()
    @Environment(\.colorScheme) private var colorScheme

    private var scale: CGFloat { settings.widgetSize.scaleFactor }
    private var sleeveSize: CGFloat { 164 * scale }
    private var discSize: CGFloat { 154 * scale }
    private var isPlaying: Bool { bridge.playbackStatus == .playing }

    private var discOffsetX: CGFloat {
        isPlaying ? sleeveSize * 0.45 : sleeveSize * 0.22
    }

    private var totalVisualWidth: CGFloat {
        sleeveSize + discSize * 0.50
    }

    var body: some View {
        VStack(spacing: 10 * scale) {
            ZStack(alignment: .leading) {
                // 1. Half-exposed spinning vinyl record behind sleeve
                VinylDiscView(
                    artwork: bridge.artwork,
                    size: discSize,
                    angleDegrees: spinDriver.angleDegrees
                )
                .offset(x: discOffsetX)
                .shadow(
                    color: .black.opacity(colorScheme == .dark ? 0.52 : 0.28),
                    radius: 14 * scale,
                    x: 4 * scale,
                    y: 8 * scale
                )
                .animation(.spring(response: 0.65, dampingFraction: 0.80), value: isPlaying)

                // 2. Physical album jacket / sleeve
                sleeveView
                    .zIndex(2)
            }
            .frame(width: totalVisualWidth, height: sleeveSize, alignment: .leading)
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.20)) {
                    isHovered = hovering
                }
            }

            // 3. Embedded floating lyric line below the vinyl ornament
            if settings.showLyrics, let line = bridge.currentLyricLine {
                LyricsOverlayView(
                    line: line,
                    showTranslation: settings.showBilingualLyrics,
                    style: .vinylFloating,
                    fontStyle: settings.fontStyle,
                    textEffect: settings.textEffect,
                    ambientColor: bridge.ambientColor,
                    scale: scale
                )
                .frame(maxWidth: totalVisualWidth + 44 * scale)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .padding(.horizontal, 18 * scale)
        .padding(.top, 14 * scale)
        .padding(.bottom, 16 * scale)
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: bridge.currentLyricLine != nil && settings.showLyrics)
        .onAppear {
            spinDriver.setPlaying(isPlaying)
        }
        .onChange(of: isPlaying) { _, newValue in
            spinDriver.setPlaying(newValue)
        }
        .onDisappear {
            spinDriver.stopImmediately()
        }
    }

    private var sleeveView: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let artwork = bridge.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                } else {
                    PlaceholderArtworkView(iconSize: 38 * scale)
                }
            }
            .frame(width: sleeveSize, height: sleeveSize)
            .clipped()
            .id(bridge.currentTrack?.cacheKey ?? "none")
            .animation(.easeInOut(duration: 0.35), value: bridge.currentTrack?.cacheKey)
            .tapOrWindowDrag(dragSession: dragSession) {
                bridge.openAppleMusic()
            }

            // Subtle physical sleeve spine & paper sheen details
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [.white.opacity(0.24), .black.opacity(0.18), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 7 * scale)
                Spacer()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.18)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 5 * scale)
            }
            .allowsHitTesting(false)

            // Hover-only glass overlay with track info & playback controls
            if isHovered {
                hoverOverlay
                    .transition(.opacity)
            }
        }
        .frame(width: sleeveSize, height: sleeveSize)
        .clipShape(RoundedRectangle(cornerRadius: 7 * scale, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7 * scale, style: .continuous)
                .strokeBorder(.white.opacity(colorScheme == .dark ? 0.16 : 0.35), lineWidth: 0.7)
        )
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.55 : 0.30),
            radius: 16 * scale,
            x: 2 * scale,
            y: 9 * scale
        )
    }

    private var hoverOverlay: some View {
        ZStack {
            LinearGradient(
                colors: [
                    .black.opacity(0.16),
                    .black.opacity(0.42),
                    .black.opacity(0.76)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                // Top-right quick mode switch buttons (Card / Dynamic Island)
                HStack(spacing: 5 * scale) {
                    Spacer()
                    Button {
                        onSelectMode(.minimalCard)
                    } label: {
                        Image(systemName: "rectangle.inset.filled")
                            .font(.system(size: 10.5 * scale, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .frame(width: 23 * scale, height: 23 * scale)
                            .background(.ultraThinMaterial.opacity(0.85), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("切换至极简桌面小挂件")

                    Button {
                        onSelectMode(.dynamicIsland)
                    } label: {
                        Image(systemName: "capsule.tophalf.filled")
                            .font(.system(size: 10.5 * scale, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .frame(width: 23 * scale, height: 23 * scale)
                            .background(.ultraThinMaterial.opacity(0.85), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("切换至灵动岛")
                }
                .padding(8 * scale)

                Spacer()

                // Track title & artist + compact controls
                VStack(spacing: 7 * scale) {
                    VStack(spacing: 2 * scale) {
                        Text(bridge.currentTrack?.title ?? "")
                            .font(.system(size: 12.8 * scale, weight: .semibold, design: settings.fontStyle.design))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text(bridge.currentTrack?.artist ?? "")
                            .font(.system(size: 10.5 * scale, weight: .medium, design: settings.fontStyle.design))
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .padding(.horizontal, 10 * scale)

                    HStack(spacing: 16 * scale) {
                        ControlIconButton(
                            systemName: "backward.fill",
                            size: 13 * scale,
                            tint: .white
                        ) {
                            bridge.previousTrack()
                        }

                        ControlIconButton(
                            systemName: isPlaying ? "pause.fill" : "play.fill",
                            size: 16 * scale,
                            tint: .white
                        ) {
                            bridge.togglePlayPause()
                        }

                        ControlIconButton(
                            systemName: "forward.fill",
                            size: 13 * scale,
                            tint: .white
                        ) {
                            bridge.nextTrack()
                        }
                    }
                    .padding(.bottom, 11 * scale)
                }
            }
        }
    }
}

/// Realistic vinyl disc: micro-grooves + fixed diagonal specular sheen + spinning album center label.
private struct VinylDiscView: View {
    let artwork: NSImage?
    let size: CGFloat
    let angleDegrees: Double

    var body: some View {
        ZStack {
            // Base matte-black vinyl surface
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.11, green: 0.11, blue: 0.125),
                            Color(red: 0.055, green: 0.055, blue: 0.065),
                            Color(red: 0.08, green: 0.08, blue: 0.092),
                            Color(red: 0.035, green: 0.035, blue: 0.042)
                        ],
                        center: .center,
                        startRadius: size * 0.16,
                        endRadius: size * 0.50
                    )
                )

            // Fine concentric vinyl grooves
            Canvas { context, canvasSize in
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let minRadius = canvasSize.width * 0.21
                let maxRadius = canvasSize.width * 0.482
                let step = max(1.6, canvasSize.width * 0.014)

                var r = minRadius
                var idx = 0
                while r < maxRadius {
                    let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
                    let path = Path(ellipseIn: rect)
                    let opacity: Double = (idx % 4 == 0) ? 0.11 : 0.045
                    context.stroke(path, with: .color(.white.opacity(opacity)), lineWidth: 0.55)
                    r += step
                    idx += 1
                }
            }

            // Fixed conical light sheen (stays anchored to room light while disc rotates underneath)
            Circle()
                .fill(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: .white.opacity(0.00), location: 0.00),
                            .init(color: .white.opacity(0.16), location: 0.10),
                            .init(color: .white.opacity(0.02), location: 0.22),
                            .init(color: .white.opacity(0.00), location: 0.46),
                            .init(color: .white.opacity(0.14), location: 0.60),
                            .init(color: .white.opacity(0.02), location: 0.72),
                            .init(color: .white.opacity(0.00), location: 1.00)
                        ]),
                        center: .center
                    )
                )
                .blendMode(.screen)

            // Outer rim bevel
            Circle()
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.8)

            // Rotating center album label + spindle hole
            ZStack {
                Group {
                    if let artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        PlaceholderArtworkView(iconSize: size * 0.12)
                    }
                }
                .frame(width: size * 0.36, height: size * 0.36)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .strokeBorder(.black.opacity(0.45), lineWidth: 1.5)
                )

                // Center spindle hole
                Circle()
                    .fill(Color(red: 0.08, green: 0.08, blue: 0.09))
                    .frame(width: size * 0.055, height: size * 0.055)
                    .overlay(
                        Circle()
                            .strokeBorder(.white.opacity(0.28), lineWidth: 0.7)
                    )
            }
            .rotationEffect(.degrees(angleDegrees))
        }
        .frame(width: size, height: size)
        .drawingGroup()
    }
}

struct ControlIconButton: View {
    let systemName: String
    let size: CGFloat
    let tint: Color
    let action: () -> Void

    @State private var isHovering: Bool = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(tint.opacity(isHovering ? 1.0 : 0.86))
                .scaleEffect(isHovering ? 1.12 : 1.0)
                .frame(width: size + 12, height: size + 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovering = hovering
            }
        }
    }
}
