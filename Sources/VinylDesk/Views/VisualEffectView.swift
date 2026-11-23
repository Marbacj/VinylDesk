import AppKit
import SwiftUI

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

/// Smooth marquee text that only scrolls when text actually overflows its available width.
struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offsetX: CGFloat = 0
    @State private var animationToken: UUID = UUID()

    private let gap: CGFloat = 36

    private var shouldScroll: Bool {
        textWidth > containerWidth + 2 && containerWidth > 0
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Hidden measurement text
                Text(text)
                    .font(font)
                    .fixedSize(horizontal: true, vertical: false)
                    .background(
                        GeometryReader { textGeo in
                            Color.clear.preference(key: TextWidthKey.self, value: textGeo.size.width)
                        }
                    )
                    .hidden()

                if shouldScroll {
                    HStack(spacing: gap) {
                        Text(text)
                            .font(font)
                            .foregroundStyle(color)
                            .fixedSize(horizontal: true, vertical: false)
                        Text(text)
                            .font(font)
                            .foregroundStyle(color)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .offset(x: offsetX)
                } else {
                    Text(text)
                        .font(font)
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(width: geo.size.width, alignment: .leading)
            .clipped()
            .mask(
                Group {
                    if shouldScroll {
                        HStack(spacing: 0) {
                            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                                .frame(width: 6)
                            Rectangle().fill(.black)
                            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: 10)
                        }
                    } else {
                        Rectangle().fill(.black)
                    }
                }
            )
            .onAppear {
                containerWidth = geo.size.width
                restartScrollIfNeeded()
            }
            .onChange(of: geo.size.width) { _, newWidth in
                containerWidth = newWidth
                restartScrollIfNeeded()
            }
            .onChange(of: text) { _, _ in
                offsetX = 0
                restartScrollIfNeeded()
            }
            .onPreferenceChange(TextWidthKey.self) { width in
                if abs(width - textWidth) > 0.5 {
                    textWidth = width
                    restartScrollIfNeeded()
                }
            }
        }
        .frame(height: 19)
    }

    private func restartScrollIfNeeded() {
        let token = UUID()
        animationToken = token
        offsetX = 0

        guard shouldScroll else { return }
        let distance = textWidth + gap
        let duration = max(4.0, Double(distance) / 28.0)

        Task { @MainActor in
            while animationToken == token && shouldScroll {
                try? await Task.sleep(for: .seconds(2.2))
                guard animationToken == token else { return }
                withAnimation(.linear(duration: duration)) {
                    offsetX = -distance
                }
                try? await Task.sleep(for: .seconds(duration + 0.1))
                guard animationToken == token else { return }
                offsetX = 0
            }
        }
    }
}

private struct TextWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct PlaceholderArtworkView: View {
    let iconSize: CGFloat

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .controlAccentColor).opacity(0.45),
                    Color.primary.opacity(0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}
