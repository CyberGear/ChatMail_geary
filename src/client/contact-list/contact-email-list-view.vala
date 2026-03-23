/*
 * Copyright 2025 ChatMail Contributors
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class ContactEmailListView : Gtk.ScrolledWindow {

    public signal void email_selected(Geary.Email? email);
    public signal void email_activated(Geary.Email email, uint button);

    private Gtk.ListBox list_box;
    private ContactConversationListModel? model;

    public ContactEmailListView() {
        this.list_box = new Gtk.ListBox();
        this.list_box.selection_mode = Gtk.SelectionMode.SINGLE;
        this.list_box.row_selected.connect(on_row_selected);
        this.list_box.row_activated.connect(on_row_activated);
        
        this.list_box.visible = true;
        this.list_box.no_show_all = false;

        add(this.list_box);
        set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
        this.visible = true;
        this.no_show_all = false;
    }

    public void set_model(ContactConversationListModel model) {
        this.model = model;
        rebuild_list();
    }

    private void rebuild_list() {
        debug("ContactEmailListView: rebuild_list called, model=%s", model != null ? "yes" : "no");
        
        foreach (var child in list_box.get_children()) {
            child.destroy();
        }

        if (model == null) {
            debug("ContactEmailListView: model is null, showing placeholder");
            var placeholder = new Gtk.Label("Select a contact to see emails");
            list_box.add(placeholder);
            placeholder.show();
            return;
        }

        uint count = model.get_n_items();
        debug("ContactEmailListView: rebuilding with %u emails", count);
        
        for (uint i = 0; i < count; i++) {
            var email = model.get_item(i);
            if (email == null) {
                continue;
            }

            var row = create_row_for_email(email, model.is_outgoing(email));
            list_box.add(row);
        }
        
        list_box.show_all();
    }

    private Gtk.Widget create_row_for_email(Geary.Email email, bool is_outgoing) {
        var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);

        var from = "";
        if (email.from != null && email.from.size > 0) {
            from = email.from.get_all().first().to_short_display();
        }

        var subject = "";
        if (email.subject != null) {
            subject = email.subject.value;
        } else {
            subject = "(no subject)";
        }
        var date = "";
        if (email.date != null) {
            date = email.date.value.format("%Y-%m-%d");
        }

        var from_label = new Gtk.Label(from);
        from_label.halign = Gtk.Align.START;
        from_label.hexpand = true;

        var subject_label = new Gtk.Label(subject);
        subject_label.halign = Gtk.Align.START;
        subject_label.hexpand = true;

        var date_label = new Gtk.Label(date);
        date_label.halign = Gtk.Align.END;

        box.pack_start(from_label, true, true, 0);
        box.pack_start(subject_label, true, true, 0);
        box.pack_start(date_label, false, false, 0);

        if (is_outgoing) {
            box.margin_end = 4;
        } else {
            box.margin_start = 4;
        }

        box.show_all();
        return box;
    }

    private void on_row_selected(Gtk.ListBoxRow? row) {
        if (row == null || model == null) {
            email_selected(null);
            return;
        }

        uint index = row.get_index();
        var email = model.get_item(index);
        email_selected(email);
    }

    private void on_row_activated(Gtk.ListBox box, Gtk.ListBoxRow row) {
        if (model == null) {
            return;
        }

        uint index = row.get_index();
        var email = model.get_item(index);
        if (email != null) {
            email_activated(email, 0);
        }
    }

    public void refresh() {
        rebuild_list();
    }
}
