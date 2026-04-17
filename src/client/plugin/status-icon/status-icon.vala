/*
 * Copyright © 2026 ChatMail contributors.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

[ModuleInit]
public void peas_register_types(TypeModule module) {
    Peas.ObjectModule obj = module as Peas.ObjectModule;
    obj.register_extension_type(
        typeof(Plugin.PluginBase),
        typeof(Plugin.StatusIcon)
    );
}

/** Shows a system tray icon with unread mail indicator. */
public class Plugin.StatusIcon :
    PluginBase, NotificationExtension, FolderExtension, TrustedExtension {


    private const Geary.Folder.SpecialUse[] MONITORED_TYPES = {
        INBOX, NONE
    };

    public NotificationContext notifications {
        get; set construct;
    }

    public FolderContext folders {
        get; set construct;
    }

    public global::Application.Client client_application {
        get; set construct;
    }

    public global::Application.PluginManager client_plugins {
        get; set construct;
    }

    private AppIndicator.Indicator? indicator = null;
    private Gtk.Menu? menu = null;
    private Gtk.MenuItem? show_item = null;


    public override async void activate(bool is_startup) throws GLib.Error {
        this.indicator = new AppIndicator.Indicator(
            Config.APP_ID,
            Config.APP_ID,
            AppIndicator.IndicatorCategory.COMMUNICATIONS
        );
        this.indicator.set_status(AppIndicator.IndicatorStatus.ACTIVE);
        this.indicator.set_title(global::Application.Client.NAME);
        this.indicator.set_attention_icon_full(
            Config.APP_ID, _("New mail received")
        );

        this.menu = new Gtk.Menu();

        this.show_item = new Gtk.MenuItem.with_label(
            _("Show Geary")
        );
        this.show_item.activate.connect(on_show_activate);
        this.menu.append(this.show_item);

        var compose_item = new Gtk.MenuItem.with_label(
            _("Compose New Message")
        );
        compose_item.activate.connect(on_compose_activate);
        this.menu.append(compose_item);

        this.menu.append(new Gtk.SeparatorMenuItem());

        var quit_item = new Gtk.MenuItem.with_label(
            _("Quit")
        );
        quit_item.activate.connect(on_quit_activate);
        this.menu.append(quit_item);

        this.menu.show_all();
        this.indicator.set_menu(this.menu);

        FolderStore folder_store = yield this.folders.get_folder_store();
        folder_store.folders_available.connect(
            (folders) => check_folders(folders)
        );
        folder_store.folders_unavailable.connect(
            (folders) => check_folders(folders)
        );
        folder_store.folders_type_changed.connect(
            (folders) => check_folders(folders)
        );
        check_folders(folder_store.get_folders());

        this.notifications.notify["total-new-messages"].connect(on_total_changed);
        update_status();
    }

    public override async void deactivate(bool is_shutdown) throws GLib.Error {
        this.notifications.notify["total-new-messages"].disconnect(
            on_total_changed
        );

        if (this.indicator != null) {
            this.indicator.set_status(AppIndicator.IndicatorStatus.PASSIVE);
            this.indicator = null;
        }

        this.menu = null;
        this.show_item = null;
    }

    private void check_folders(Gee.Collection<Folder> folders) {
        foreach (Folder folder in folders) {
            if (folder.used_as in MONITORED_TYPES) {
                this.notifications.start_monitoring_folder(folder);
            } else {
                this.notifications.stop_monitoring_folder(folder);
            }
        }
    }

    private void update_status() {
        if (this.indicator == null) {
            return;
        }

        int count = this.notifications.total_new_messages;
        if (count > 0) {
            this.indicator.set_status(AppIndicator.IndicatorStatus.ATTENTION);
            this.show_item.label = ngettext(
                "Show Geary (%d unread)",
                "Show Geary (%d unread)",
                count
            ).printf(count);
        } else {
            this.indicator.set_status(AppIndicator.IndicatorStatus.ACTIVE);
            this.show_item.label = _("Show Geary");
        }
    }

    private void on_total_changed() {
        update_status();
    }

    private void on_show_activate() {
        this.client_application.activate();
    }

    private void on_compose_activate() {
        this.client_application.activate_action(
            Action.Application.COMPOSE, null
        );
    }

    private void on_quit_activate() {
        this.client_application.activate_action(
            Action.Application.QUIT, null
        );
    }

}
