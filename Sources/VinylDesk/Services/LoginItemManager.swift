import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
public final class LoginItemManager {
    public private(set) var isEnabled: Bool = false
    public private(set) var lastErrorMessage: String?

    public init() {
        refreshStatus()
    }

    public func refreshStatus() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    public func setEnabled(_ enabled: Bool) {
        lastErrorMessage = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshStatus()
        } catch {
            lastErrorMessage = error.localizedDescription
            refreshStatus()
        }
    }
}
