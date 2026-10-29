import Foundation

public struct ProjectRule: Hashable, Sendable {
    public let id: String
    public let folders: [String]
    public let markers: [String]
    public let ecosystem: String
    public let restore: String

    public init(id: String, folders: [String], markers: [String], ecosystem: String, restore: String) {
        self.id = id
        self.folders = folders
        self.markers = markers
        self.ecosystem = ecosystem
        self.restore = restore
    }

    public func matches(folder: String) -> Bool {
        folders.contains(folder)
    }

    public func isMarker(_ fileName: String) -> Bool {
        markers.contains { marker in
            marker.hasPrefix("*") ? fileName.hasSuffix(marker.dropFirst()) : fileName == marker
        }
    }

    public var exactMarkers: [String] {
        markers.filter { !$0.hasPrefix("*") }
    }

    public var hasPatternMarkers: Bool {
        markers.contains { $0.hasPrefix("*") }
    }
}

public struct CacheRule: Hashable, Sendable {
    public let id: String
    public let name: String
    public let path: String
    public let ecosystem: String
    public let restore: String

    public init(id: String, name: String, path: String, ecosystem: String, restore: String) {
        self.id = id
        self.name = name
        self.path = path
        self.ecosystem = ecosystem
        self.restore = restore
    }

    public func url(in home: URL) -> URL {
        home.appendingPathComponent(path, isDirectory: true)
    }
}

public enum Rules {
    public static let projects: [ProjectRule] = [
        ProjectRule(id: "node", folders: ["node_modules"], markers: ["package.json"], ecosystem: "Node.js", restore: "npm install"),
        ProjectRule(id: "node-build", folders: [".next", ".nuxt", ".svelte-kit", ".turbo", ".parcel-cache", ".angular"], markers: ["package.json"], ecosystem: "Node.js", restore: "rebuilt by the next build"),
        ProjectRule(id: "dotnet", folders: ["bin", "obj"], markers: ["*.csproj", "*.fsproj", "*.vbproj"], ecosystem: ".NET", restore: "dotnet restore && dotnet build"),
        ProjectRule(id: "swiftpm", folders: [".build"], markers: ["Package.swift"], ecosystem: "Swift", restore: "swift build"),
        ProjectRule(id: "cargo", folders: ["target"], markers: ["Cargo.toml"], ecosystem: "Rust", restore: "cargo build"),
        ProjectRule(id: "maven", folders: ["target"], markers: ["pom.xml"], ecosystem: "Java", restore: "mvn package"),
        ProjectRule(id: "gradle", folders: ["build", ".gradle"], markers: ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"], ecosystem: "Gradle", restore: "./gradlew build"),
        ProjectRule(id: "flutter", folders: [".dart_tool", "build"], markers: ["pubspec.yaml"], ecosystem: "Flutter", restore: "flutter pub get"),
        ProjectRule(id: "cocoapods", folders: ["Pods"], markers: ["Podfile"], ecosystem: "CocoaPods", restore: "pod install"),
        ProjectRule(id: "python-venv", folders: [".venv", "venv"], markers: ["pyproject.toml", "requirements.txt", "setup.py", "Pipfile"], ecosystem: "Python", restore: "recreate the virtual environment and reinstall"),
        ProjectRule(id: "tox", folders: [".tox"], markers: ["tox.ini"], ecosystem: "Python", restore: "tox"),
        ProjectRule(id: "terraform", folders: [".terraform"], markers: ["*.tf"], ecosystem: "Terraform", restore: "terraform init"),
    ]

    public static let caches: [CacheRule] = [
        CacheRule(id: "xcode-derived-data", name: "Xcode DerivedData", path: "Library/Developer/Xcode/DerivedData", ecosystem: "Xcode", restore: "rebuilt by Xcode on the next build"),
        CacheRule(id: "xcode-ios-device-support", name: "iOS DeviceSupport", path: "Library/Developer/Xcode/iOS DeviceSupport", ecosystem: "Xcode", restore: "copied again when a device connects"),
        CacheRule(id: "xcode-watchos-device-support", name: "watchOS DeviceSupport", path: "Library/Developer/Xcode/watchOS DeviceSupport", ecosystem: "Xcode", restore: "copied again when a device connects"),
        CacheRule(id: "simulator-caches", name: "Simulator caches", path: "Library/Developer/CoreSimulator/Caches", ecosystem: "Xcode", restore: "rebuilt by the simulator"),
        CacheRule(id: "swiftpm", name: "SwiftPM cache", path: "Library/Caches/org.swift.swiftpm", ecosystem: "Swift", restore: "downloaded again on resolve"),
        CacheRule(id: "cocoapods", name: "CocoaPods cache", path: "Library/Caches/CocoaPods", ecosystem: "CocoaPods", restore: "downloaded again by pod install"),
        CacheRule(id: "npm", name: "npm cache", path: ".npm/_cacache", ecosystem: "Node.js", restore: "downloaded again by npm install"),
        CacheRule(id: "yarn", name: "Yarn cache", path: "Library/Caches/Yarn", ecosystem: "Node.js", restore: "downloaded again by yarn install"),
        CacheRule(id: "yarn-berry", name: "Yarn Berry cache", path: ".yarn/berry/cache", ecosystem: "Node.js", restore: "downloaded again by yarn install"),
        CacheRule(id: "pnpm", name: "pnpm store", path: "Library/pnpm/store", ecosystem: "Node.js", restore: "downloaded again by pnpm install"),
        CacheRule(id: "bun", name: "Bun cache", path: ".bun/install/cache", ecosystem: "Node.js", restore: "downloaded again by bun install"),
        CacheRule(id: "node-gyp", name: "node-gyp headers", path: "Library/Caches/node-gyp", ecosystem: "Node.js", restore: "downloaded again on the next native build"),
        CacheRule(id: "electron", name: "Electron downloads", path: "Library/Caches/electron", ecosystem: "Node.js", restore: "downloaded again on install"),
        CacheRule(id: "playwright", name: "Playwright browsers", path: "Library/Caches/ms-playwright", ecosystem: "Node.js", restore: "npx playwright install"),
        CacheRule(id: "puppeteer", name: "Puppeteer browsers", path: ".cache/puppeteer", ecosystem: "Node.js", restore: "downloaded again on install"),
        CacheRule(id: "typescript", name: "TypeScript typings cache", path: "Library/Caches/typescript", ecosystem: "Node.js", restore: "downloaded again by the editor"),
        CacheRule(id: "nuget", name: "NuGet packages", path: ".nuget/packages", ecosystem: ".NET", restore: "downloaded again by dotnet restore"),
        CacheRule(id: "nuget-http", name: "NuGet HTTP cache", path: ".local/share/NuGet/http-cache", ecosystem: ".NET", restore: "downloaded again by dotnet restore"),
        CacheRule(id: "nuget-v3", name: "NuGet v3 cache", path: ".local/share/NuGet/v3-cache", ecosystem: ".NET", restore: "downloaded again by dotnet restore"),
        CacheRule(id: "gradle", name: "Gradle caches", path: ".gradle/caches", ecosystem: "Gradle", restore: "downloaded again by the next build"),
        CacheRule(id: "gradle-wrapper", name: "Gradle wrapper distributions", path: ".gradle/wrapper/dists", ecosystem: "Gradle", restore: "downloaded again by ./gradlew"),
        CacheRule(id: "maven", name: "Maven repository", path: ".m2/repository", ecosystem: "Java", restore: "downloaded again by mvn"),
        CacheRule(id: "pip", name: "pip cache", path: "Library/Caches/pip", ecosystem: "Python", restore: "downloaded again by pip install"),
        CacheRule(id: "uv", name: "uv cache", path: ".cache/uv", ecosystem: "Python", restore: "downloaded again by uv"),
        CacheRule(id: "poetry", name: "Poetry cache", path: "Library/Caches/pypoetry", ecosystem: "Python", restore: "downloaded again by poetry install"),
        CacheRule(id: "go-build", name: "Go build cache", path: "Library/Caches/go-build", ecosystem: "Go", restore: "rebuilt by go build"),
        CacheRule(id: "cargo-registry", name: "Cargo registry", path: ".cargo/registry", ecosystem: "Rust", restore: "downloaded again by cargo"),
        CacheRule(id: "composer", name: "Composer cache", path: "Library/Caches/composer", ecosystem: "PHP", restore: "downloaded again by composer install"),
        CacheRule(id: "deno", name: "Deno cache", path: "Library/Caches/deno", ecosystem: "Deno", restore: "downloaded again by deno"),
        CacheRule(id: "homebrew", name: "Homebrew downloads", path: "Library/Caches/Homebrew", ecosystem: "Homebrew", restore: "downloaded again by brew install"),
    ]

    public static let artifactFolders: Set<String> = Set(projects.flatMap(\.folders))

    public static func projectRules(for folder: String) -> [ProjectRule] {
        projects.filter { $0.matches(folder: folder) }
    }

    public static func project(id: String) -> ProjectRule? {
        projects.first { $0.id == id }
    }

    public static func cache(id: String) -> CacheRule? {
        caches.first { $0.id == id }
    }

    public static let neverDescend: Set<String> = ["node_modules", "Pods", "vendor", "venv", "DerivedData"]

    public static let skippedTopLevel: Set<String> = ["Library", "Applications", "Pictures", "Music", "Movies", "Public"]

    public static let skippedRelativePaths: Set<String> = ["go/pkg"]

    public static let packageExtensions: Set<String> = [
        "app", "appex", "framework", "bundle", "plugin", "kext", "xcarchive",
        "photoslibrary", "musiclibrary", "tvlibrary", "photolibrary", "imovielibrary", "fcpbundle", "logicx",
    ]
}
