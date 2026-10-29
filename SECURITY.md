# Security Policy

DevSweep deletes files, so it is built to delete as little as possible and only what you confirmed.

## What the app accesses

| Resource | Access | Why |
| --- | --- | --- |
| Your home folder | Read folder listings and file metadata (names, sizes, modification times) | Finding build folders and measuring them. File contents are never read. |
| Folders you confirm in the Clean dialog | Delete | The only writes outside the app's own files |
| `docker` CLI, if installed | Run `system df` and, when you clean Docker items, `image prune --all`, `container prune`, `builder prune --all` | The Docker section |
| `UserDefaults` | Read / write | Exclusions, idle threshold, reminder settings, total freed |
| `~/Library/Application Support/io.github.recepysl.dev-sweep` | Read / write | The last scan, so the menu opens instantly |
| Notification Center | Post | Local reminders, if enabled |

DevSweep makes no network requests at all. There is no analytics or telemetry.

Before deleting, every path is checked again: inside your home folder, canonical, a real folder and not a symbolic link, not excluded, and still matching its rule (including the project file next to it). See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#cleaning).

## Supported versions

Only the latest release receives fixes.

## Reporting a vulnerability

Please **do not open a public issue** for security problems, for example a way to make DevSweep delete something outside its rules. Instead, use GitHub's [private vulnerability reporting](https://github.com/recepysl/dev-sweep/security/advisories/new) for this repository. You can expect an initial response within a few days.
