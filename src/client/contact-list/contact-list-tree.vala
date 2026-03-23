/*
 * Copyright 2025 ChatMail Contributors
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class ContactList.Tree : Gtk.TreeView, Geary.BaseInterface {

    public const Gtk.TargetEntry[] TARGET_ENTRY_LIST = {
        { "application/x-geary-mail", Gtk.TargetFlags.SAME_APP, 0 }
    };

    public signal void contact_selected(Geary.Contact? contact);
    public signal void contact_activated(Geary.Contact? contact);

    public Geary.Contact? selected { get; private set; default = null; }

    private ContactListModel _model = new ContactListModel();
    private Geary.Folder? _current_folder = null;

    private Gtk.ListStore store = new Gtk.ListStore(
        3,
        typeof (string),    // NAME
        typeof (string?),   // EMAIL
        typeof (string?)    // TOOLTIP
    );

    private Gtk.TreeSelection? selection = null;

    public Tree() {
        set_model(store);
        base_ref();
        set_activate_on_single_click(true);
        
        var name_column = new Gtk.TreeViewColumn();
        name_column.title = "Contacts";
        
        var cell = new Gtk.CellRendererText();
        name_column.pack_start(cell, true);
        name_column.add_attribute(cell, "text", 0);
        
        append_column(name_column);
        
        selection = get_selection();
        selection.changed.connect(on_selection_changed);
        row_activated.connect(on_row_activated);

        this.visible = true;
    }

    ~Tree() {
        base_unref();
    }

    public override void get_preferred_width(out int minimum_size, out int natural_size) {
        minimum_size = 360;
        natural_size = 500;
    }

    private void on_selection_changed(Gtk.TreeSelection selection) {
        Gtk.TreeModel model;
        Gtk.TreeIter iter;
        
        if (selection.get_selected(out model, out iter)) {
            string? email = null;
            model.get(iter, 1, out email);
            
            if (email != null) {
                this.selected = _model.get_contact(Geary.Contact.normalise_email(email));
                contact_selected(this.selected);
            }
        } else {
            this.selected = null;
            contact_selected(null);
        }
    }

    private void on_row_activated(Gtk.TreePath path, Gtk.TreeViewColumn column) {
        Gtk.TreeModel model;
        Gtk.TreeIter iter;
        
        if (selection.get_selected(out model, out iter)) {
            string? email = null;
            model.get(iter, 1, out email);
            
            if (email != null) {
                this.selected = _model.get_contact(Geary.Contact.normalise_email(email));
                contact_activated(this.selected);
            }
        }
    }

    public async void load_from_folder(Geary.Folder folder,
                                       GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        _current_folder = folder;

        var required_fields = Geary.Email.Field.ORIGINATORS | Geary.Email.Field.RECEIVERS;
        yield _model.load_from_folder(folder, required_fields, cancellable);

        rebuild_tree();
    }

    private void rebuild_tree() {
        store.clear();

        foreach (var contact in _model.get_sorted()) {
            Gtk.TreeIter iter;
            store.append(out iter);
            
            string display_name = contact.real_name ?? contact.email;
            int count = _model.get_incoming_count(contact.normalized_email) + 
                       _model.get_outgoing_count(contact.normalized_email);
            
            store.set(iter,
                0, "%s (%d)".printf(display_name, count),
                1, contact.email,
                2, contact.email
            );
        }
    }

    public void clear() {
        store.clear();
        _model.clear();
        _current_folder = null;
        this.selected = null;
    }

    public ContactListModel get_contact_model() {
        return _model;
    }

    public Geary.Folder? get_current_folder() {
        return _current_folder;
    }
}
