import Foundation

public struct DockerError: Error, Hashable, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }
}

public enum DockerTarget: String, CaseIterable, Sendable {
    case images = "Images"
    case containers = "Containers"
    case buildCache = "Build Cache"

    public var id: String {
        switch self {
        case .images: return "docker:images"
        case .containers: return "docker:containers"
        case .buildCache: return "docker:build-cache"
        }
    }

    public var title: String {
        switch self {
        case .images: return "Unused images"
        case .containers: return "Stopped containers"
        case .buildCache: return "Build cache"
        }
    }

    public var restore: String {
        switch self {
        case .images: return "pulled or built again when needed"
        case .containers: return "recreated by docker run or compose up"
        case .buildCache: return "rebuilt by the next docker build"
        }
    }

    public var pruneArguments: [String] {
        switch self {
        case .images: return ["image", "prune", "--all", "--force"]
        case .containers: return ["container", "prune", "--force"]
        case .buildCache: return ["builder", "prune", "--all", "--force"]
        }
    }

    public init?(itemID: String) {
        guard let target = DockerTarget.allCases.first(where: { $0.id == itemID }) else { return nil }
        self = target
    }
}

public struct DockerUsage: Hashable, Sendable {
    public var target: DockerTarget
    public var reclaimable: Int64
    public var count: Int
}

public struct DockerCLI: Hashable, Sendable {
    public let executable: String

    public init(executable: String) {
        self.executable = executable
    }

    public static func locate(home: String = NSHomeDirectory(), environment: [String: String] = ProcessInfo.processInfo.environment) -> DockerCLI? {
        let fromPath = (environment["PATH"] ?? "").split(separator: ":").map { "\($0)/docker" }
        let candidates = fromPath + [
            "/opt/homebrew/bin/docker",
            "/usr/local/bin/docker",
            home + "/.docker/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker",
            home + "/.orbstack/bin/docker",
            home + "/.rd/bin/docker",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map(DockerCLI.init)
    }

    public func reclaimable(timeout: TimeInterval = 20) -> Result<[Item], DockerError> {
        switch run(["system", "df", "--format", "{{json .}}"], timeout: timeout) {
        case .failure(let error):
            return .failure(error)
        case .success(let output):
            let items = DockerCLI.parse(output)
                .filter { $0.reclaimable > 0 }
                .map { usage in
                    Item(
                        id: usage.target.id,
                        kind: .docker,
                        title: usage.target.title,
                        location: usage.count == 1 ? "1 entry" : "\(usage.count) entries",
                        ecosystem: "Docker",
                        restore: usage.target.restore,
                        dockerSize: usage.reclaimable
                    )
                }
            return .success(items)
        }
    }

    public func prune(_ target: DockerTarget, timeout: TimeInterval = 600) -> DockerError? {
        if case .failure(let error) = run(target.pruneArguments, timeout: timeout) { return error }
        return nil
    }

    public static func parse(_ output: String) -> [DockerUsage] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            guard let data = line.data(using: .utf8),
                  let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = row["Type"] as? String,
                  let target = DockerTarget(rawValue: type) else { return nil }
            let reclaimable = (row["Reclaimable"] as? String).flatMap(parseSize) ?? 0
            let total = Int((row["TotalCount"] as? String) ?? "") ?? 0
            let active = Int((row["Active"] as? String) ?? "") ?? 0
            let count = target == .buildCache ? total : max(0, total - active)
            return DockerUsage(target: target, reclaimable: reclaimable, count: count)
        }
    }

    public static func parseSize(_ text: String) -> Int64? {
        let token = text.split(separator: " ").first.map(String.init) ?? ""
        let number = token.prefix { $0.isNumber || $0 == "." }
        let unit = token.dropFirst(number.count).uppercased()
        guard let value = Double(number) else { return nil }
        let multipliers: [String: Double] = [
            "B": 1, "KB": 1e3, "MB": 1e6, "GB": 1e9, "TB": 1e12,
            "KIB": 1_024, "MIB": 1_048_576, "GIB": 1_073_741_824, "TIB": 1_099_511_627_776,
        ]
        guard let multiplier = multipliers[unit] else { return nil }
        return Int64(value * multiplier)
    }

    func run(_ arguments: [String], timeout: TimeInterval) -> Result<String, DockerError> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        let directory = (executable as NSString).deletingLastPathComponent
        environment["PATH"] = [directory, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", environment["PATH"] ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: ":")
        process.environment = environment
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = FileHandle.nullDevice

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            return .failure(DockerError("Couldn't run docker: \(error.localizedDescription)"))
        }

        var stdout = Data()
        var stderr = Data()
        let reading = DispatchGroup()
        DispatchQueue.global().async(group: reading) { stdout = output.fileHandleForReading.readDataToEndOfFile() }
        DispatchQueue.global().async(group: reading) { stderr = errors.fileHandleForReading.readDataToEndOfFile() }

        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = reading.wait(timeout: .now() + 2)
            return .failure(DockerError("Docker didn't answer within \(Int(timeout)) seconds."))
        }
        reading.wait()

        guard process.terminationStatus == 0 else {
            let message = String(data: stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if message.contains("Cannot connect to the Docker daemon") || message.contains("Is the docker daemon running") || message.contains("error during connect") {
                return .failure(DockerError("Docker isn't running."))
            }
            return .failure(DockerError(message.isEmpty ? "docker exited with status \(process.terminationStatus)." : message))
        }
        return .success(String(data: stdout, encoding: .utf8) ?? "")
    }
}
