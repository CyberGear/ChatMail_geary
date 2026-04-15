/*
 * Copyright 2026 the Geary contributors
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Holds a sorted list of {@link ContactList.Contact} objects for a single
 * account.
 *
 * Contacts are kept sorted by {@link Contact.last_activity} in descending
 * order (most recent first); contacts without a last_activity are placed at
 * the end.
 *
 * This is intentionally *not* a {@link GLib.ListModel} -- the owning
 * {@link ContactList.View} drives the {@link Gtk.ListBox} directly via
 * manual add/remove for simplicity.
 */
internal class ContactList.Model : GLib.Object {

    /** Number of contacts currently held. */
    public int size {
        get { return this.contacts.size; }
    }

    private Gee.ArrayList<Contact> contacts = new Gee.ArrayList<Contact>();

    public Model() {
    }

    /** Inserts a contact in sorted position. */
    public void add_contact(Contact contact) {
        this.contacts.add(contact);
        this.contacts.sort(compare_contacts);
    }

    /** Removes all contacts. */
    public void clear() {
        this.contacts.clear();
    }

    /** Returns the contact at the given index. */
    public Contact get_contact(int index) {
        return this.contacts.get(index);
    }

    /**
     * Returns a new model containing only contacts whose display name or
     * email address contains the given query (case-insensitive substring
     * match).
     */
    public Model filter(string query) {
        var result = new Model();
        string needle = query.down();

        foreach (var contact in this.contacts) {
            if (contact.display_name.down().contains(needle) ||
                contact.email.down().contains(needle)) {
                result.contacts.add(contact);
            }
        }
        // Already sorted since we iterate in order
        return result;
    }

    /**
     * Comparison function: descending by last_activity.
     *
     * Contacts with a null last_activity sort to the end.
     */
    private static int compare_contacts(Contact a, Contact b) {
        if (a.last_activity == null && b.last_activity == null) {
            return 0;
        }
        if (a.last_activity == null) {
            return 1;
        }
        if (b.last_activity == null) {
            return -1;
        }
        return b.last_activity.compare(a.last_activity);
    }
}
