# PhoneVault 📱🔒

A native macOS desktop application for live inspecting, browsing, and exporting internal databases and files from iOS apps over USB/Lightning without taking full device backups. Also supports offline iTunes/Finder backup inspection.

Built using **Swift**, **SwiftUI**, Apple's system **SQLite3**, and **Foundation**. Operates 100% locally and offline without cloud services or external servers.

---

## Features

- **Live USB App Inspection (Zero Backup Needed)**:
  - Connect an iPhone via USB or Lightning cable.
  - Instantly list installed apps on the device.
  - Automatically identifies app access levels:
    - **Container (Debug)**: Full access to internal databases, `Library/Application Support/`, `Library/Preferences/`, and `Documents/` for developer/debug builds (`get-task-allow`).
    - **Documents (File Sharing)**: Access to `Documents/` and subfolders for apps with `UIFileSharingEnabled`.
  - On-demand streaming: clicking an SQLite DB or plist downloads only that file into a lightweight cache in milliseconds.
  - SQLite WAL mode awareness: automatically fetches `-wal` and `-shm` companion files alongside SQLite databases so you always see the latest uncheckpointed writes.
  - Live refresh: reload files and inspect databases in real time while using the app on your phone.
- **Offline iOS Backups**:
  - Reads unencrypted iTunes and Finder iOS backup folders (`~/Library/Application Support/MobileSync/Backup/<UUID>`).
  - Maps manifest entries and domains (`AppDomain-com...`) to directory trees.
  - Create new local backups directly via `idevicebackup2` or with built-in macOS Finder guidance.
- **Hierarchical File Browser**:
  - Virtual directory hierarchy navigation with interactive breadcrumbs.
  - Search across file names and relative paths.
  - Multi-column file table with sorting by Name, Path, Size, and Modification Date.
- **Format-Specific Inspection**:
  - **SQLite**: Lists tables, views, schemas, and row counts; reads paginated table rows in an interactive data grid (read-only).
  - **Property Lists**: Visual, expandable tree view of dictionaries, arrays, primitives, and raw bytes.
  - **JSON**: Syntax-formatted, pretty-printed text preview.
  - **Text & Logs**: Safe text reader with configurable byte limits and truncation warnings.
  - **Images**: Native image renderer with dimensions and metadata.
  - **Generic / Binary**: Safe fallback displaying metadata and file-export options.
- **Safe Export Engine**:
  - Export single files, multi-file selections, directories, or entire apps.
  - Preserves original relative folder hierarchy.
  - Validates destination paths against path traversal (`..`).
  - Safe automatic disambiguation on duplicate filenames (`(2)`, `(3)`, etc.).
  - Guarantees exact bit-for-bit file integrity.

---

## What iOS Backups Contain and Do Not Contain

PhoneVault is designed around iOS backup semantics:

- **Contained**: Documents, databases, preferences (`Library/Preferences/*.plist`), application state files, and cached data marked for backup inclusion by app developers.
- **Excluded by iOS Design**:
  - Encrypted backups without a valid decryption phase.
  - Application binaries (`.app` bundles, Mach-O executables, compiled frameworks).
  - Temporary folders (`tmp/`) and caches marked `NSURLIsExcludedFromBackupKey`.
  - Sensitive keychain items (passwords, certificates) unless stored in developer-managed app databases.
  - Live private container access on jailed, non-backup states.

---

## Building and Running

### Prerequisites
- macOS 14.0 Sonoma or later
- Xcode 15 or later (or Swift 6 toolchain)

**Optional (for Live USB Inspection):**
Device discovery and offline backup inspection work out of the box with zero external dependencies. To inspect live app containers and stream files over USB, install the `libimobiledevice` toolchain:
```bash
brew install libimobiledevice ideviceinstaller
```

### Quick Start with Make

```bash
# Build release macOS application bundle (build/PhoneVault.app)
make app

# Launch the app
make run

# Run all test suites
make test
```

### Manual Build via Scripts

```bash
# Build the release app bundle
./scripts/build-app.sh --release

# The bundle is located at:
open build/PhoneVault.app
```

---

## Architecture Overview

```
PhoneVault/
├── src/
│   ├── PhoneVaultCore/           # Standalone domain & parser library
│   │   ├── Backup/               # BackupReader: Manifest.db & Info.plist parser
│   │   ├── Device/               # usbmuxd monitor & live AFC/ideviceinstaller services
│   │   ├── Formats/              # Format inspectors (SQLite, Plist, JSON, Text)
│   │   ├── Export/               # ExportService: safe path verification & copying
│   │   └── Models/               # Domain models (AppRecord, BackupFile, etc.)
│   └── PhoneVaultApp/            # SwiftUI macOS application
│       ├── ViewModels/           # BackupViewModel (@Observable)
│       ├── Views/
│       │   ├── Device/           # Connected device details & live app browser
│       │   ├── Sidebar/          # App list & backup summary
│       │   ├── FileBrowser/      # Filterable virtual file table
│       │   ├── Inspector/        # File metadata & format previews
│       │   └── Shared/           # Empty states and UI components
├── resources/
│   └── AppIcon.icns              # Application icon
├── tests/
│   └── PhoneVaultCoreTests/      # Automated tests for parser, formats & export
└── scripts/
    ├── build-app.sh              # Packages and signs PhoneVault.app
    └── generate-icon.swift       # Generates multi-resolution AppIcon
```

---

## Testing

PhoneVault includes comprehensive test suites using Swift Testing covering:
- Manifest parsing & payload resolution
- Corrupt / missing payload reporting
- Plist decoding & formatting
- SQLite schema extraction & paginated row queries
- JSON pretty-printing & malformed payload rejection
- Text reader limits & truncation
- Path traversal prevention during file export
- Byte preservation and filename collision handling

Run tests with:
```bash
make test
```
