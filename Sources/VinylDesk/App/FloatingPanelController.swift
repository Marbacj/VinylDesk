import AppKit
import SwiftUI

private final class VinylPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

@MainActor
public final class WindowDragSession {
    private weak var panel: NSPanel?
    private let settings: AppSettings

    private var isDragging: Bool = false
    private var startMouseLocation: NSPoint = .zero
    private var startWindowOrigin: NSPoint = .zero

    public init(panel: NSPanel, settings: AppSettings) {
        self.panel = panel
        self.settings = settings
    }

    public func handleDragChanged() {
        guard !settings.isPositionLocked, let panel else { return }
        let currentMouse = NSEvent.mouseLocation

        if !isDragging {
            isDragging = true
            startMouseLocation = currentMouse
            startWindowOrigin = panel.frame.origin
            return
        }

        let dx = currentMouse.x - startMouseLocation.x
        let dy = currentMouse.y - startMouseLocation.y
        panel.setFrameOrigin(NSPoint(x: startWindowOrigin.x + dx, y: startWindowOrigin.y + dy))
    }

    public func handleDragEnded() {
        guard isDragging, let panel else { return }
        isDragging = false
        let frame = panel.frame
        settings.savedWindowTopLeft = CGPoint(x: frame.minX, y: frame.maxY)
    }
}

@MainActor
public final class FloatingPanelController: NSObject, NSWindowDelegate {
    private let settings: AppSettings
    private let bridge: AppleMusicBridge
    private let panel: VinylPanel
    private let dragSession: WindowDragSession
    private var hostingView: FirstMouseHostingView<WidgetRootView>?

    private var isProgrammaticFrameUpdate: Bool = false
    private var isCurrentlyShown: Bool = false
    private var visibilityGeneration: Int = 0
    private var lastContentSize: CGSize = CGSize(width: 280, height: 200)

    public init(settings: AppSettings, bridge: AppleMusicBridge) {
        self.settings = settings
        self.bridge = bridge

        let initialRect = NSRect(x: 80, y: 80, width: 280, height: 200)
        self.panel = VinylPanel(
            contentRect: initialRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.dragSession = WindowDragSession(panel: self.panel, settings: settings)

        super.init()

        configurePanel()
        setupContentView()
        applySettings()
        restoreOrDefaultPosition(for: initialRect.size)
    }

    private func configurePanel() {
        panel.delegate = self
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = true
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = false
        panel.isReleasedWhenClosed = false
        panel.alphaValue = 0
    }

    private func setupContentView() {
        let rootView = WidgetRootView(
            bridge: bridge,
            settings: settings,
            dragSession: dragSession,
            onContentSizeChange: { [weak self] newSize in
                self?.updateContentSize(newSize)
            }
        )
        let hosting = FirstMouseHostingView(rootView: rootView)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hosting
        self.hostingView = hosting
    }

    public func applySettings() {
        switch settings.windowLayer {
        case .desktop:
            let desktopLevel = Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
            panel.level = NSWindow.Level(rawValue: desktopLevel)
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        case .floating:
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            if isCurrentlyShown {
                panel.orderFrontRegardless()
            }
        }
    }

    public func setVisible(_ visible: Bool) {
        guard visible != isCurrentlyShown else { return }
        isCurrentlyShown = visible
        visibilityGeneration += 1
        let gen = visibilityGeneration

        if visible {
            if settings.windowLayer == .floating {
                panel.orderFrontRegardless()
            } else {
                panel.orderFront(nil)
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1.0
            }
        } else {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.30
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0.0
            }, completionHandler: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.visibilityGeneration == gen, !self.isCurrentlyShown else { return }
                    self.panel.orderOut(nil)
                }
            })
        }
    }

    public func resetPosition() {
        settings.savedWindowTopLeft = nil
        restoreOrDefaultPosition(for: panel.frame.size)
    }

    private func updateContentSize(_ newSize: CGSize) {
        guard newSize.width > 10, newSize.height > 10 else { return }
        let roundedSize = CGSize(width: ceil(newSize.width), height: ceil(newSize.height))
        guard abs(roundedSize.width - lastContentSize.width) > 0.5 ||
              abs(roundedSize.height - lastContentSize.height) > 0.5 else {
            return
        }
        lastContentSize = roundedSize

        // Anchor top-left corner so expanding lyrics or toggling modes never drifts downward.
        let currentFrame = panel.frame
        let topLeft = CGPoint(x: currentFrame.minX, y: currentFrame.maxY)
        let targetOrigin = CGPoint(x: topLeft.x, y: topLeft.y - roundedSize.height)
        let clampedOrigin = clampOrigin(targetOrigin, for: roundedSize)

        isProgrammaticFrameUpdate = true
        panel.setFrame(NSRect(origin: clampedOrigin, size: roundedSize), display: true, animate: false)
        isProgrammaticFrameUpdate = false
    }

    private func restoreOrDefaultPosition(for size: CGSize) {
        isProgrammaticFrameUpdate = true
        defer { isProgrammaticFrameUpdate = false }

        if let savedTopLeft = settings.savedWindowTopLeft {
            let origin = CGPoint(x: savedTopLeft.x, y: savedTopLeft.y - size.height)
            let clamped = clampOrigin(origin, for: size)
            panel.setFrame(NSRect(origin: clamped, size: size), display: true)
        } else if let screen = NSScreen.main ?? NSScreen.screens.first {
            let visible = screen.visibleFrame
            // Tasteful default placement: bottom-left desktop corner with breathing margin.
            let x = visible.minX + 36
            let y = visible.minY + 42
            panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
            settings.savedWindowTopLeft = CGPoint(x: x, y: y + size.height)
        }
    }

    private func clampOrigin(_ origin: CGPoint, for size: CGSize) -> CGPoint {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return origin }

        let targetCenter = CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
        let screen = screens.first { $0.frame.contains(targetCenter) } ?? NSScreen.main ?? screens[0]
        let bounds = screen.visibleFrame

        let minX = bounds.minX - 12
        let maxX = max(minX, bounds.maxX - size.width + 12)
        let minY = bounds.minY - 12
        let maxY = max(minY, bounds.maxY - size.height + 12)

        return CGPoint(
            x: min(max(origin.x, minX), maxX),
            y: min(max(origin.y, minY), maxY)
        )
    }

    // MARK: - NSWindowDelegate

    public func windowDidMove(_ notification: Notification) {
        guard !isProgrammaticFrameUpdate else { return }
        let frame = panel.frame
        settings.savedWindowTopLeft = CGPoint(x: frame.minX, y: frame.maxY)
    }
}
