import SwiftUI
import AppKit

struct DevSweepApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var model = SweepModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        MainActor.assumeIsolated {
            SweepModel.shared.start()
            LoginItem.shared.enableByDefaultIfFirstRun()
            if Preferences.shared.notificationsEnabled {
                Notifier.shared.requestAuthorization()
            }
        }
    }
}
