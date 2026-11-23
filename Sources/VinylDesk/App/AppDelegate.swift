import AppKit
import Observation
import SwiftUI

@MainActor
public final class AppCoordinator {
    public let settings: AppSettings
    public let bridge: AppleMusicBridge
    public let loginItemManager: LoginItemManager
    public let panelController: FloatingPanelController

    private var isObserving: Bool = false

    public init() {
        let settings = AppSettings()
        let bridge = AppleMusicBridge(settings: settings)
        let loginItemManager = LoginItemManager()
        let panelController = FloatingPanelController(settings: settings, bridge: bridge)

        self.settings = settings
        self.bridge = bridge
        self.loginItemManager = loginItemManager
        self.panelController = panelController
    }

    public func start() {
        NSApp.setActivationPolicy(.accessory)
        bridge.start()
        syncPanelState()
        startObservationLoop()
    }

    public func stop() {
        isObserving = false
        bridge.stop()
    }

    private func startObservationLoop() {
        guard !isObserving else { return }
        isObserving = true
        observeChanges()
    }

    private func observeChanges() {
        guard isObserving else { return }
        withObservationTracking {
            _ = settings.windowLayer
            _ = settings.isPositionLocked
            _ = bridge.shouldShowWidget
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isObserving else { return }
                self.syncPanelState()
                self.observeChanges()
            }
        }
    }

    private func syncPanelState() {
        panelController.applySettings()
        panelController.setVisible(bridge.shouldShowWidget)
    }
}

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public let coordinator = AppCoordinator()

    public func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.start()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }
}
