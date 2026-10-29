# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-10-29

First release.

### Added
- Menu bar icon with the reclaimable amount, orange above the reminder threshold or below 10 % free disk, red below 5 %.
- **Projects**: build and dependency folders next to their project file (Node.js, .NET, Swift, Rust, Maven, Gradle, Flutter, CocoaPods, Python, Terraform), grouped per project with days since last activity.
- **Global caches**: npm, Yarn, pnpm, Bun, NuGet, Gradle, Maven, pip, uv, Poetry, Go, Cargo, CocoaPods, SwiftPM, Composer, Deno, Homebrew, Playwright, Puppeteer, Electron, node-gyp, TypeScript, Xcode DerivedData, DeviceSupport and simulator caches.
- **Docker**: unused images, stopped containers and build cache through the `docker` CLI; volumes are never touched.
- Projects idle for 30+ days (configurable) are preselected after each scan; one confirmation before deleting; every path re-validated right before removal.
- Parallel scanner built on `getattrlistbulk`; hard-linked files aren't counted as reclaimable.
- Disk usage bar, *Freed so far* total, right-click *Show in Finder*, *Copy Path* and *Exclude from Scans*.
- Weekly reminder above a threshold and a daily warning when the disk is almost full.
- Settings window: idle threshold, excluded folders, reminders, *Open at Login*.
- CLI modes: `--once` (dry run, optional `--json`), `--selftest`, `--render-screenshots`.
- `scripts/install.sh` one-line installer.

[1.0.0]: https://github.com/recepysl/dev-sweep/releases/tag/v1.0.0
