import ServiceManagement

enum LaunchAtLogin {
    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
            return
        }
        do {
            try SMAppService.mainApp.unregister()
        } catch {
            // Already unregistered when running from `swift run`.
        }
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
