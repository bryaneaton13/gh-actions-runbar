import AppKit
import SwiftUI

@main
struct RunBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel(store: store)
        } label: {
            StatusBarLabel(summary: store.summary, isRefreshing: store.isRefreshing)
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: RunBarWindow.settings) {
            SettingsView(store: store)
        }
        .defaultSize(width: 560, height: 560)
        .windowResizability(.contentMinSize)

        Window("Run workflow", id: RunBarWindow.runWorkflow) {
            WorkflowDispatchView(store: store)
        }
        .defaultSize(width: 440, height: 390)
        .windowResizability(.contentMinSize)
    }
}
