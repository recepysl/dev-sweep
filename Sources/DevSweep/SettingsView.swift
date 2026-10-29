import SwiftUI
import AppKit
import SweepKit

@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(preferences: .shared, login: .shared, onExclusionsChanged: {
                SweepModel.shared.scan()
            }))
            let newWindow = NSWindow(contentViewController: controller)
            newWindow.title = "DevSweep Settings"
            newWindow.styleMask = [.titled, .closable]
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var login: LoginItem
    var home: String = NSHomeDirectory()
    var onExclusionsChanged: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("Scanning") {
                Picker("Preselect projects idle for", selection: $preferences.staleAfterDays) {
                    ForEach(Preferences.idleChoices, id: \.self) { Text("\($0) days").tag($0) }
                }
                .pickerStyle(.menu)
                .fixedSize()
                Text("DevSweep scans your home folder for build folders next to a project file (node_modules next to package.json, bin and obj next to a .csproj, …) and checks the caches of common developer tools. ~/Library, hidden folders and app bundles are skipped.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            section("Excluded folders") {
                VStack(alignment: .leading, spacing: 0) {
                    if preferences.excludedPaths.isEmpty {
                        Text("Nothing excluded. Right-click an item in the menu and choose Exclude from Scans, or add a folder here.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(8)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(preferences.excludedPaths, id: \.self) { path in
                                    HStack {
                                        Image(systemName: "folder").foregroundStyle(.secondary)
                                        Text(PathDisplay.abbreviate(path, home: home))
                                            .font(.system(size: 12, design: .monospaced))
                                            .lineLimit(1).truncationMode(.middle)
                                        Spacer()
                                        Button {
                                            preferences.include(path)
                                            onExclusionsChanged()
                                        } label: {
                                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Scan this folder again")
                                    }
                                    .padding(.vertical, 3)
                                }
                            }
                            .padding(8)
                        }
                        .frame(height: 120)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.2)))
                Button("Add Folder…") { addFolder() }
            }

            section("Notifications") {
                Toggle("Remind me weekly when there is a lot to clean, and when the disk is almost full", isOn: $preferences.notificationsEnabled)
                    .toggleStyle(.checkbox)
                Picker("Remind when more than", selection: $preferences.notifyThresholdGB) {
                    ForEach(Preferences.thresholdChoices, id: \.self) { Text("\($0) GB").tag($0) }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .disabled(!preferences.notificationsEnabled)
                Text("DevSweep never deletes anything on its own.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            section("General") {
                Toggle("Open at Login", isOn: Binding(get: { login.isEnabled }, set: { login.setEnabled($0) }))
                    .toggleStyle(.checkbox)
                if let error = login.lastError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
                Text("Freed so far: \(Bytes.format(preferences.totalFreed))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        panel.prompt = "Exclude"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            preferences.exclude(url.standardizedFileURL.path)
        }
        onExclusionsChanged()
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }
}
