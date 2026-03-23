/*
 * Copyright 2025 ChatMail Contributors
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class ContactListModel : GLib.Object {

    private Gee.HashMap<string, Geary.Contact> _contacts =
        new Gee.HashMap<string, Geary.Contact>();

    private Gee.HashMap<string, int> _incoming_counts =
        new Gee.HashMap<string, int>();
    private Gee.HashMap<string, int> _outgoing_counts =
        new Gee.HashMap<string, int>();

    public int size {
        get { return _contacts.size; }
    }

    public bool is_empty {
        get { return _contacts.size == 0; }
    }

    public async void load_from_folder(Geary.Folder folder,
                                       Geary.Email.Field required_fields,
                                       GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        clear();

        int count = 100;
        var emails = yield folder.list_email_by_id_async(
            null,
            count,
            required_fields,
            Geary.Folder.ListFlags.OLDEST_TO_NEWEST,
            cancellable
        );

        if (emails == null || emails.size == 0) {
            return;
        }

        var account = folder.account;
        foreach (var email in emails) {
            add_email_contacts(email);
        }
    }

    public void add_email_contacts(Geary.Email email) {
        if (email.from != null) {
            foreach (var addr in email.from.get_all()) {
                add_contact(addr, Geary.Contact.Importance.RECEIVED_FROM, false);
            }
        }

        if (email.sender != null) {
            add_contact(email.sender, Geary.Contact.Importance.RECEIVED_FROM, false);
        }

        if (email.to != null) {
            foreach (var addr in email.to.get_all()) {
                add_contact(addr, Geary.Contact.Importance.SENT_TO, true);
            }
        }

        if (email.cc != null) {
            foreach (var addr in email.cc.get_all()) {
                add_contact(addr, Geary.Contact.Importance.SEEN, true);
            }
        }

        if (email.bcc != null) {
            foreach (var addr in email.bcc.get_all()) {
                add_contact(addr, Geary.Contact.Importance.SEEN, true);
            }
        }
    }

    private void add_contact(Geary.RFC822.MailboxAddress addr,
                             int importance,
                             bool is_outgoing) {
        if (addr.address == null || addr.address == "") {
            return;
        }

        var normalized = Geary.Contact.normalise_email(addr.address);
        var existing = _contacts.get(normalized);

        if (existing != null) {
            if (importance > existing.highest_importance) {
                existing.highest_importance = importance;
            }
            if (is_outgoing) {
                int existing_out = _outgoing_counts.get(normalized);
                _outgoing_counts.set(normalized, existing_out + 1);
            } else {
                int existing_in = _incoming_counts.get(normalized);
                _incoming_counts.set(normalized, existing_in + 1);
            }
        } else {
            string? name = addr.name;
            if (name != null && name.strip() == "") {
                name = null;
            }

            var contact = new Geary.Contact(addr.address, name, importance);

            _contacts.set(normalized, contact);

            if (is_outgoing) {
                _outgoing_counts[normalized] = 1;
                _incoming_counts[normalized] = 0;
            } else {
                _incoming_counts[normalized] = 1;
                _outgoing_counts[normalized] = 0;
            }
        }
    }

    public void clear() {
        _contacts.clear();
        _incoming_counts.clear();
        _outgoing_counts.clear();
    }

    public Gee.Collection<Geary.Contact> get_all() {
        return _contacts.values;
    }

    public Geary.Contact? get_contact(string normalized_email) {
        return _contacts.get(normalized_email);
    }

    public int get_incoming_count(string normalized_email) {
        int? count = _incoming_counts.get(normalized_email);
        return count != null ? count : 0;
    }

    public int get_outgoing_count(string normalized_email) {
        int? count = _outgoing_counts.get(normalized_email);
        return count != null ? count : 0;
    }

    public Gee.List<Geary.Contact> get_sorted() {
        var list = new Gee.ArrayList<Geary.Contact>();
        foreach (var contact in _contacts.values) {
            list.add(contact);
        }

        list.sort((a, b) => {
            if (a.highest_importance != b.highest_importance) {
                return b.highest_importance - a.highest_importance;
            }
            return strcmp(a.normalized_email, b.normalized_email);
        });

        return list;
    }

    public bool contains(Geary.Contact item) {
        return _contacts.has_key(item.normalized_email);
    }

    public bool add(Geary.Contact contact) {
        if (_contacts.has_key(contact.normalized_email)) {
            return false;
        }
        _contacts.set(contact.normalized_email, contact);
        _incoming_counts[contact.normalized_email] = 0;
        _outgoing_counts[contact.normalized_email] = 0;
        return true;
    }

    public bool remove(Geary.Contact contact) {
        bool removed = _contacts.unset(contact.normalized_email);
        if (removed) {
            _incoming_counts.unset(contact.normalized_email);
            _outgoing_counts.unset(contact.normalized_email);
        }
        return removed;
    }
}
