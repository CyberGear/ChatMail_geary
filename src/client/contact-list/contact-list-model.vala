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

    private Gee.HashSet<string> _account_emails = new Gee.HashSet<string>();

    public int size {
        get { return _contacts.size; }
    }

    public bool is_empty {
        get { return _contacts.size == 0; }
    }

    public void set_account_emails(Gee.Collection<string> emails) {
        _account_emails.clear();
        foreach (var email in emails) {
            string normalized = normalise_gmail_address(email);
            _account_emails.add(normalized);
        }
    }

    private static string normalise_gmail_address(string address) {
        string normalized = address.normalize().casefold();
        int at_pos = normalized.last_index_of("@");
        if (at_pos > 0) {
            string domain = normalized.substring(at_pos + 1);
            if (domain == "gmail.com" || domain == "googlemail.com") {
                int plus_pos = normalized.last_index_of("+");
                if (plus_pos > 0 && plus_pos > at_pos - 10) {
                    normalized = normalized.substring(0, plus_pos) + "@" + domain;
                }
            }
        }
        return normalized;
    }

    private bool is_account_email(string address) {
        string normalized = normalise_gmail_address(address);
        return _account_emails.contains(normalized);
    }

    public async void load_from_folder(Geary.Folder folder,
                                       Geary.Email.Field required_fields,
                                       GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        debug("Loading contacts from folder: %s", folder.path.to_string());
        
        var c = cancellable;
        if (c == null) {
            c = new GLib.Cancellable();
        }
        
        clear();

        int count = 100;
        var emails = yield folder.list_email_by_id_async(
            null,
            count,
            required_fields,
            Geary.Folder.ListFlags.OLDEST_TO_NEWEST,
            c
        );

        debug("Got %d emails from folder", emails != null ? emails.size : 0);

        if (emails == null || emails.size == 0) {
            return;
        }

        foreach (var email in emails) {
            add_email_contacts(email);
        }

        debug("Added contacts, total: %d", _contacts.size);
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
            debug("add_contact: empty address, skipping");
            return;
        }

        if (is_account_email(addr.address)) {
            debug("add_contact: %s is account email, skipping", addr.address);
            return;
        }

        var normalized = normalise_gmail_address(addr.address);
        debug("add_contact: normalized=%s, name=%s", normalized, addr.name);
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

    public async void load_from_account(Geary.Account account,
                                         GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        debug("load_from_account: starting for account %s", account.information.display_name);
        
        var c = cancellable;
        if (c == null) {
            c = new GLib.Cancellable();
        }
        
        clear();

        var required_fields = Geary.Email.Field.ORIGINATORS | Geary.Email.Field.RECEIVERS;

        var inbox = account.get_special_folder(Geary.Folder.SpecialUse.INBOX);
        debug("load_from_account: inbox=%p", inbox);
        if (inbox != null) {
            debug("Loading contacts from INBOX");
            yield load_folder_contacts(inbox, required_fields, c);
        } else {
            debug("No INBOX folder found!");
        }

        var sent = account.get_special_folder(Geary.Folder.SpecialUse.SENT);
        debug("load_from_account: sent=%p", sent);
        if (sent != null) {
            debug("Loading contacts from SENT");
            yield load_folder_contacts(sent, required_fields, c);
        } else {
            debug("No SENT folder found!");
        }

        debug("Loaded contacts, total: %d", _contacts.size);
    }

    private async void load_folder_contacts(Geary.Folder folder,
                                            Geary.Email.Field required_fields,
                                            GLib.Cancellable? cancellable)
        throws GLib.Error {
        debug("load_folder_contacts: folder=%s, state=%d", folder.path.to_string(), folder.get_open_state());
        
        var c = cancellable;
        if (c == null) {
            c = new GLib.Cancellable();
        }
        
        int count = 100;
        var emails = yield folder.list_email_by_id_async(
            null,
            count,
            required_fields,
            Geary.Folder.ListFlags.OLDEST_TO_NEWEST,
            c
        );

        debug("load_folder_contacts: got %d emails", emails != null ? emails.size : 0);
        if (emails != null) {
            foreach (var email in emails) {
                add_email_contacts(email);
            }
        }
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
