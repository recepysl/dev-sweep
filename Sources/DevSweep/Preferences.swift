import Foundation

@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    static let idleChoices = [7, 14, 30, 60, 90]
    static let thresholdChoices = [5, 10, 20, 50]

    @Published var excludedPaths: [String] {
        didSet { defaults.set(excludedPaths, forKey: Keys.excluded) }
    }
    @Published var staleAfterDays: Int {
        didSet { defaults.set(staleAfterDays, forKey: Keys.staleAfter) }
    }
    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Keys.notifications) }
    }
    @Published var notifyThresholdGB: Int {
        didSet { defaults.set(notifyThresholdGB, forKey: Keys.threshold) }
    }
    @Published var totalFreed: Int64 {
        didSet { defaults.set(totalFreed, forKey: Keys.freed) }
    }

    var lastReminder: Date? {
        get { defaults.object(forKey: Keys.lastReminder) as? Date }
        set { defaults.set(newValue, forKey: Keys.lastReminder) }
    }

    var lastDiskWarning: Date? {
        get { defaults.object(forKey: Keys.lastDiskWarning) as? Date }
        set { defaults.set(newValue, forKey: Keys.lastDiskWarning) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let excluded = "excludedPaths"
        static let staleAfter = "staleAfterDays"
        static let notifications = "notificationsEnabled"
        static let threshold = "notifyThresholdGB"
        static let freed = "totalFreedBytes"
        static let lastReminder = "lastReminder"
        static let lastDiskWarning = "lastDiskWarning"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        excludedPaths = defaults.stringArray(forKey: Keys.excluded) ?? []
        let staleAfter = defaults.integer(forKey: Keys.staleAfter)
        staleAfterDays = Self.idleChoices.contains(staleAfter) ? staleAfter : 30
        notificationsEnabled = defaults.object(forKey: Keys.notifications) as? Bool ?? true
        let threshold = defaults.integer(forKey: Keys.threshold)
        notifyThresholdGB = Self.thresholdChoices.contains(threshold) ? threshold : 10
        totalFreed = (defaults.object(forKey: Keys.freed) as? NSNumber)?.int64Value ?? 0
    }

    nonisolated static func storedExcludedPaths() -> [String] {
        UserDefaults.standard.stringArray(forKey: Keys.excluded) ?? []
    }

    func exclude(_ path: String) {
        guard !excludedPaths.contains(path) else { return }
        excludedPaths.append(path)
        excludedPaths.sort()
    }

    func include(_ path: String) {
        excludedPaths.removeAll { $0 == path }
    }
}
