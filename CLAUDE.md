# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is Geary

Geary is a conversation-based email client for the GNOME desktop, written primarily in Vala. It implements IMAP and SMTP protocols from scratch (no third-party protocol library), uses SQLite for local storage with full-text search, and renders email HTML via WebKitGTK.

## Build Commands

A `justfile` is provided. Use `just <recipe>` for all common tasks:

```bash
just setup            # Configure (development profile, debug build)
just setup-release    # Configure for release
just build            # Build (auto-configures if needed)
just run              # Build and run from build dir (no install)
just install          # Install to system
just uninstall        # Uninstall from system
just test             # Run all tests
just test-xvfb        # Run all tests with virtual display (headless)
just test-engine      # Engine unit tests only (headless-safe)
just test-client      # Client/GTK unit tests (needs display)
just test-js          # JavaScript unit tests (needs display)
just test-ci          # Run tests matching CI settings
just test-verbose     # Verbose test output
just clean            # Remove build directory
just rebuild          # Clean + build
just show-config      # Show current build configuration
just configure -Dprofile=beta   # Reconfigure a build option
just docs             # Build API docs (requires valadoc)
just update-darkreader  # Update vendored DarkReader JS
```

Build profiles: `auto` (default, detects from .git), `development`, `beta`, `release`. Set via `-Dprofile=<value>`.

## Architecture

### Three-Layer Design

```
Client Layer (src/client/)          — GTK UI, plugins, composer, conversation viewer
    ↓
Engine API (src/engine/api/)        — Abstract interfaces: Account, Folder, Email, Engine
    ↓
Engine Implementation (src/engine/) — IMAP/SMTP protocols, SQLite DB, sync logic
```

The engine is fully independent of GTK — it can theoretically be reused without the UI.

### Source Layout

- `src/engine/` — Email backend (protocol-agnostic API + IMAP/SMTP/DB implementations)
  - `api/` — Public interfaces and abstract base classes
  - `imap/` — Custom IMAP protocol implementation (commands, responses, transport)
  - `imap-engine/` — Bridges IMAP protocol to engine API (sync, replay queue, prefetching)
  - `imap-db/` — SQLite persistence for IMAP data
  - `smtp/` — Custom SMTP protocol implementation
  - `outbox/` — Local outbox folder for queued unsent emails
  - `db/` — Generic SQLite wrapper (async transactions, connection pooling)
  - `app/` — Higher-level abstractions (ConversationMonitor, SearchFolder, DraftManager)
  - `rfc822/`, `mime/` — Email format parsing (uses GMime 3.0)
  - `nonblocking/` — Async primitives (locks, semaphores, queues)
  - `state/` — State machine for protocol sequencing
- `src/client/` — Desktop UI
  - `application/` — GTK.Application entry point, controller, main window
  - `plugin/` — Plugin system (libpeas 2) and built-in plugins
  - `composer/` — Email composition (rich text via WebKitGTK)
  - `conversation-viewer/` — Threaded message display
  - `conversation-list/` — Conversation previews
  - `folder-list/` — Folder tree sidebar
  - `accounts/` — Account configuration UI
  - `components/` — Reusable GTK widgets
  - `web-process/` — WebKitGTK extension (sandboxed DOM manipulation)
- `ui/` — GTK .ui layout files, CSS, JavaScript (bundled as GResource)
- `sql/` — 30 versioned SQLite migration scripts (version-001.sql through version-030.sql)
- `bindings/vapi/` — Custom Vala bindings for C libraries (do not auto-generate)
- `test/` — Engine, client, and JS unit tests + manual integration tests
- `po/` — Gettext translations (40+ languages)
- `desktop/` — GSettings schema, .desktop file, AppStream metadata

### Key Design Decisions

- **Custom IMAP/SMTP**: Implemented from scratch for fine-grained control, retry logic, and provider-specific optimizations (Gmail, Outlook, generic).
- **Replay Queue**: Server changes are replayed to the local DB via `imap-engine-replay-queue.vala`, handling race conditions and supporting undo.
- **Client-side conversation threading**: Messages grouped by message-id/in-reply-to/references, not server-side THREAD extension.
- **Lazy email loading**: Only metadata fetched initially; bodies/attachments loaded on demand with background prefetching.
- **Async database**: SQLite operations are async-compatible via background thread pool, preventing UI blocking.
- **Provider detection**: Auto-detects Gmail/Outlook/generic IMAP, each with specialized folder handling classes in `imap-engine/`.

### Plugin System

Built on libpeas 2. Plugins extend `Plugin.PluginBase` with `activate()`/`deactivate()` lifecycle methods. Extension interfaces: `NotificationExtension`, `EmailExtension`, `FolderExtension`. Built-in plugins are in `src/client/plugin/` (desktop-notifications, email-templates, mail-merge, folder-highlight, sent-sound, etc.).

### Credentials

Abstracted via `CredentialsMediator` interface with implementations for GNOME Online Accounts and libsecret.

## Vala Language Notes

- Vala compiles to C via GLib/GObject. Intermediate C files are not manually edited.
- Async/await is built-in (`async` methods, `yield` keyword, `GLib.Cancellable` for cancellation).
- GLib signals are first-class. UI reacts to engine signals.
- Properties are GObject properties, not C++ getters/setters.
- Custom error domains (e.g., `EngineError`, `ImapError`, `SmtpError`) — thrown with `throw new ErrorDomain.CODE("msg")`.

## Code Style

Defined in `.editorconfig`:
- Vala: 4-space indent
- XML/CSS: 2-space indent
- Meson build files: 2-space indent
- JSON: 4-space indent
- All files: UTF-8, LF line endings, trim trailing whitespace

## Database Migrations

SQLite schema is versioned in `sql/version-NNN.sql`. Migrations applied sequentially on startup by `Geary.Db.VersionedDatabase`. Schema version tracked via SQLite `user_version` pragma. Never modify existing migration files — always add a new version.

## Translations

Uses GLib gettext. `_()` for standard strings, `NC_()` for context-specific translations. Translation files in `po/`. Plugin translations use custom msgfmt keywords (`--keyword=Name`, `--keyword=Description`).

## CI

GitLab CI (`.gitlab-ci.yml`): builds on Fedora container + Flatpak, runs tests via `xvfb-run -a dbus-run-session -- meson test`. Tests have a 10x timeout multiplier for CI.

## Integration Tests (Manual)

Not part of `meson test`. Run against real servers:
```bash
build/test/test-integration imap gmail test@gmail.com password
build/test/test-integration imap outlook test@outlook.com password
build/test/test-integration imap other mail.example.com test@example.com password
```

## Important Files

- `src/client/application/main.vala` — Application entry point
- `src/client/application/application-client.vala` — GTK.Application subclass
- `src/client/application/application-controller.vala` — Coordinates UI and engine
- `src/engine/imap-engine/imap-engine-minimal-folder.vala` — Core folder logic (~1700 lines)
- `src/engine/imap-engine/imap-engine-replay-queue.vala` — Server sync replay queue
- `src/engine/app/app-conversation-monitor.vala` — Conversation threading
- `desktop/org.gnome.Geary.gschema.xml` — GSettings schema (app preferences)
- `ui/org.gnome.Geary.gresource.xml` — Resource bundle manifest
- `ui/darkreader.js` — Vendored DarkReader library (update manually from CDN)
