import AppKit
import SwiftUI

@main
struct RunBarApp: App {
    private enum WindowID {
        static let settings = "settings"
    }

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel(store: store)
        } label: {
            StatusBarLabel(summary: store.summary, isRefreshing: store.isRefreshing)
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: WindowID.settings) {
            SettingsView(store: store)
        }
        .defaultSize(width: 560, height: 560)
        .windowResizability(.contentMinSize)
    }
}
