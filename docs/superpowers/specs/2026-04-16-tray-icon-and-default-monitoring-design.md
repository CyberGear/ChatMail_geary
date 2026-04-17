# Tray Icon and Default Background Monitoring

## Context

Geary (ChatMail fork) already supports background monitoring and desktop notifications, but there's no persistent visual indicator when the window is closed. Users have no way to restore the window without re-launching the app. This spec adds a system tray icon via AppIndicator and makes background monitoring the default behavior, so the app always monitors for new email and provides a tray icon for quick access.

## Requirements

1. **System tray icon** visible whenever the app is running
2. **Hide to tray on close** — clicking X hides the window instead of destroying it
3. **Tray menu** — right-click shows: Show Geary, Compose New Message, Quit
4. **Unread indicator** — tray icon switches to attention state when unread mail exists
5. **Default-on** — background monitoring and tray icon are enabled by default (no user action needed)
6. **Restore from tray** — left-clicking the tray icon shows/raises the main window

## Approach

Use `libayatana-appindicator3` via the StatusNotifierItem D-Bus protocol. This is the modern standard on Linux, supported by GNOME Shell (via `gnome-shell-extension-appindicator`), KDE Plasma, and most other desktop environments. Implemented as an autoloaded plugin following the existing notification-badge and desktop-notifications plugin patterns.

## Components

### 1. Window Close Behavior Change

**File**: `src/client/application/application-main-window.vala`

Modify `on_delete_event()` (line ~2148):

```vala
private bool on_delete_event() {
    if (close_composer(true, false)) {
        if (this.application.is_background_service) {
            // Hide to tray instead of destroying
            hide();
        } else {
            this.sensitive = false;
            this.select_folder.begin(
                null, false, true,
                (obj, res) => {
                    this.select_folder.end(res);
                    destroy();
                }
            );
        }
    }
    return Gdk.EVENT_STOP;
}
```

When `is_background_service` is true, the window hides instead of being destroyed. The app stays alive (existing `on_window_removed` logic in `application-client.vala` already prevents quit when `is_background_service` is true — and `window-removed` only fires on destroy, not hide).

Re-showing the window: `application.activate()` → `present()` → `get_active_main_window().present()` — this calls `Gtk.Window.present()` on the hidden window, which shows and raises it. The existing `last_active_main_window` reference keeps the window alive.

### 2. Status Icon Plugin

**Directory**: `src/client/plugin/status-icon/`

**Files**:
- `status-icon.vala` — plugin implementation
- `status-icon.plugin.in` — plugin metadata (translatable)
- `meson.build` — build rules

**Plugin class**: `Plugin.StatusIcon` extends `PluginBase`, implements `TrustedExtension`, `NotificationExtension`, `FolderExtension`.

**Lifecycle**:

```
activate():
  1. Create AppIndicator.Indicator(APP_ID, icon_name, COMMUNICATIONS)
  2. Set indicator status = ACTIVE
  3. Set icon = "org.gnome.Geary" (normal), attention icon = "org.gnome.Geary" (same icon, but ATTENTION status triggers DE-specific highlighting)
  4. Build Gtk.Menu with 3 items
  5. Set menu on indicator
  6. Start monitoring INBOX/NONE folders (same pattern as notification-badge)
  7. Connect to notifications.notify["total-new-messages"]

deactivate():
  1. Set indicator status = PASSIVE (hides it)
  2. Disconnect signals
  3. Destroy menu
```

**Menu items**:
- **"Show Geary"** / **"Show Geary (N unread)"** — calls `client_application.activate()` to present the window
- **"Compose New Message"** — activates the `app.compose` GLib.Action on the application
- **"Quit"** — calls `client_application.quit()`

**Unread state**:
- When `total_new_messages` > 0: set indicator status to `ATTENTION`, update menu label to include count
- When `total_new_messages` == 0: set indicator status to `ACTIVE`, reset menu label

**Left-click handling**: AppIndicator doesn't expose a direct left-click signal (it's DE-controlled — typically opens the menu). On GNOME with the appindicator extension, left-click opens the menu. The "Show Geary" menu item at the top provides window access. This is the standard AppIndicator UX.

### 3. VAPI Binding

**File**: `bindings/vapi/ayatana-appindicator3-0.1.vapi`

Minimal hand-written binding:

```vala
[CCode (cheader_filename = "libayatana-appindicator/app-indicator.h")]
namespace AppIndicator {
    [CCode (cname = "AppIndicatorCategory", cprefix = "APP_INDICATOR_CATEGORY_", has_type_id = false)]
    public enum IndicatorCategory {
        APPLICATION_STATUS,
        COMMUNICATIONS,
        SYSTEM_SERVICES,
        HARDWARE,
        OTHER
    }

    [CCode (cname = "AppIndicatorStatus", cprefix = "APP_INDICATOR_STATUS_", has_type_id = false)]
    public enum IndicatorStatus {
        PASSIVE,
        ACTIVE,
        ATTENTION
    }

    [CCode (cname = "AppIndicator", type_id = "app_indicator_get_type ()")]
    public class Indicator : GLib.Object {
        [CCode (cname = "app_indicator_new")]
        public Indicator (string id, string icon_name, IndicatorCategory category);
        [CCode (cname = "app_indicator_set_status")]
        public void set_status (IndicatorStatus status);
        [CCode (cname = "app_indicator_set_attention_icon_full")]
        public void set_attention_icon_full (string icon_name, string? icon_desc);
        [CCode (cname = "app_indicator_set_menu")]
        public void set_menu (Gtk.Menu menu);
        [CCode (cname = "app_indicator_set_title")]
        public void set_title (string title);
        [CCode (cname = "app_indicator_set_icon_full")]
        public void set_icon_full (string icon_name, string? icon_desc);
    }
}
```

This follows the project convention — `bindings/vapi/libpeas-2.vapi` is similarly hand-written. Only the API surface we actually use is bound.

### 4. Default-ON Configuration

**GSettings** (`desktop/org.gnome.Geary.gschema.xml`):
- Change `run-in-background` default from `false` to `true`

**Plugin autoload** (`src/client/application/application-plugin-manager.vala`):
- Add `"status-icon"` to the `AUTOLOAD_MODULES` array

No separate GSettings key for the tray icon — it's coupled to `run-in-background`. When that's off, the window close destroys normally and the tray icon plugin still runs but becomes less important (the app will quit when the last window is closed anyway). The tray icon remains visible while the app is running regardless.

### 5. Meson Build Integration

**Root `meson.build`**:
```meson
ayatana_appindicator = dependency('ayatana-appindicator3-0.1', required: false)
```

**`src/client/plugin/meson.build`**:
```meson
subdir('status-icon')
```

**`src/client/plugin/status-icon/meson.build`**:
```meson
plugin_name = 'status-icon'

if ayatana_appindicator.found()
  status_icon_dependencies = plugin_dependencies
  status_icon_dependencies += declare_dependency(
    dependencies: [
      valac.find_library(
        'ayatana-appindicator3-0.1',
        dirs: [meson.project_source_root() / 'bindings' / 'vapi']
      ),
      ayatana_appindicator,
    ]
  )

  plugin_src = files(plugin_name + '.vala')
  plugin_data = plugin_name + plugin_data_suffix
  plugin_dest = plugins_dir / plugin_name

  shared_module(
    plugin_name,
    sources: plugin_src,
    dependencies: status_icon_dependencies,
    vala_args: geary_vala_args,
    c_args: plugin_c_args,
    install: true,
    install_dir: plugin_dest,
    install_rpath: client_lib_dir,
  )

  custom_target(
    plugin_data,
    input: files(plugin_data + plugin_data_src_suffix),
    output: plugin_data,
    command: msgfmt_plugin_cmd,
    install: true,
    install_dir: plugin_dest
  )
endif
```

Follows the messaging-menu pattern: conditional on the library being available.

### 6. Plugin Metadata

**`src/client/plugin/status-icon/status-icon.plugin.in`**:
```ini
[Plugin]
Module=status-icon
Name=Status Icon
Description=Shows a system tray icon with unread mail indicator
Authors=ChatMail contributors
Copyright=Copyright © 2026
Builtin=true
Hidden=true
```

`Builtin=true` + `Hidden=true` makes it an internal autoloaded plugin (same as notification-badge).

## Files Modified

| File | Change |
|------|--------|
| `src/client/application/application-main-window.vala` | Hide instead of destroy on close when background service active |
| `src/client/application/application-plugin-manager.vala` | Add "status-icon" to AUTOLOAD_MODULES |
| `desktop/org.gnome.Geary.gschema.xml` | Change `run-in-background` default to `true` |
| `meson.build` | Add `ayatana-appindicator3-0.1` optional dependency |
| `src/client/plugin/meson.build` | Add `subdir('status-icon')` |

## Files Created

| File | Purpose |
|------|---------|
| `bindings/vapi/ayatana-appindicator3-0.1.vapi` | Vala binding for libayatana-appindicator3 |
| `src/client/plugin/status-icon/status-icon.vala` | Plugin implementation |
| `src/client/plugin/status-icon/status-icon.plugin.in` | Plugin metadata |
| `src/client/plugin/status-icon/meson.build` | Build rules |

## Verification

1. Install build dependency: `sudo apt install libayatana-appindicator3-dev`
2. `just rebuild` — compiles cleanly including new plugin
3. `just run` — verify:
   - Tray icon appears in system tray on launch
   - Close window (X) → window hides, tray icon remains
   - Right-click tray → menu with Show Geary / Compose / Quit
   - Click "Show Geary" → window reappears
   - Receive email → tray icon switches to attention state
   - Read email → tray icon returns to normal
   - Click "Quit" → app exits completely, tray icon disappears
4. `just test-engine` — existing engine tests still pass
5. Verify without library: remove `libayatana-appindicator3-dev`, `just rebuild` — builds without the plugin, no errors
