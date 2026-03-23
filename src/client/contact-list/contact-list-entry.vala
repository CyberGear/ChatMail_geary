/*
 * Copyright 2025 ChatMail Contributors
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class ContactListEntry : GLib.Object, Sidebar.Entry, Sidebar.SelectableEntry {

    private Geary.Contact contact;
    private int incoming_count;
    private int outgoing_count;

    public ContactListEntry(Geary.Contact contact,
                            int incoming_count,
                            int outgoing_count) {
        this.contact = contact;
        this.incoming_count = incoming_count;
        this.outgoing_count = outgoing_count;
    }

    public Geary.Contact get_contact() {
        return contact;
    }

    public void set_counts(int incoming, int outgoing) {
        this.incoming_count = incoming;
        this.outgoing_count = outgoing;
        entry_changed();
    }

    public override string get_sidebar_name() {
        if (contact.real_name != null && contact.real_name != "") {
            return contact.real_name;
        }
        return contact.email;
    }

    public override string? get_sidebar_tooltip() {
        string tooltip = contact.email;
        if (incoming_count > 0) {
            tooltip += "\n%d incoming".printf(incoming_count);
        }
        if (outgoing_count > 0) {
            tooltip += "\n%d outgoing".printf(outgoing_count);
        }
        return tooltip;
    }

    public override string? get_sidebar_icon() {
        return "avatar-default";
    }

    public override int get_count() {
        return incoming_count + outgoing_count;
    }

    public override string to_string() {
        return "ContactListEntry: %s".printf(contact.email);
    }
}
