import Foundation

public final class Cancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

public struct ScanProgress: Sendable {
    public var path: String
    public var folders: Int
    public var found: Int

    public init(path: String, folders: Int, found: Int) {
        self.path = path
        self.folders = folders
        self.found = found
    }
}

public struct Scanner: Sendable {
    public let home: String
    public let excluded: Set<String>
    public let docker: DockerCLI?

    public init(home: String = NSHomeDirectory(), excluded: [String] = [], docker: DockerCLI? = DockerCLI.locate()) {
        let root = URL(fileURLWithPath: home).standardizedFileURL.path
        self.home = root
        self.excluded = Set(excluded.map { Scanner.normalize($0, home: root) })
        self.docker = docker
    }

    public static func normalize(_ path: String, home: String) -> String {
        let expanded = path.hasPrefix("~/") ? home + path.dropFirst(1) : path
        var normalized = URL(fileURLWithPath: expanded).standardizedFileURL.path
        while normalized.count > 1 && normalized.hasSuffix("/") { normalized.removeLast() }
        return normalized
    }

    public func scan(cancellation: Cancellation = Cancellation(), progress: (@Sendable (ScanProgress) -> Void)? = nil) -> ScanResult {
        let started = Date()
        let dockerOutcome = Locked((items: [Item](), state: DockerState.notInstalled))
        let group = DispatchGroup()
        if let docker {
            DispatchQueue.global(qos: .utility).async(group: group) {
                switch docker.reclaimable() {
                case .success(let items):
                    dockerOutcome.withValue { $0 = (items, .available) }
                case .failure(let error):
                    dockerOutcome.withValue { $0 = ([], .notRunning(error.message)) }
                }
            }
        }

        let caches = scanCaches()
        let projects = scanProjects(cancellation: cancellation, progress: progress)
        group.wait()

        let (dockerItems, dockerState) = dockerOutcome.withValue { ($0.items, $0.state) }
        let items = (caches + projects + dockerItems).sorted { ($0.size, $0.id) > ($1.size, $1.id) }
        return ScanResult(
            items: items,
            docker: dockerState,
            disk: DiskSpace.of(URL(fileURLWithPath: home)),
            scannedAt: Date(),
            duration: Date().timeIntervalSince(started)
        )
    }

    public func scanCaches() -> [Item] {
        let rules = Rules.caches.filter { rule in
            let path = home + "/" + rule.path
            return !isExcluded(path) && FileTree.isRealDirectory(path)
        }
        let sizes = FileTree.allocatedSizes(of: rules.map { home + "/" + $0.path })
        return zip(rules, sizes).compactMap { rule, size in
            guard size > 0 else { return nil }
            let path = home + "/" + rule.path
            return Item(
                id: "cache:" + rule.id,
                kind: .cache,
                title: rule.name,
                location: PathDisplay.abbreviate(path, home: home),
                ecosystem: rule.ecosystem,
                restore: rule.restore,
                artifacts: [Artifact(path: path, ruleID: rule.id, size: size)],
                lastActivity: FileTree.modificationDate(path)
            )
        }
    }

    public func findArtifacts(cancellation: Cancellation = Cancellation(), progress: (@Sendable (ScanProgress) -> Void)? = nil) -> [(project: String, artifact: Artifact)] {
        let state = Locked((found: [(project: String, artifact: Artifact)](), folders: 0))
        let home = home
        let scanner = self

        FileTree.traverse([DirectoryWork(path: home)]) { work in
            if cancellation.isCancelled { return nil }
            guard let entries = FileTree.list(work.path) else { return [] }
            let fileNames = entries.filter { $0.type == .file || $0.type == .symlink }.map(\.name)
            var children: [DirectoryWork] = []
            var found: [(project: String, artifact: Artifact)] = []

            for entry in entries where entry.type == .directory {
                let name = entry.name
                let path = work.path + "/" + name
                let level = work.level + 1
                if scanner.isExcluded(path) { continue }
                if level == 1 && Rules.skippedTopLevel.contains(name) { continue }
                if Rules.skippedRelativePaths.contains(String(path.dropFirst(home.count + 1))) { continue }
                if Rules.packageExtensions.contains((name as NSString).pathExtension.lowercased()) { continue }
                if Rules.artifactFolders.contains(name),
                   let rule = Rules.projectRules(for: name).first(where: { rule in fileNames.contains(where: rule.isMarker) }) {
                    found.append((work.path, Artifact(path: path, ruleID: rule.id, size: 0)))
                    continue
                }
                if name.hasPrefix(".") || Rules.neverDescend.contains(name) { continue }
                children.append(DirectoryWork(path: path, level: level))
            }

            let snapshot = state.withValue { value -> ScanProgress? in
                value.found.append(contentsOf: found)
                value.folders += 1
                guard !found.isEmpty || value.folders % 500 == 0 else { return nil }
                return ScanProgress(path: work.path, folders: value.folders, found: value.found.count)
            }
            if let snapshot, let progress { progress(snapshot) }
            return children
        }
        return state.withValue { $0.found }.sorted { $0.artifact.path < $1.artifact.path }
    }

    public func scanProjects(cancellation: Cancellation = Cancellation(), progress: (@Sendable (ScanProgress) -> Void)? = nil) -> [Item] {
        let found = findArtifacts(cancellation: cancellation, progress: progress)
        guard !cancellation.isCancelled else { return [] }

        let sizes = FileTree.allocatedSizes(of: found.map(\.artifact.path))
        var byProject: [String: [Artifact]] = [:]
        for (index, entry) in found.enumerated() {
            var artifact = entry.artifact
            artifact.size = sizes[index]
            byProject[entry.project, default: []].append(artifact)
        }

        let projects = byProject.keys.sorted()
        let activity = Locked([Date?](repeating: nil, count: projects.count))
        DispatchQueue.concurrentPerform(iterations: projects.count) { index in
            let date = lastActivity(of: projects[index], artifacts: byProject[projects[index]] ?? [])
            activity.withValue { $0[index] = date }
        }
        let dates = activity.withValue { $0 }

        return projects.enumerated().compactMap { index, project in
            let artifacts = (byProject[project] ?? []).sorted { $0.name < $1.name }
            guard artifacts.contains(where: { $0.size > 0 }) else { return nil }
            let rules = artifacts.compactMap { Rules.project(id: $0.ruleID) }
            return Item(
                id: "project:" + project,
                kind: .project,
                title: (project as NSString).lastPathComponent,
                location: PathDisplay.abbreviate(project, home: home),
                ecosystem: unique(rules.map(\.ecosystem)).joined(separator: " · "),
                restore: unique(rules.map(\.restore)).joined(separator: "; "),
                artifacts: artifacts,
                lastActivity: dates[index]
            )
        }
    }

    public func lastActivity(of project: String, artifacts: [Artifact], maxDepth: Int = 6, maxEntries: Int = 20_000) -> Date? {
        let artifactPaths = Set(artifacts.map(\.path))
        var newest: Date?
        var seen = 0
        var stack = [(path: project, level: 0)]

        func consider(_ date: Date?) {
            guard let date else { return }
            if newest == nil || date > newest! { newest = date }
        }

        while let (directory, level) = stack.popLast(), seen < maxEntries {
            guard let entries = FileTree.list(directory) else { continue }
            for entry in entries {
                seen += 1
                switch entry.type {
                case .file where entry.name != ".DS_Store":
                    consider(entry.modified)
                case .directory where level < maxDepth:
                    let path = directory + "/" + entry.name
                    if artifactPaths.contains(path) || Rules.artifactFolders.contains(entry.name)
                        || entry.name.hasPrefix(".") || Rules.neverDescend.contains(entry.name) { continue }
                    stack.append((path, level + 1))
                default:
                    break
                }
            }
        }

        var directory = project
        while directory.hasPrefix(home) {
            let git = directory + "/.git"
            if FileManager.default.fileExists(atPath: git) {
                consider(FileTree.modificationDate(git + "/index"))
                consider(FileTree.modificationDate(git + "/logs/HEAD"))
                break
            }
            if directory == home { break }
            directory = (directory as NSString).deletingLastPathComponent
        }
        return newest
    }

    public func isExcluded(_ path: String) -> Bool {
        guard !excluded.isEmpty else { return false }
        if excluded.contains(path) { return true }
        return excluded.contains { path.hasPrefix($0 + "/") }
    }

    private func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }
}
