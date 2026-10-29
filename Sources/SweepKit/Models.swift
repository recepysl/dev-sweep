import Foundation

public enum ItemKind: String, Codable, CaseIterable, Sendable {
    case project
    case cache
    case docker
}

public struct Artifact: Codable, Hashable, Sendable {
    public var path: String
    public var ruleID: String
    public var size: Int64

    public init(path: String, ruleID: String, size: Int64) {
        self.path = path
        self.ruleID = ruleID
        self.size = size
    }

    public var name: String {
        (path as NSString).lastPathComponent
    }
}

public struct Item: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var kind: ItemKind
    public var title: String
    public var location: String
    public var ecosystem: String
    public var restore: String
    public var artifacts: [Artifact]
    public var dockerSize: Int64
    public var lastActivity: Date?

    public init(
        id: String, kind: ItemKind, title: String, location: String, ecosystem: String, restore: String,
        artifacts: [Artifact] = [], dockerSize: Int64 = 0, lastActivity: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.location = location
        self.ecosystem = ecosystem
        self.restore = restore
        self.artifacts = artifacts
        self.dockerSize = dockerSize
        self.lastActivity = lastActivity
    }

    public var size: Int64 {
        kind == .docker ? dockerSize : artifacts.reduce(0) { $0 + $1.size }
    }

    public var artifactNames: String {
        artifacts.map(\.name).sorted().joined(separator: ", ")
    }

    public func daysIdle(now: Date = Date()) -> Int? {
        guard let lastActivity else { return nil }
        return max(0, Int(now.timeIntervalSince(lastActivity) / 86_400))
    }

    public func isStale(olderThan days: Int, now: Date = Date()) -> Bool {
        guard kind == .project, let idle = daysIdle(now: now) else { return false }
        return idle >= days
    }
}

public struct DiskSpace: Codable, Hashable, Sendable {
    public var total: Int64
    public var available: Int64

    public init(total: Int64, available: Int64) {
        self.total = total
        self.available = available
    }

    public var used: Int64 {
        max(0, total - available)
    }

    public var usedFraction: Double {
        total > 0 ? Double(used) / Double(total) : 0
    }

    public var availableFraction: Double {
        total > 0 ? Double(available) / Double(total) : 1
    }

    public static func of(_ url: URL) -> DiskSpace? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
        guard let values = try? url.resourceValues(forKeys: keys), let total = values.volumeTotalCapacity else { return nil }
        let available = values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0)
        return DiskSpace(total: Int64(total), available: available)
    }
}

public enum DockerState: Codable, Hashable, Sendable {
    case notInstalled
    case notRunning(String)
    case available
}

public struct ScanResult: Codable, Hashable, Sendable {
    public var items: [Item]
    public var docker: DockerState
    public var disk: DiskSpace?
    public var scannedAt: Date
    public var duration: TimeInterval

    public init(items: [Item], docker: DockerState = .notInstalled, disk: DiskSpace? = nil, scannedAt: Date = Date(), duration: TimeInterval = 0) {
        self.items = items
        self.docker = docker
        self.disk = disk
        self.scannedAt = scannedAt
        self.duration = duration
    }

    public func items(_ kind: ItemKind) -> [Item] {
        items.filter { $0.kind == kind }
    }

    public var reclaimable: Int64 {
        items.reduce(0) { $0 + $1.size }
    }

    public func removing(_ ids: Set<String>) -> ScanResult {
        var copy = self
        copy.items.removeAll { ids.contains($0.id) }
        return copy
    }

    public func defaultSelection(staleAfter days: Int, now: Date = Date()) -> Set<String> {
        Set(items.filter { $0.isStale(olderThan: days, now: now) }.map(\.id))
    }
}

public enum Bytes {
    nonisolated(unsafe) public static var locale = Locale.current

    public static func format(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.formattingContext = .standalone
        formatter.zeroPadsFractionDigits = false
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        let text = formatter.string(fromByteCount: bytes)
        let separator = locale.decimalSeparator ?? "."
        let system = Locale.current.decimalSeparator ?? "."
        return separator == system ? text : text.replacingOccurrences(of: system, with: separator)
    }

    public static func compact(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        if gb >= 10 { return "\(Int(gb.rounded())) GB" }
        if gb >= 1 { return String(format: "%.1f GB", locale: locale, gb) }
        return "\(Int((Double(bytes) / 1_000_000).rounded())) MB"
    }
}

public enum PathDisplay {
    public static func abbreviate(_ path: String, home: String = NSHomeDirectory()) -> String {
        if path == home { return "~" }
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}
