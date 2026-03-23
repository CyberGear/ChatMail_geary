# Geary Development Guide

This file provides essential information for agents working on the Geary email client codebase.

## Project Overview

Geary is a GNOME email application built with [Vala](https://wiki.gnome.org/Vala) and GTK3.
The project uses the Meson build system and follows GNOME coding conventions.

## Build Commands

### Basic Build
```bash
meson build          # Configure the build
ninja -C build      # Compile the project
./build/src/geary   # Run without installing
```

### Running Tests
```bash
meson test -C build              # Run all tests
meson test -C build engine-tests  # Run specific test suite
meson test -C build -v           # Run with verbose output
```

Available test suites:
- `engine-tests` - Core engine functionality
- `client-tests` - Client UI components
- `js-tests` - JavaScript components

### Clean Build
```bash
rm -rf build && meson build && ninja -C build
```

### Build Profiles
```bash
meson setup build -Dprofile=development  # Development (default in git)
meson setup build -Dprofile=beta         # Beta release
meson setup build -Dprofile=release       # Production release
```

## Code Style Guidelines

### EditorConfig
The project uses `.editorconfig` for consistent formatting. Key settings:

| File Type     | Indent Style | Indent Size |
|--------------|--------------|-------------|
| `*.vala`     | space        | 4           |
| `*.xml`      | space        | 2           |
| `*.css`      | space        | 2           |
| `meson.build`| space        | 2           |

### Copyright Header
Every `.vala` file must include this header:
```vala
/*
 * Copyright [year(s)] [Author Name] <email@example.com>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */
```

### Naming Conventions

**Classes & Interfaces:**
```vala
public class Geary.Email : BaseObject { }           // Public class
public interface Geary.Folder : GLib.Object { }   // Public interface
private class InternalImpl { }                     // Private class
internal class PackageVisible { }                   // Internal (assembly) visibility
```

**Methods:** `snake_case`
```vala
public void open_async() throws GLib.Error { }
public string get_preview_as_string() { }
```

**Constants:** `UPPER_SNAKE_CASE`
```vala
public const int MAX_PREVIEW_BYTES = 256;
private const string INTERNAL_NAME = "geary";
```

**Enums:** `CamelCase`
```vala
public enum Field {
    NONE,
    DATE,
    SUBJECT
}
```

**Private fields:** prefixed with `_`
```vala
private RFC822.MailboxAddresses? _from = null;
private Geary.RFC822.Message? message = null;
```

### Doc Comments
Use `/** ... */` for documentation. See `src/engine/api/geary-email.vala` for examples:
```vala
/**
 * An Email represents a single RFC 822 style email message.
 *
 * @see Folder
 * @see Email.fields
 */
public class Geary.Email : BaseObject {
    /**
     * The maximum expected length of message body preview text.
     */
    public const int MAX_PREVIEW_BYTES = 256;
}
```

### Virtual Signals
```vala
public virtual signal void connected(Greeting greeting);
public virtual signal void disconnected();
public virtual signal void scan_completed();
```

## Code Patterns

### Async Methods
Methods that perform I/O must use async patterns:
```vala
public async void open_async() throws GLib.Error {
    // ... async operations ...
}
```

### Error Handling
```vala
public void some_method() throws GLib.Error {
    try {
        do_something();
    } catch (Error err) {
        debug("Error occurred: %s", err.message);
        throw err;
    }
}
```

### GLib Type References
Use `GLib.` prefix for GLib types to avoid ambiguity:
```vala
GLib.File.new_for_uri(uri)
GLib.Regex.new(WS_OR_NP)
GLib.MainLoop
```

### Namespace Imports
Organize imports by:
1. GLib/GTK namespaces
2. Internal Geary namespaces
3. Project-local imports

## Directory Structure

```
src/
├── engine/          # Core email engine
│   ├── api/         # Public API interfaces
│   ├── app/         # Application logic
│   ├── imap/        # IMAP protocol implementation
│   ├── smtp/        # SMTP protocol implementation
│   └── util/        # Utility functions
├── client/          # GTK client application
│   ├── application/ # Application entry point
│   └── components/  # UI components
├── console/         # Console debugger tool
└── mailer/         # Send mail utility

test/
├── engine/          # Engine unit tests
├── client/          # Client unit tests
├── js/              # JavaScript tests
└── mock/            # Mock implementations for testing

subprojects/
└── vala-unit/       # ValaUnit testing framework
```

## Testing Conventions

### Test File Structure
```vala
class Geary.EmailTest: TestCase {
    public EmailTest() {
        base("Geary.EmailTest");
        add_test("email_from_basic_message", email_from_basic_message);
    }

    public void email_from_basic_message() throws GLib.Error {
        // Test implementation
    }
}
```

### Test Assertions
Use the assertions from `TestCase`:
```vala
assert_true(condition, "message");
assert_false(condition, "message");
assert_equal(actual, expected, "message");
assert_non_null(value, "message");
```

### Test Fixtures
Override `set_up()` and `tear_down()` for fixture management:
```vala
public override void set_up() throws GLib.Error {
    // Initialize test fixtures
}

public override void tear_down() throws GLib.Error {
    // Clean up resources
}
```

## Dependencies

Key dependencies (minimum versions):
- Vala >= 0.56
- GLib >= 2.74
- GTK >= 3.24.24
- WebKitGTK >= 2.30
- SQLite >= 3.24 (with FTS3 and FTS5 support)
- Geeqie >= 0.8.5

## Contributing

Before committing:
1. Run `meson test -C build` to ensure tests pass
2. Ensure code follows GNOME HIG and project conventions
3. Update copyright years when modifying files
4. Add tests for new functionality

See [CONTRIBUTING.md](CONTRIBUTING.md) and [BUILDING.md](BUILDING.md) for more details.
