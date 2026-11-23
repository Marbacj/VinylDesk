import SwiftUI

@main
struct VinylDeskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                settings: appDelegate.coordinator.settings,
                bridge: appDelegate.coordinator.bridge,
                loginItemManager: appDelegate.coordinator.loginItemManager,
                onResetPosition: {
                    appDelegate.coordinator.panelController.resetPosition()
                }
            )
        } label: {
            Image(systemName: "opticaldisc")
                .symbolRenderingMode(.hierarchical)
                .accessibilityLabel("VinylDesk")
        }
        .menuBarExtraStyle(.menu)
    }
}
