# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Geary is an email client application built for the GNOME desktop using Vala and GTK. It organizes email around conversations rather than folders, providing a modern, straightforward interface.

## Building & Development

### Build System
- Uses **Meson** and **Ninja** for building
- Required build command sequence:
  ```bash
  meson build
  ninja -C build
  ```

### Build Profiles
- `development` - Default for development work (detected from .git directory)
- `beta` - Beta version with different branding
- `release` - Release builds for packaging

### Build Options
```bash
# Configure build with options
meson setup build -Dprofile=development -Dvaladoc=true
ninja -C build

# Run tests
meson test -C build

# Run all tests
meson test -C build --

# Run specific test
meson test -C build -v -t 10 <TEST_NAME>
```

### Build Profiles Setup
```bash
# Development (default)
meson setup build -Dprofile=development

# Beta
meson setup build -Dprofile=beta

# Release
meson setup build -Dprofile=release
```

### Test Command Reference
```bash
# Run all tests
meson test -C build

# Run with test timeout (default 10)
meson test -C build -t 10

# Run verbose tests
meson test -C build -v

# Run specific test
meson test -C build -v test-name

# Run tests without color output
meson test -C build --no-stdsplit

# Run with test arguments
meson test -C build $TEST_ARGS  # e.g., -t 10 for timeout
```

## Project Structure

```
src/
├── client/          # UI/GUI layer
│   ├── application/ # Application-wide services (accounts, contacts, database)
│   ├── components/  # Reusable UI components
│   ├── composer/    # Email composition window
│   ├── conversation-list/  # Conversation list view
│   ├── conversation-viewer/  # Email viewing
│   ├── dialogs/     # Dialog windows
│   ├── folder-list/  # Folder tree view
│   └── plugin/      # Plugin system
├── console/         # Console-based tools
├── engine/          # Core email handling (IMAP, MIME, RFC822)
│   ├── api/         # Geary API
│   ├── app/         # Application logic
│   ├── common/      # Common utilities
│   ├── db/          # Database access
│   ├── imap/        # IMAP protocol handling
│   ├── imap-db/     # IMAP database operations
│   ├── imap-engine/ # IMAP account engines
│   ├── mime/        # MIME handling
│   ├── outbox/      # Outbox operations
│   ├── rfc822/      # Email parsing
│   └── util/        # Utilities
└── mailer/          # Email sending logic

test/
├── client/          # Client-side unit tests
├── engine/          # Engine unit tests
├── integration/     # Integration tests
└── js/              # JavaScript unit tests

ui/                  # Glade UI files
desktop/             # Desktop files and schemas
help/                # User documentation
icons/               # Application icons
```

## Architecture

### Three-Tier Architecture

1. **Engine Layer** (`src/engine/`)
   - Core email handling: IMAP parsing, MIME processing, RFC822 email handling
   - Database operations for IMAP state
   - Contains internal APIs (not directly exposed)

2. **Client Layer** (`src/client/`)
   - UI components and GTK widgets
   - Application-wide services (accounts manager, contacts, database)
   - Uses Geary API (exposed in engine)
   - Contains internal APIs

3. **API Layer**
   - Geary API exposed via `geary-engine-*.vapi`
   - Reused by client and engine tests
   - Mock implementations for testing

### Testing Strategy

The project uses **ValaUnit** for unit testing with three distinct test suites:

1. **Engine Tests** (`test-engine`)
   - Tests engine layer functionality
   - IMAP protocol handling
   - Email parsing and MIME operations
   - Database operations

2. **Client Tests** (`test-client`)
   - Tests client-side UI components
   - Application configuration
   - Contact/composer widgets
   - Runs in Xvfb for GUI rendering

3. **Integration Tests** (`test-integration`)
   - End-to-end functionality tests
   - Requires network access

4. **JavaScript Tests** (`test-js`)
   - Tests JavaScript components used in web views

### Test Infrastructure

```bash
# Run engine tests only
meson test -C build 'engine-tests'

# Run client tests only
meson test -C build 'client-tests'

# Run JS tests only
meson test -C build 'js-tests'

# Run all tests
meson test -C build
```

## Dependencies

### Required
- GTK 3.24.24+
- WebKitGTK 4.1 (2.30+)
- SQLite 3.24+ (with FTS3 and FTS5 support)
- Valac 0.56+

### Optional
- libunwind (for better stack traces)
- libytnef (for TNEF/Outlook attachment support)
- enchant-2 (spell checking)

## Code Style

See `.editorconfig` for formatting rules:
- 4-space indentation for Vala files
- 2-space indentation for XML/CSS/JSON
- LF line endings
- UTF-8 charset
- Trim trailing whitespace

## License

LGPL-2.1-or-later

## Related Projects

- [Geary Wiki](https://gitlab.gnome.org/GNOME/geary/-/wikis)
- [GNOME Discourse](https://discourse.gnome.org/tags/c/applications/7/geary)
- [Matrix](https://gnome.element.io/#/room/#geary:gnome.org)
