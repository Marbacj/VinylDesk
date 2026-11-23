import AppKit
import Observation
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
@Observable
public final class NotchMetricsStore {
    public var metrics: ScreenNotchMetrics = .current()

    public func refresh() {
        metrics = .current()
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
        guard settings.displayMode != .dynamicIsland, !settings.isPositionLocked, let panel else { return }
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
    private let notchStore = NotchMetricsStore()
    private var hostingView: FirstMouseHostingView<WidgetRootView>?

    private var isProgrammaticFrameUpdate: Bool = false
    private var isCurrentlyShown: Bool = false
    private var visibilityGeneration: Int = 0
    private var lastDisplayMode: DisplayMode
    private var lastDesktopContentSize: CGSize = CGSize(width: 280, height: 200)

    private var isDynamicIslandExpanded: Bool = false
    private var islandShrinkWorkItem: DispatchWorkItem?
    private var screenObserver: NSObjectProtocol?

    public init(settings: AppSettings, bridge: AppleMusicBridge) {
        self.settings = settings
        self.bridge = bridge
        self.lastDisplayMode = settings.displayMode

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
        observeScreenChanges()
        applySettings()

        if settings.displayMode == .dynamicIsland {
            positionDynamicIsland(expanded: false)
        } else {
            restoreOrDefaultPosition(for: initialRect.size)
        }
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
            notchStore: notchStore,
            onContentSizeChange: { [weak self] newSize in
                self?.updateDesktopContentSize(newSize)
            },
            onDynamicIslandExpansionChange: { [weak self] expanded in
                self?.handleDynamicIslandExpansion(expanded)
            }
        )
        let hosting = FirstMouseHostingView(rootView: rootView)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hosting
        self.hostingView = hosting
    }

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.notchStore.refresh()
                if self.settings.displayMode == .dynamicIsland {
                    self.positionDynamicIsland(expanded: self.isDynamicIslandExpanded)
                }
            }
        }
    }

    public func applySettings() {
        let previousMode = lastDisplayMode
        let currentMode = settings.displayMode
        lastDisplayMode = currentMode

        if currentMode == .dynamicIsland {
            notchStore.refresh()
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

            if previousMode != .dynamicIsland {
                isDynamicIslandExpanded = false
            }
            positionDynamicIsland(expanded: isDynamicIslandExpanded)

            if isCurrentlyShown {
                panel.orderFrontRegardless()
            }
            return
        }

        // Non-island desktop/floating modes (Vinyl & Minimal Card)
        islandShrinkWorkItem?.cancel()
        islandShrinkWorkItem = nil
        isDynamicIslandExpanded = false

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

        if previousMode == .dynamicIsland {
            restoreOrDefaultPosition(for: lastDesktopContentSize)
        }
    }

    public func setVisible(_ visible: Bool) {
        guard visible != isCurrentlyShown else { return }
        isCurrentlyShown = visible
        visibilityGeneration += 1
        let gen = visibilityGeneration

        if visible {
            if settings.displayMode == .dynamicIsland {
                notchStore.refresh()
                positionDynamicIsland(expanded: isDynamicIslandExpanded)
                panel.orderFrontRegardless()
            } else if settings.windowLayer == .floating {
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
        if settings.displayMode == .dynamicIsland {
            notchStore.refresh()
            positionDynamicIsland(expanded: isDynamicIslandExpanded)
            return
        }
        settings.savedWindowTopLeft = nil
        restoreOrDefaultPosition(for: panel.frame.size)
    }

    // MARK: - Dynamic Island Frame Management

    private func handleDynamicIslandExpansion(_ expanded: Bool) {
        guard settings.displayMode == .dynamicIsland else { return }
        islandShrinkWorkItem?.cancel()
        islandShrinkWorkItem = nil
        isDynamicIslandExpanded = expanded

        if expanded {
            // Immediately expand panel canvas so the SwiftUI spring animates smoothly with zero clipping.
            positionDynamicIsland(expanded: true)
        } else {
            // Wait for the collapse spring to settle before shrinking panel frame so below-notch clicks pass through.
            let item = DispatchWorkItem { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.settings.displayMode == .dynamicIsland, !self.isDynamicIslandExpanded else { return }
                    self.positionDynamicIsland(expanded: false)
                }
            }
            islandShrinkWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42, execute: item)
        }
    }

    private func positionDynamicIsland(expanded: Bool) {
        let metrics = notchStore.metrics
        let screenFrame = metrics.screenFrame
        let hasActiveLyric = settings.showLyrics && bridge.currentLyricLine != nil
        let hasTranslation = settings.showBilingualLyrics && (bridge.currentLyricLine?.translation?.isEmpty == false)

        let width: CGFloat
        let height: CGFloat

        if expanded {
            width = max(448, metrics.notchWidth + 248)
            let baseTop = metrics.hasHardwareNotch ? max(metrics.notchHeight - 6, 22) : 14
            let lyricExtra: CGFloat = hasActiveLyric ? (hasTranslation ? 44 : 28) : 0
            height = baseTop + 162 + lyricExtra
        } else {
            let baseCollapsedWidth: CGFloat = metrics.hasHardwareNotch ? (metrics.notchWidth + 112) : 264
            let baseCollapsedHeight: CGFloat = max(metrics.notchHeight, 33) + 12
            if hasActiveLyric {
                width = max(baseCollapsedWidth, 380)
                height = baseCollapsedHeight + (hasTranslation ? 48 : 32)
            } else {
                width = baseCollapsedWidth
                height = baseCollapsedHeight
            }
        }

        let originX = round(screenFrame.midX - width / 2)
        let originY = screenFrame.maxY - height

        isProgrammaticFrameUpdate = true
        panel.setFrame(NSRect(x: originX, y: originY, width: width, height: height), display: true, animate: false)
        isProgrammaticFrameUpdate = false
    }

    // MARK: - Desktop / Floating Frame Management

    private func updateDesktopContentSize(_ newSize: CGSize) {
        guard settings.displayMode != .dynamicIsland else { return }
        guard newSize.width > 10, newSize.height > 10 else { return }
        let roundedSize = CGSize(width: ceil(newSize.width), height: ceil(newSize.height))
        guard abs(roundedSize.width - lastDesktopContentSize.width) > 0.5 ||
              abs(roundedSize.height - lastDesktopContentSize.height) > 0.5 else {
            return
        }
        lastDesktopContentSize = roundedSize

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
        guard !isProgrammaticFrameUpdate, settings.displayMode != .dynamicIsland else { return }
        let frame = panel.frame
        settings.savedWindowTopLeft = CGPoint(x: frame.minX, y: frame.maxY)
    }
}
