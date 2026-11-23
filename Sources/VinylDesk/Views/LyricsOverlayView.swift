import AppKit
import SwiftUI

enum LyricPresentationStyle {
    case cardEmbedded
    case vinylFloating
}

struct LyricsOverlayView: View {
    let line: LyricLine
    let showTranslation: Bool
    let style: LyricPresentationStyle
    let fontStyle: FontStyleOption
    let textEffect: TextEffectStyle
    let ambientColor: NSColor?
    let scale: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    private var translationText: String? {
        guard showTranslation, let trans = line.translation, !trans.isEmpty else { return nil }
        return trans
    }

    private var accentSwiftUIColor: Color {
        if let ambientColor {
            return Color(nsColor: ambientColor)
        }
        return Color.accentColor
    }

    private var lineTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.965))
                .combined(with: .offset(y: 5)),
            removal: .opacity
                .combined(with: .offset(y: -4))
        )
    }

    var body: some View {
        Group {
            switch style {
            case .cardEmbedded:
                cardContent
            case .vinylFloating:
                vinylContent
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: line.id)
    }

    // MARK: - Minimal Card Embedded Lyrics

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 2.5 * scale) {
            primaryStyledText(
                line.text,
                size: 12 * scale,
                weight: fontStyle == .serif ? .medium : .medium,
                alignment: .leading
            )
            .id("orig-\(line.id)")
            .transition(lineTransition)

            if let trans = translationText {
                Text(trans)
                    .font(.system(size: 10.5 * scale, weight: .regular, design: fontStyle.design))
                    .foregroundStyle(.secondary.opacity(0.90))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .id("trans-\(line.id)")
                    .transition(lineTransition)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Vinyl Floating Lyrics

    @ViewBuilder
    private var vinylContent: some View {
        switch textEffect {
        case .cinemaSubtitle:
            cinemaSubtitleContent
        case .ambientGlow:
            ambientGlowContent
        case .frostedPill:
            frostedPillContent
        }
    }

    /// Clean movie-subtitle style: no capsule box, pure typography with layered soft shadows readable on any wallpaper.
    private var cinemaSubtitleContent: some View {
        let primaryColor: Color = colorScheme == .dark ? .white.opacity(0.96) : .black.opacity(0.88)
        let secondaryColor: Color = colorScheme == .dark ? .white.opacity(0.76) : .black.opacity(0.66)
        let tightShadow: Color = colorScheme == .dark ? .black.opacity(0.82) : .white.opacity(0.95)
        let softHalo: Color = colorScheme == .dark ? .black.opacity(0.50) : .white.opacity(0.72)

        return VStack(spacing: 3 * scale) {
            Text(line.text)
                .font(.system(size: 13.5 * scale, weight: .medium, design: fontStyle.design))
                .tracking(fontStyle == .serif ? 0.6 : 0.25)
                .foregroundStyle(primaryColor)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .truncationMode(.tail)
                .shadow(color: tightShadow, radius: 2.2, x: 0, y: 1)
                .shadow(color: softHalo, radius: 9, x: 0, y: 2)
                .id("v-cinema-orig-\(line.id)")
                .transition(lineTransition)

            if let trans = translationText {
                Text(trans)
                    .font(.system(size: 11 * scale, weight: .regular, design: fontStyle.design))
                    .tracking(0.2)
                    .foregroundStyle(secondaryColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .shadow(color: tightShadow, radius: 2, x: 0, y: 1)
                    .shadow(color: softHalo, radius: 7, x: 0, y: 1.5)
                    .id("v-cinema-trans-\(line.id)")
                    .transition(lineTransition)
            }
        }
        .padding(.horizontal, 6 * scale)
        .padding(.vertical, 2 * scale)
    }

    /// Ambient cover-tinted glow style: subtle gradient typography with soft colored bloom.
    private var ambientGlowContent: some View {
        let baseColor: Color = colorScheme == .dark ? .white : .black.opacity(0.9)
        let grad = LinearGradient(
            colors: [baseColor, accentSwiftUIColor.opacity(colorScheme == .dark ? 0.95 : 0.85), baseColor],
            startPoint: .leading,
            endPoint: .trailing
        )
        let baseShadow: Color = colorScheme == .dark ? .black.opacity(0.72) : .white.opacity(0.9)

        return VStack(spacing: 3 * scale) {
            Text(line.text)
                .font(.system(size: 13.5 * scale, weight: .semibold, design: fontStyle.design))
                .tracking(fontStyle == .serif ? 0.6 : 0.25)
                .foregroundStyle(grad)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .truncationMode(.tail)
                .shadow(color: baseShadow, radius: 2, x: 0, y: 1)
                .shadow(color: accentSwiftUIColor.opacity(colorScheme == .dark ? 0.68 : 0.42), radius: 10, x: 0, y: 0)
                .id("v-glow-orig-\(line.id)")
                .transition(lineTransition)

            if let trans = translationText {
                Text(trans)
                    .font(.system(size: 11 * scale, weight: .regular, design: fontStyle.design))
                    .foregroundStyle(baseColor.opacity(0.76))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .shadow(color: baseShadow, radius: 2, x: 0, y: 1)
                    .shadow(color: accentSwiftUIColor.opacity(0.35), radius: 7, x: 0, y: 0)
                    .id("v-glow-trans-\(line.id)")
                    .transition(lineTransition)
            }
        }
        .padding(.horizontal, 8 * scale)
        .padding(.vertical, 2 * scale)
    }

    /// Classic frosted capsule pill for maximum contrast on complex wallpapers.
    private var frostedPillContent: some View {
        VStack(spacing: 2 * scale) {
            Text(line.text)
                .font(.system(size: 12.2 * scale, weight: .medium, design: fontStyle.design))
                .tracking(fontStyle == .serif ? 0.4 : 0.15)
                .foregroundStyle(.primary.opacity(0.94))
                .lineLimit(1)
                .truncationMode(.tail)
                .id("v-pill-orig-\(line.id)")
                .transition(lineTransition)

            if let trans = translationText {
                Text(trans)
                    .font(.system(size: 10.5 * scale, weight: .regular, design: fontStyle.design))
                    .foregroundStyle(.secondary.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .id("v-pill-trans-\(line.id)")
                    .transition(lineTransition)
            }
        }
        .padding(.horizontal, 12 * scale)
        .padding(.vertical, 5.5 * scale)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.10),
                            lineWidth: 0.6
                        )
                )
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.14), radius: 8, x: 0, y: 3)
        }
    }

    @ViewBuilder
    private func primaryStyledText(
        _ text: String,
        size: CGFloat,
        weight: Font.Weight,
        alignment: TextAlignment
    ) -> some View {
        if textEffect == .ambientGlow {
            let base: Color = colorScheme == .dark ? .white.opacity(0.95) : .black.opacity(0.88)
            Text(text)
                .font(.system(size: size, weight: weight, design: fontStyle.design))
                .tracking(fontStyle == .serif ? 0.4 : 0.15)
                .foregroundStyle(
                    LinearGradient(
                        colors: [base, accentSwiftUIColor.opacity(0.92), base],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .shadow(color: accentSwiftUIColor.opacity(0.42), radius: 6, x: 0, y: 0)
                .multilineTextAlignment(alignment)
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            Text(text)
                .font(.system(size: size, weight: weight, design: fontStyle.design))
                .tracking(fontStyle == .serif ? 0.4 : 0.15)
                .foregroundStyle(.primary.opacity(0.88))
                .multilineTextAlignment(alignment)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
