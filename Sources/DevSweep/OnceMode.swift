import Foundation
import SweepKit

enum OnceMode {
    static func run(arguments: [String]) -> Never {
        let home = value(after: "--home", in: arguments) ?? NSHomeDirectory()
        let excluded = arguments.contains("--home") ? [] : Preferences.storedExcludedPaths()
        let scanner = Scanner(home: home, excluded: excluded)
        let result = scanner.scan()

        if arguments.contains("--json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(result), let text = String(data: data, encoding: .utf8) {
                print(text)
            }
            exit(0)
        }

        if let disk = result.disk {
            print("\(Bytes.format(disk.available)) free of \(Bytes.format(disk.total)) · scanned \(PathDisplay.abbreviate(scanner.home)) in \(String(format: "%.1f", result.duration)) s")
        }
        print("Reclaimable: \(Bytes.format(result.reclaimable)) (dry run, nothing was deleted)")

        section("Projects", result.items(.project)) { item in
            let idle = item.daysIdle().map { "\($0)d idle" } ?? ""
            return "\(item.location)  [\(item.artifactNames)]  \(idle)"
        }
        section("Global caches", result.items(.cache)) { "\($0.title)  \($0.location)" }
        switch result.docker {
        case .notInstalled:
            print("\nDocker: not installed")
        case .notRunning(let message):
            print("\nDocker: \(message)")
        case .available:
            section("Docker", result.items(.docker)) { "\($0.title)  \($0.location)" }
        }
        exit(0)
    }

    private static func section(_ title: String, _ items: [Item], describe: (Item) -> String) {
        let total = items.reduce(Int64(0)) { $0 + $1.size }
        print("\n\(title) (\(items.count), \(Bytes.format(total)))")
        for item in items {
            print("  \(Bytes.format(item.size).padding(toLength: 10, withPad: " ", startingAt: 0)) \(describe(item))")
        }
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.index(after: index) < arguments.endIndex else { return nil }
        return arguments[arguments.index(after: index)]
    }
}
