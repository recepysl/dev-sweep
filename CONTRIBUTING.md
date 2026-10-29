# Contributing

Thanks for taking the time to improve DevSweep! Bug reports, ideas, new rules and pull requests are all welcome.

## Getting started

You need macOS 14+ and a Swift 5.9+ toolchain (Xcode or the Command Line Tools).

```bash
git clone https://github.com/recepysl/dev-sweep.git
cd dev-sweep
make run          # build DevSweep.app and launch it from the repo
make once         # dry run against your home folder, deletes nothing
```

## Adding a rule

Most contributions are a new line in [`Sources/SweepKit/Rules.swift`](Sources/SweepKit/Rules.swift):

- **Project rule:** the folder name(s), the marker file(s) that must sit next to them, the ecosystem and how the folder comes back. Only add folders that are fully regenerable and never committed in practice.
- **Cache rule:** a path relative to the home folder that the tool recreates on its own.

Add an assertion to `SelfCheck.swift` when the rule has a twist (shared folder name, pattern marker).

## Before you open a pull request

- `make selftest` passes (and `make test` if you have Xcode).
- `swift build -c release` builds without warnings.
- If you changed anything visible, run `make screenshots` and commit the updated images in `docs/images/`.
- User-facing changes have an entry under an *Unreleased* heading in [CHANGELOG.md](CHANGELOG.md).

## Guidelines

- **Safety first.** Never offer anything that isn't regenerable. Never follow symbolic links. Every deletion path must go through `Cleaner.refusal(for:in:)`.
- **Keep it dependency-free.** Apple frameworks only.
- **Keep logic in `SweepKit`.** Anything that doesn't need SwiftUI belongs there, with assertions in `SelfCheck.swift`.
- **No network.** The app doesn't talk to any server.
- **Never commit real data.** Screenshots and fixtures use made-up paths only.

## Commit messages

The history follows [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(kit): add Bazel output folders
fix(app): keep the selection after excluding an item
docs: explain the idle threshold
```

Common types are `feat`, `fix`, `docs`, `test`, `build`, `ci`, `refactor` and `chore`. Scopes are `kit`, `app` and `cli`.

## Releasing

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`.
2. Move the *Unreleased* changelog entries under the new version.
3. Tag and push: `git tag v1.1.0 && git push origin v1.1.0`.

The release workflow builds the DMG and publishes the GitHub release with the changelog section as notes.
