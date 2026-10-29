import Foundation

public enum SelfCheck {
    public static func run() -> [String] {
        var failures: [String] = []

        func expect(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
            if !condition() { failures.append("line \(line): \(message)") }
        }

        checkRules(expect)
        checkDocker(expect)
        checkFormatting(expect)

        do {
            try checkScanAndClean(expect)
        } catch {
            failures.append("fixture: \(error)")
        }
        return failures
    }

    private typealias Expect = (@autoclosure () -> Bool, String, Int) -> Void

    private static func checkRules(_ expect: Expect) {
        let dotnet = Rules.project(id: "dotnet")!
        expect(dotnet.isMarker("Shop.Api.csproj"), "*.csproj matches a project file", #line)
        expect(!dotnet.isMarker("csproj"), "*.csproj needs the extension", #line)
        expect(Rules.project(id: "node")!.isMarker("package.json"), "package.json marks Node", #line)
        expect(!Rules.project(id: "node")!.isMarker("package-lock.json"), "package-lock.json alone isn't a marker", #line)
        expect(Rules.projectRules(for: "target").map(\.id) == ["cargo", "maven"], "target is Cargo or Maven", #line)
        expect(Set(Rules.caches.map(\.id)).count == Rules.caches.count, "cache ids are unique", #line)
        expect(Set(Rules.projects.map(\.id)).count == Rules.projects.count, "project rule ids are unique", #line)
        expect(Rules.caches.allSatisfy { !$0.path.hasPrefix("/") && !$0.path.contains("..") }, "cache paths are relative to home", #line)
        expect(!Rules.artifactFolders.contains("dist"), "dist is never touched", #line)
        expect(!Rules.caches.contains { $0.path.contains("Archives") }, "Xcode archives are never touched", #line)
        expect(Scanner.normalize("~/work/", home: "/Users/me") == "/Users/me/work", "~ and trailing slash are normalized", #line)
    }

    private static func checkDocker(_ expect: Expect) {
        expect(DockerCLI.parseSize("1.2GB (50%)") == 1_200_000_000, "parses GB with percentage", #line)
        expect(DockerCLI.parseSize("512.5kB") == 512_500, "parses kB", #line)
        expect(DockerCLI.parseSize("0B") == 0, "parses 0B", #line)
        expect(DockerCLI.parseSize("2GiB") == 2_147_483_648, "parses GiB", #line)
        expect(DockerCLI.parseSize("lots") == nil, "rejects garbage", #line)

        let output = """
        {"Active":"2","Reclaimable":"3.1GB (64%)","Size":"4.8GB","TotalCount":"7","Type":"Images"}
        {"Active":"1","Reclaimable":"12MB (40%)","Size":"30MB","TotalCount":"4","Type":"Containers"}
        {"Active":"1","Reclaimable":"0B","Size":"2GB","TotalCount":"3","Type":"Local Volumes"}
        {"Active":"0","Reclaimable":"1.5GB","Size":"1.5GB","TotalCount":"42","Type":"Build Cache"}
        """
        let usage = DockerCLI.parse(output)
        expect(usage.map(\.target) == [.images, .containers, .buildCache], "volumes are ignored", #line)
        expect(usage.first?.reclaimable == 3_100_000_000, "image reclaimable size", #line)
        expect(usage.first?.count == 5, "unused image count is total minus active", #line)
        expect(usage.last?.count == 42, "build cache count is the total", #line)
        expect(DockerTarget(itemID: "docker:images") == .images, "item id round-trips", #line)
        expect(!DockerTarget.allCases.flatMap(\.pruneArguments).contains("volume"), "volumes are never pruned", #line)
    }

    private static func checkFormatting(_ expect: Expect) {
        let saved = Bytes.locale
        Bytes.locale = Locale(identifier: "en_US")
        defer { Bytes.locale = saved }
        expect(Bytes.compact(16_400_000_000) == "16 GB", "compact rounds above 10 GB", #line)
        expect(Bytes.compact(1_250_000_000) == "1.3 GB" || Bytes.compact(1_250_000_000) == "1.2 GB", "compact keeps one decimal", #line)
        expect(Bytes.format(32_300_000_000) == "32.3 GB", "format uses the chosen locale: \(Bytes.format(32_300_000_000))", #line)
        expect(Bytes.compact(420_000_000) == "420 MB", "compact uses MB below 1 GB", #line)
        expect(PathDisplay.abbreviate("/Users/me/work/app", home: "/Users/me") == "~/work/app", "abbreviates home", #line)
        expect(PathDisplay.abbreviate("/Users/meow/app", home: "/Users/me") == "/Users/meow/app", "doesn't abbreviate a sibling user", #line)
    }

    private static func checkScanAndClean(_ expect: Expect) throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("devsweep-selfcheck-\(UUID().uuidString)").resolvingSymlinksInPath()
        let home = base.appendingPathComponent("home").path
        defer { try? fm.removeItem(at: base) }

        func file(_ relative: String, bytes: Int = 64, age days: Double? = nil) throws {
            let url = URL(fileURLWithPath: home + "/" + relative)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 7, count: bytes).write(to: url)
            if let days {
                try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-days * 86_400)], ofItemAtPath: url.path)
            }
        }

        try file("work/shop/package.json", age: 90)
        try file("work/shop/src/index.ts", age: 90)
        try file("work/shop/node_modules/left-pad/index.js", bytes: 40_000, age: 90)
        try file("work/shop/node_modules/left-pad/package.json", age: 90)
        try file("work/shop/node_modules/left-pad/node_modules/inner/index.js", age: 90)
        try file("work/shop/.next/cache/chunk.js", bytes: 20_000)
        try file("work/api/Shop.Api.csproj", age: 2)
        try file("work/api/Program.cs", age: 2)
        try file("work/api/bin/Debug/Shop.Api.dll", bytes: 30_000)
        try file("work/api/obj/project.assets.json", bytes: 10_000)
        try file("work/orphan/node_modules/lib/index.js", bytes: 10_000)
        try file("work/orphan/node_modules/lib/package.json")
        try file("work/orphan/node_modules/lib/node_modules/x/index.js", bytes: 10_000)
        try file("work/web/package.json")
        try file("work/web/dist/app.js", bytes: 10_000)
        try file("work/skipme/package.json")
        try file("work/skipme/node_modules/a.js", bytes: 10_000)
        try file(".vscode/extensions/ext/package.json")
        try file(".vscode/extensions/ext/node_modules/dep/index.js", bytes: 10_000)
        try file("Library/Caches/Yarn/v6/pkg.tgz", bytes: 50_000)
        try file("Library/Application Support/tool/package.json")
        try file("Library/Application Support/tool/node_modules/x.js", bytes: 10_000)
        try file(".npm/_cacache/content/blob", bytes: 25_000)
        try file("Games/Big.app/Contents/package.json")
        try file("Games/Big.app/Contents/node_modules/x.js", bytes: 10_000)
        try fm.createSymbolicLink(atPath: home + "/work/shop-link", withDestinationPath: home + "/work/shop")
        try fm.createSymbolicLink(atPath: home + "/work/web/node_modules", withDestinationPath: home + "/work/shop/node_modules")
        try fm.linkItem(atPath: home + "/work/shop/node_modules/left-pad/index.js", toPath: home + "/hardlink-index.js")
        try file("work/shop/node_modules/solo.js", bytes: 8_000, age: 90)

        let scanner = Scanner(home: home, excluded: ["~/work/skipme"], docker: nil)
        let result = scanner.scan()
        let ids = Set(result.items.map(\.id))

        expect(ids.contains("project:\(home)/work/shop"), "finds node_modules next to package.json", #line)
        expect(ids.contains("project:\(home)/work/api"), "finds bin/obj next to a csproj", #line)
        expect(ids.contains("cache:yarn"), "finds the Yarn cache", #line)
        expect(ids.contains("cache:npm"), "finds the npm cache", #line)
        expect(!ids.contains { $0.contains("orphan") }, "ignores node_modules without package.json and doesn't descend into it", #line)
        expect(!ids.contains { $0.contains("skipme") }, "honors excluded folders", #line)
        expect(!ids.contains { $0.contains(".vscode") }, "skips hidden folders", #line)
        expect(!ids.contains { $0.contains("Application Support") }, "skips ~/Library outside known caches", #line)
        expect(!ids.contains { $0.contains(".app") }, "skips app bundles", #line)
        expect(!ids.contains { $0.contains("shop-link") }, "doesn't follow symbolic links", #line)
        expect(!ids.contains("project:\(home)/work/web"), "doesn't treat a symlinked node_modules or dist as an artifact", #line)
        expect(result.items.filter { $0.kind == .project }.count == 2, "exactly two projects", #line)

        let shop = result.items.first { $0.id == "project:\(home)/work/shop" }
        expect(shop?.artifacts.map(\.name) == [".next", "node_modules"], "groups artifacts per project", #line)
        let nodeModules = shop?.artifacts.first { $0.name == "node_modules" }
        expect((nodeModules?.size ?? 0) >= 8_000 && (nodeModules?.size ?? 0) < 40_000, "hard-linked files aren't counted as reclaimable", #line)
        expect((shop?.daysIdle() ?? 0) >= 89, "a freshly written .next doesn't count as activity", #line)

        let api = result.items.first { $0.id == "project:\(home)/work/api" }
        expect(api?.artifacts.map(\.name) == ["bin", "obj"], "bin and obj belong to the .NET project", #line)
        expect(api?.daysIdle().map { $0 >= 1 && $0 <= 3 } == true, "last activity comes from source files", #line)

        try file("work/old/package.json", age: 120)
        try file("work/old/index.js", age: 120)
        try file("work/old/node_modules/x.js", bytes: 5_000, age: 120)
        let old = scanner.scan().items.first { $0.id == "project:\(home)/work/old" }
        expect(old?.isStale(olderThan: 30) == true, "a project untouched for 120 days is stale", #line)
        expect(old?.isStale(olderThan: 200) == false, "but not older than 200 days", #line)

        let cleaner = Cleaner(scanner: scanner)

        var outside = Item(id: "project:/tmp/x", kind: .project, title: "x", location: "/tmp/x", ecosystem: "", restore: "")
        outside.artifacts = [Artifact(path: base.path + "/node_modules", ruleID: "node", size: 1)]
        expect(cleaner.refusal(for: outside.artifacts[0], in: outside) != nil, "refuses paths outside home", #line)

        var traversal = outside
        traversal.artifacts = [Artifact(path: home + "/work/shop/../api/bin", ruleID: "dotnet", size: 1)]
        expect(cleaner.refusal(for: traversal.artifacts[0], in: traversal) != nil, "refuses non-canonical paths", #line)

        var link = outside
        link.artifacts = [Artifact(path: home + "/work/web/node_modules", ruleID: "node", size: 1)]
        expect(cleaner.refusal(for: link.artifacts[0], in: link) != nil, "refuses symbolic links", #line)

        var wrongRule = outside
        wrongRule.artifacts = [Artifact(path: home + "/work/api/bin", ruleID: "node", size: 1)]
        expect(cleaner.refusal(for: wrongRule.artifacts[0], in: wrongRule) != nil, "refuses a folder that doesn't match its rule", #line)

        var fakeCache = outside
        fakeCache.kind = .cache
        fakeCache.artifacts = [Artifact(path: home + "/work/api", ruleID: "yarn", size: 1)]
        expect(cleaner.refusal(for: fakeCache.artifacts[0], in: fakeCache) != nil, "refuses a cache at an unexpected path", #line)

        if let api {
            try fm.removeItem(atPath: home + "/work/api/Shop.Api.csproj")
            let report = cleaner.clean([api])
            expect(report.cleanedIDs.isEmpty && report.failures.count == 2, "refuses when the marker file is gone", #line)
            expect(fm.fileExists(atPath: home + "/work/api/bin/Debug/Shop.Api.dll"), "nothing was deleted without a marker", #line)
        }

        if let shop {
            let report = cleaner.clean([shop])
            expect(report.cleanedIDs == [shop.id], "cleans the shop project", #line)
            expect(report.failures.isEmpty, "no failures cleaning shop: \(report.failures.map(\.reason))", #line)
            expect(!fm.fileExists(atPath: home + "/work/shop/node_modules"), "node_modules is gone", #line)
            expect(fm.fileExists(atPath: home + "/work/shop/package.json"), "package.json stays", #line)
            expect(fm.fileExists(atPath: home + "/work/shop/src/index.ts"), "sources stay", #line)
            expect(fm.fileExists(atPath: home + "/hardlink-index.js"), "the other hard link survives", #line)
            expect(fm.fileExists(atPath: home + "/work/shop-link"), "the symlink to the project stays", #line)
            expect(report.freed == shop.size, "freed equals the scanned size", #line)
        }

        if let yarn = result.items.first(where: { $0.id == "cache:yarn" }) {
            let report = cleaner.clean([yarn])
            expect(report.cleanedIDs == [yarn.id], "cleans a cache", #line)
            expect(!fm.fileExists(atPath: home + "/Library/Caches/Yarn"), "the Yarn cache is gone", #line)
            expect(fm.fileExists(atPath: home + "/Library/Caches"), "its parent stays", #line)
        }

        let selection = ScanResult(items: [old].compactMap { $0 } + result.items.filter { $0.kind == .cache }).defaultSelection(staleAfter: 30)
        expect(selection == Set([old?.id].compactMap { $0 }), "only stale projects are preselected", #line)
    }
}
