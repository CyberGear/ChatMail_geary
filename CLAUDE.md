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

## Contact-Centric UI (ChatMail Fork)

This fork replaces Geary's folder-based navigation with a contact-centric layout. Design spec: `docs/superpowers/specs/2026-04-15-contact-centric-ui-design.md`.

### Layout: Contacts → Emails → Viewer

- **Column 1** (`src/client/contact-list/`): Contact list grouped by account, sorted by most recent email. Avatar initials + name + email + badge count.
- **Column 2** (`src/client/contact-email-list/`): Emails filtered by selected contact. Inbox emails matched by `from`, Sent emails matched by `to`. Direction arrows: ↓ incoming (left), ↑ outgoing (right).
- **Column 3**: Single email viewer via `ConversationViewer.load_single_email()` (not threaded conversations).

### How Contact Data Is Sourced

Both the contact list and email list use the **same filtering logic** — this is critical for consistency:

- **Contact list population** (`contact-list-view.vala:populate_account`): Queries the local SQLite DB directly (`geary.db`), joining `MessageTable` with `MessageLocationTable` and `FolderTable`. Inbox folder: extracts sender from `from_field`. Sent folder: extracts recipient from `to_field`. Email addresses extracted from RFC822 angle brackets (`<email>`).
- **Email list filtering** (`contact-email-list-view.vala:collect_from_folder`): Uses `Folder.list_email_by_id_async()` then filters with `address_list_contains()` on `email.from` (inbox) or `email.to/cc/bcc` (sent).
- **Any change to filtering logic must be applied to BOTH** to keep counts and lists consistent.

### Local SQLite DB Access

The contact list reads `geary.db` directly via `Sqlite.Database` (added `sqlite` to client meson dependencies). The DB path comes from `account.information.data_dir.get_child("geary.db")`. Key tables:

- `FolderTable` — folder names and attributes. Inbox identified by `name = "INBOX"`, Sent by `\Sent` in attributes.
- `MessageTable` — `from_field`, `to_field`, `date_time_t` (Unix timestamp). RFC822 format: `"Name" <email@addr>`.
- `MessageLocationTable` — links `message_id` to `folder_id`.
- `ContactTable` — `email`, `real_name`, `highest_importance`.

### Legacy Code Still Present

The old `FolderList.Tree` and `ConversationList.View` are still instantiated in `MainWindow` for compatibility with the rest of the codebase (keyboard shortcuts, search, actions). They are not added to the UI — the new `ContactList.View` and `ContactEmailList.View` replace them in the layout. The old widgets can be removed once all dependent code paths are migrated.

### Known Issues / Future Work

- **Email viewer shows preview text only** — `load_single_email()` renders the preview snippet as plain text, not the full HTML body. To fix: use `ConversationWebView` or `ConversationEmail` to render the full RFC822 message body with HTML.
- **Multi-recipient sent emails** — The SQL query only extracts the FIRST recipient from `to_field`. Emails sent to multiple recipients where the contact is not the first `to` address may be missed. Fix: parse all addresses from `to_field` in the SQL query or switch to a Vala-side scan.
- **Contact search** — The search bar filters the already-loaded contact list by name/email substring. It does not re-query the database.
- **Compose/reply** — The existing Geary composer infrastructure still works but is wired through the old code paths. The `do_compose` method in `ConversationViewer` references `conversation_list_view` which is still instantiated. Full compose integration needs updating.
- **Unread tracking** — Badge counts show total email count, not unread count. Implementing unread requires checking email flags.
- **Responsive layout** — The `HdyLeaflet` folding still works but `on_contact_selected`/`on_email_selected` handlers could be refined for mobile navigation.
- **WebKit sandbox** — Requires `WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1` env var in some environments where bubblewrap is restricted.
- **CSS theming** — `ui/contact-list.css` uses `@theme_selected_bg_color` and `opacity` for theme compatibility. Avoid hardcoded hex colors.
- **libpeas-2 VAPI** — Generated manually via `vapigen` and placed in `bindings/vapi/libpeas-2.vapi` because Vala 0.56 doesn't ship it. Regenerate if upgrading libpeas.
- **Meson version** — Root `meson.build` and `subprojects/vala-unit/meson.build` were patched from `>= 1.7` to `>= 1.3` for local builds. Revert when using a system with Meson 1.7+.
