import AppKit
import SweepKit

@MainActor
final class SweepModel: ObservableObject {
    static let shared = SweepModel()

    static let rescanAfter: TimeInterval = 24 * 3_600
    static let reminderEvery: TimeInterval = 7 * 86_400
    static let diskWarningEvery: TimeInterval = 86_400

    @Published private(set) var result: ScanResult?
    @Published var selection: Set<String> = []
    @Published private(set) var isScanning = false
    @Published private(set) var progress: ScanProgress?
    @Published private(set) var cleaning: (done: Int, total: Int)?
    @Published private(set) var message: String?
    @Published private(set) var disk: DiskSpace?
    @Published private(set) var collapsed: Set<ItemKind> = []

    let preferences: Preferences
    let home: String
    private let persistent: Bool
    private var cancellation: Cancellation?
    private var timer: Timer?

    private init() {
        preferences = .shared
        home = NSHomeDirectory()
        persistent = true
        result = Self.loadCachedResult()
        disk = DiskSpace.of(URL(fileURLWithPath: NSHomeDirectory())) ?? result?.disk
        if let result { selection = result.defaultSelection(staleAfter: preferences.staleAfterDays) }
    }

    init(preview result: ScanResult?, selection: Set<String>? = nil, progress: ScanProgress? = nil, preferences: Preferences, collapsed: Set<ItemKind> = [], home: String = NSHomeDirectory()) {
        self.preferences = preferences
        self.home = home
        persistent = false
        self.result = result
        self.disk = result?.disk
        self.progress = progress
        self.isScanning = progress != nil
        self.collapsed = collapsed
        self.selection = selection ?? result?.defaultSelection(staleAfter: preferences.staleAfterDays) ?? []
    }

    var items: [Item] {
        result?.items ?? []
    }

    func items(_ kind: ItemKind) -> [Item] {
        items.filter { $0.kind == kind }
    }

    var reclaimable: Int64 {
        result?.reclaimable ?? 0
    }

    var selectedItems: [Item] {
        items.filter { selection.contains($0.id) }
    }

    var selectedSize: Int64 {
        selectedItems.reduce(0) { $0 + $1.size }
    }

    var diskIsLow: Bool {
        (disk?.availableFraction ?? 1) < 0.10
    }

    var diskIsCritical: Bool {
        (disk?.availableFraction ?? 1) < 0.05
    }

    var needsAttention: Bool {
        diskIsLow || reclaimable >= Int64(preferences.notifyThresholdGB) * 1_000_000_000
    }

    func start() {
        if result == nil || Date().timeIntervalSince(result!.scannedAt) > Self.rescanAfter {
            scan(manual: false)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 3_600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.hourly() }
        }
    }

    private func hourly() {
        disk = DiskSpace.of(URL(fileURLWithPath: NSHomeDirectory())) ?? disk
        guard !isScanning, cleaning == nil else { return }
        if let result, Date().timeIntervalSince(result.scannedAt) < Self.rescanAfter { return }
        scan(manual: false)
    }

    func scan(manual: Bool = true) {
        guard persistent else { return }
        if isScanning { cancellation?.cancel() }
        let cancellation = Cancellation()
        self.cancellation = cancellation
        isScanning = true
        progress = nil
        message = nil

        let scanner = Scanner(excluded: preferences.excludedPaths)
        let throttle = Throttle(interval: 0.25)
        Task.detached(priority: .utility) { [self] in
            let result = scanner.scan(cancellation: cancellation) { progress in
                guard throttle.allow() else { return }
                Task { @MainActor in
                    guard self.cancellation === cancellation else { return }
                    self.progress = progress
                }
            }
            await MainActor.run {
                guard self.cancellation === cancellation, !cancellation.isCancelled else { return }
                self.finishScan(result, manual: manual)
            }
        }
    }

    func cancelScan() {
        cancellation?.cancel()
        cancellation = nil
        isScanning = false
        progress = nil
    }

    private func finishScan(_ result: ScanResult, manual: Bool) {
        self.result = result
        disk = result.disk ?? disk
        selection = result.defaultSelection(staleAfter: preferences.staleAfterDays)
        isScanning = false
        progress = nil
        cancellation = nil
        save()
        if !manual { remindIfNeeded() }
    }

    private func remindIfNeeded() {
        guard preferences.notificationsEnabled, let result else { return }
        let now = Date()

        if diskIsLow, let disk {
            if preferences.lastDiskWarning.map({ now.timeIntervalSince($0) > Self.diskWarningEvery }) ?? true {
                preferences.lastDiskWarning = now
                Notifier.shared.post(
                    title: "Your disk is almost full",
                    body: "\(Bytes.format(disk.available)) free. DevSweep found \(Bytes.format(result.reclaimable)) of caches and build folders you can delete."
                )
                return
            }
        }

        guard result.reclaimable >= Int64(preferences.notifyThresholdGB) * 1_000_000_000 else { return }
        guard let last = preferences.lastReminder else {
            preferences.lastReminder = now
            return
        }
        guard now.timeIntervalSince(last) > Self.reminderEvery else { return }
        preferences.lastReminder = now
        let projects = result.items(.project).count
        let stale = result.items(.project).filter { $0.isStale(olderThan: preferences.staleAfterDays, now: now) }.count
        Notifier.shared.post(
            title: "\(Bytes.compact(result.reclaimable)) can be cleaned",
            body: "\(projects) projects (\(stale) idle for \(preferences.staleAfterDays)+ days), \(result.items(.cache).count) caches. Open DevSweep to review."
        )
    }

    func isCollapsed(_ kind: ItemKind) -> Bool {
        collapsed.contains(kind)
    }

    func toggle(_ kind: ItemKind) {
        if collapsed.contains(kind) { collapsed.remove(kind) } else { collapsed.insert(kind) }
    }

    func isSelected(_ item: Item) -> Bool {
        selection.contains(item.id)
    }

    func setSelected(_ item: Item, _ selected: Bool) {
        if selected { selection.insert(item.id) } else { selection.remove(item.id) }
    }

    func allSelected(_ kind: ItemKind) -> Bool {
        let ids = items(kind).map(\.id)
        return !ids.isEmpty && ids.allSatisfy(selection.contains)
    }

    func setAllSelected(_ kind: ItemKind, _ selected: Bool) {
        let ids = Set(items(kind).map(\.id))
        if selected { selection.formUnion(ids) } else { selection.subtract(ids) }
    }

    func selectIdle() {
        selection = result?.defaultSelection(staleAfter: preferences.staleAfterDays) ?? []
    }

    func exclude(_ item: Item) {
        let path: String
        switch item.kind {
        case .project: path = String(item.id.dropFirst("project:".count))
        case .cache: path = item.artifacts.first?.path ?? ""
        case .docker: return
        }
        guard !path.isEmpty else { return }
        preferences.exclude(path)
        result = result?.removing([item.id])
        selection.remove(item.id)
        save()
    }

    func reveal(_ item: Item) {
        let urls = item.artifacts.map { URL(fileURLWithPath: $0.path) }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func copyPath(_ item: Item) {
        let text = item.kind == .project ? String(item.id.dropFirst("project:".count)) : item.artifacts.map(\.path).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func cleanSelected() {
        let items = selectedItems
        guard persistent, !items.isEmpty, cleaning == nil, !isScanning else { return }
        guard confirm(items) else { return }

        cleaning = (0, items.count)
        message = nil
        let cleaner = Cleaner(scanner: Scanner(excluded: preferences.excludedPaths))
        Task.detached(priority: .userInitiated) { [self] in
            let report = cleaner.clean(items) { done, total in
                Task { @MainActor in if self.cleaning != nil { self.cleaning = (done, total) } }
            }
            await MainActor.run { self.finishCleaning(report) }
        }
    }

    private func confirm(_ items: [Item]) -> Bool {
        let total = items.reduce(Int64(0)) { $0 + $1.size }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete \(Bytes.format(total))?"
        var lines = items.prefix(8).map { item -> String in
            let detail = item.kind == .project ? "\(item.title) · \(item.artifactNames)" : item.title
            return "• \(detail) — \(Bytes.format(item.size))"
        }
        if items.count > 8 { lines.append("…and \(items.count - 8) more") }
        alert.informativeText = lines.joined(separator: "\n")
            + "\n\nThese are regenerable build outputs and caches. They are deleted right away, not moved to the Trash, and come back the next time you build or install."
        let delete = alert.addButton(withTitle: "Delete")
        delete.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func finishCleaning(_ report: CleanReport) {
        cleaning = nil
        result = result?.removing(report.cleanedIDs)
        selection.subtract(report.cleanedIDs)
        preferences.totalFreed += report.freed
        disk = DiskSpace.of(URL(fileURLWithPath: NSHomeDirectory())) ?? disk
        save()

        if report.failures.isEmpty {
            message = "Freed \(Bytes.format(report.freed))."
        } else {
            message = "Freed \(Bytes.format(report.freed)). \(report.failures.count) couldn't be deleted."
            let alert = NSAlert()
            alert.messageText = "Some items couldn't be deleted"
            alert.informativeText = report.failures.prefix(8)
                .map { "• \(PathDisplay.abbreviate($0.path)): \($0.reason)" }
                .joined(separator: "\n")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    private static var cacheURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "DevSweep").appendingPathComponent("last-scan.json")
    }

    private static func loadCachedResult() -> ScanResult? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ScanResult.self, from: data)
    }

    private func save() {
        guard persistent, let result else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(result) else { return }
        try? FileManager.default.createDirectory(at: Self.cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Self.cacheURL, options: .atomic)
    }
}

final class Throttle: @unchecked Sendable {
    private let lock = NSLock()
    private let interval: TimeInterval
    private var last = Date.distantPast

    init(interval: TimeInterval) {
        self.interval = interval
    }

    func allow() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        guard now.timeIntervalSince(last) >= interval else { return false }
        last = now
        return true
    }
}
