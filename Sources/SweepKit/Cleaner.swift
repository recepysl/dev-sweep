import Foundation

public struct CleanFailure: Hashable, Sendable {
    public var itemID: String
    public var path: String
    public var reason: String
}

public struct CleanReport: Hashable, Sendable {
    public var freed: Int64 = 0
    public var cleanedIDs: Set<String> = []
    public var failures: [CleanFailure] = []

    public init() {}
}

public struct Cleaner: Sendable {
    public let home: String
    public let excluded: Set<String>
    public let docker: DockerCLI?

    public init(scanner: Scanner) {
        home = scanner.home
        excluded = scanner.excluded
        docker = scanner.docker
    }

    public func clean(_ items: [Item], progress: ((Int, Int) -> Void)? = nil) -> CleanReport {
        var report = CleanReport()
        for (index, item) in items.enumerated() {
            progress?(index, items.count)
            switch item.kind {
            case .docker:
                guard let target = DockerTarget(itemID: item.id) else {
                    report.failures.append(CleanFailure(itemID: item.id, path: item.title, reason: "Unknown Docker item."))
                    continue
                }
                guard let docker else {
                    report.failures.append(CleanFailure(itemID: item.id, path: item.title, reason: "Docker isn't installed."))
                    continue
                }
                if let error = docker.prune(target) {
                    report.failures.append(CleanFailure(itemID: item.id, path: item.title, reason: error.message))
                } else {
                    report.freed += item.size
                    report.cleanedIDs.insert(item.id)
                }
            case .project, .cache:
                var removedAll = true
                for artifact in item.artifacts {
                    if let reason = refusal(for: artifact, in: item) {
                        report.failures.append(CleanFailure(itemID: item.id, path: artifact.path, reason: reason))
                        removedAll = false
                        continue
                    }
                    do {
                        try FileManager.default.removeItem(atPath: artifact.path)
                        report.freed += artifact.size
                    } catch {
                        report.failures.append(CleanFailure(itemID: item.id, path: artifact.path, reason: error.localizedDescription))
                        removedAll = false
                    }
                }
                if removedAll { report.cleanedIDs.insert(item.id) }
            }
        }
        progress?(items.count, items.count)
        return report
    }

    public func refusal(for artifact: Artifact, in item: Item) -> String? {
        let path = artifact.path
        guard URL(fileURLWithPath: path).standardizedFileURL.path == path else {
            return "The path isn't in canonical form."
        }
        guard path.hasPrefix(home + "/"), path.count > home.count + 1 else {
            return "The path is outside the home folder."
        }
        guard FileTree.isRealDirectory(path) else {
            return "It is no longer a folder, or it is a symbolic link."
        }
        if excluded.contains(path) || excluded.contains(where: { path.hasPrefix($0 + "/") }) {
            return "The path is excluded in Settings."
        }

        switch item.kind {
        case .cache:
            guard let rule = Rules.cache(id: artifact.ruleID), path == home + "/" + rule.path else {
                return "The folder doesn't match a known cache location."
            }
        case .project:
            guard let rule = Rules.project(id: artifact.ruleID) else {
                return "Unknown rule \(artifact.ruleID)."
            }
            let name = (path as NSString).lastPathComponent
            let parent = (path as NSString).deletingLastPathComponent
            guard rule.matches(folder: name) else {
                return "\(name) isn't a \(rule.ecosystem) build folder."
            }
            let siblings = (try? FileManager.default.contentsOfDirectory(atPath: parent)) ?? []
            guard siblings.contains(where: rule.isMarker) else {
                return "No \(rule.markers.joined(separator: " / ")) next to it anymore."
            }
        case .docker:
            return "Docker items aren't folders."
        }
        return nil
    }
}
