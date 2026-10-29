import AppKit
import SwiftUI
import SweepKit

@MainActor
enum ScreenshotMode {
    static func run(outputPath: String) -> Never {
        NSApplication.shared.setActivationPolicy(.prohibited)
        Bytes.locale = Locale(identifier: "en_US")
        let output = URL(fileURLWithPath: outputPath, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            for theme in Theme.allCases {
                try write(HeroScene(model: DemoData.busy(), theme: theme), to: output, name: "hero", theme: theme)
                try write(StatesScene(theme: theme), to: output, name: "states", theme: theme)
                try write(SettingsScene(theme: theme), to: output, name: "settings", theme: theme)
                try write(MenuBarStripScene(theme: theme), to: output, name: "menubar", theme: theme)
            }
        } catch {
            FileHandle.standardError.write("✗ screenshot rendering failed: \(error)\n".data(using: .utf8)!)
            exit(1)
        }
        print("✓ Rendered screenshots to \(output.path)")
        exit(0)
    }

    private static func write<V: View>(_ view: V, to directory: URL, name: String, theme: Theme) throws {
        let rep = snapshot(view, appearance: theme.appearance)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: directory.appendingPathComponent("\(name)-\(theme.rawValue).png"))
    }

    private static func snapshot<V: View>(_ view: V, appearance: NSAppearance, scale: CGFloat = 2) -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view)
        host.appearance = appearance
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        host.display()

        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }
}

enum Theme: String, CaseIterable {
    case light
    case dark

    var appearance: NSAppearance {
        NSAppearance(named: self == .light ? .aqua : .darkAqua)!
    }

    var backdrop: LinearGradient {
        switch self {
        case .light:
            return LinearGradient(
                colors: [Color(red: 0.82, green: 0.95, blue: 0.93), Color(red: 0.88, green: 0.91, blue: 0.99)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .dark:
            return LinearGradient(
                colors: [Color(red: 0.03, green: 0.14, blue: 0.16), Color(red: 0.08, green: 0.10, blue: 0.26)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    var menuBarFill: Color {
        self == .light ? Color.white.opacity(0.55) : Color.black.opacity(0.35)
    }
}

@MainActor
enum DemoData {
    static let now = Date()
    static let home = "/Users/margaret"
    static let gb: Int64 = 1_000_000_000
    static let mb: Int64 = 1_000_000

    static func project(_ path: String, _ artifacts: [(String, String, Int64)], ecosystem: String, restore: String, idle days: Double) -> Item {
        let full = home + "/" + path
        return Item(
            id: "project:" + full,
            kind: .project,
            title: (path as NSString).lastPathComponent,
            location: "~/" + path,
            ecosystem: ecosystem,
            restore: restore,
            artifacts: artifacts.map { Artifact(path: full + "/" + $0.0, ruleID: $0.1, size: $0.2) },
            lastActivity: now.addingTimeInterval(-days * 86_400)
        )
    }

    static func cache(_ id: String, size: Int64) -> Item {
        let rule = Rules.cache(id: id)!
        return Item(
            id: "cache:" + id,
            kind: .cache,
            title: rule.name,
            location: "~/" + rule.path,
            ecosystem: rule.ecosystem,
            restore: rule.restore,
            artifacts: [Artifact(path: home + "/" + rule.path, ruleID: id, size: size)]
        )
    }

    static func docker(_ target: DockerTarget, size: Int64, count: Int) -> Item {
        Item(id: target.id, kind: .docker, title: target.title, location: "\(count) entries", ecosystem: "Docker", restore: target.restore, dockerSize: size)
    }

    static let disk = DiskSpace(total: 494 * gb, available: 38 * gb)

    static func busyResult() -> ScanResult {
        let items = [
            project("Projects/inventory-service", [("target", "cargo", 2_140 * mb)], ecosystem: "Rust", restore: "cargo build", idle: 121),
            project("Projects/storefront", [(".next", "node-build", 310 * mb), ("node_modules", "node", 1_120 * mb)], ecosystem: "Node.js", restore: "npm install", idle: 94),
            project("Projects/checkout-api", [("bin", "dotnet", 540 * mb), ("obj", "dotnet", 286 * mb)], ecosystem: ".NET", restore: "dotnet restore && dotnet build", idle: 3),
            project("Projects/mobile-app", [("Pods", "cocoapods", 642 * mb)], ecosystem: "CocoaPods", restore: "pod install", idle: 41),
            project("Projects/analytics", [(".venv", "python-venv", 458 * mb)], ecosystem: "Python", restore: "recreate the virtual environment and reinstall", idle: 65),
            project("Projects/design-system", [("node_modules", "node", 384 * mb)], ecosystem: "Node.js", restore: "npm install", idle: 0),
            cache("yarn", size: 6_410 * mb),
            cache("nuget", size: 5_230 * mb),
            cache("npm", size: 3_310 * mb),
            cache("xcode-derived-data", size: 2_780 * mb),
            docker(.images, size: 4_620 * mb, count: 7),
            docker(.buildCache, size: 1_510 * mb, count: 42),
        ]
        return ScanResult(items: items, docker: .available, disk: disk, scannedAt: now.addingTimeInterval(-7 * 60), duration: 19)
    }

    static func preferences() -> Preferences {
        let preferences = Preferences(defaults: UserDefaults(suiteName: "preview-\(UUID().uuidString)")!)
        preferences.totalFreed = 64_300 * mb
        return preferences
    }

    static func busy() -> SweepModel {
        let result = busyResult()
        let selection = result.defaultSelection(staleAfter: 30).union(["cache:yarn", "docker:images"])
        return SweepModel(preview: result, selection: selection, preferences: preferences(), collapsed: [])
    }

    static func scanning() -> SweepModel {
        SweepModel(preview: nil, progress: ScanProgress(path: home + "/Projects/storefront/src", folders: 48_213, found: 37), preferences: preferences(), home: home)
    }

    static func clean() -> SweepModel {
        let result = ScanResult(
            items: [project("Projects/design-system", [("node_modules", "node", 384 * mb)], ecosystem: "Node.js", restore: "npm install", idle: 0)],
            docker: .notRunning("Docker isn't running."),
            disk: DiskSpace(total: 494 * gb, available: 211 * gb),
            scannedAt: now.addingTimeInterval(-2 * 60),
            duration: 17
        )
        return SweepModel(preview: result, selection: [], preferences: preferences())
    }
}

struct DropdownPanel: View {
    let model: SweepModel

    var body: some View {
        MenuBarView(model: model)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.28), radius: 24, y: 12)
    }
}

struct FakeMenuBar: View {
    let model: SweepModel
    let theme: Theme

    var body: some View {
        HStack(spacing: 18) {
            Spacer()
            MenuBarLabel(model: model)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.12)))
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Image(systemName: "magnifyingglass")
            Text("Wed 9:41")
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.primary)
        .padding(.horizontal, 20)
        .frame(height: 30)
        .background(theme.menuBarFill)
    }
}

struct AppIconView: View {
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
            .fill(LinearGradient(
                colors: [Color(red: 0.16, green: 0.78, blue: 0.70), Color(red: 0.05, green: 0.28, blue: 0.45)],
                startPoint: .top, endPoint: .bottom
            ))
            .overlay(
                Image(systemName: "bubbles.and.sparkles.fill")
                    .font(.system(size: size * 0.50, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
    }
}

struct HeroScene: View {
    let model: SweepModel
    let theme: Theme

    var body: some View {
        ZStack(alignment: .top) {
            theme.backdrop
            VStack(spacing: 0) {
                FakeMenuBar(model: model, theme: theme)
                HStack(alignment: .top) {
                    tagline
                        .padding(.leading, 64)
                        .padding(.top, 120)
                    Spacer()
                    DropdownPanel(model: model)
                        .padding(.trailing, 110)
                }
                .padding(.top, 8)
                Spacer(minLength: 0)
            }
        }
        .frame(width: 1080, height: 820)
    }

    private var tagline: some View {
        VStack(alignment: .leading, spacing: 18) {
            AppIconView(size: 88)
            Text("DevSweep")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text("Find the gigabytes your\nbuilds and package managers\nleft behind — and get\nthem back in one click.")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                pill("Native SwiftUI")
                pill("Any language")
                pill("macOS 14+")
            }
            .padding(.top, 6)
        }
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(theme.menuBarFill))
    }
}

struct StatesScene: View {
    let theme: Theme

    var body: some View {
        ZStack {
            theme.backdrop
            HStack(alignment: .top, spacing: 36) {
                caption("First scan", DemoData.scanning())
                caption("Almost nothing left", DemoData.clean())
            }
            .padding(48)
        }
        .fixedSize()
    }

    private func caption(_ title: String, _ model: SweepModel) -> some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
            DropdownPanel(model: model)
        }
    }
}

struct SettingsScene: View {
    let theme: Theme

    var body: some View {
        let preferences = DemoData.preferences()
        preferences.excludedPaths = [DemoData.home + "/Projects/client-archive", DemoData.home + "/Projects/storefront/e2e/fixtures"]
        return ZStack {
            theme.backdrop
            SettingsView(preferences: preferences, login: .shared, home: DemoData.home)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
                .padding(48)
        }
        .fixedSize()
    }
}

struct MenuBarStripScene: View {
    let theme: Theme

    var body: some View {
        ZStack {
            theme.backdrop
            VStack(alignment: .leading, spacing: 10) {
                strip("Little to clean", SweepModel(preview: ScanResult(items: [DemoData.cache("npm", size: 420 * DemoData.mb)], disk: DiskSpace(total: 494 * DemoData.gb, available: 211 * DemoData.gb)), preferences: DemoData.preferences()))
                strip("More than 10 GB to clean", DemoData.busy())
                strip("Disk almost full", SweepModel(preview: ScanResult(items: DemoData.busyResult().items, disk: DiskSpace(total: 494 * DemoData.gb, available: 18 * DemoData.gb)), preferences: DemoData.preferences()))
            }
            .padding(24)
        }
        .fixedSize()
    }

    private func strip(_ title: String, _ model: SweepModel) -> some View {
        HStack(spacing: 14) {
            MenuBarLabel(model: model)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.10)))
                .frame(width: 110, alignment: .leading)
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}
