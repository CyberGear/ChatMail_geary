/*
 * Copyright 2025 ChatMail Contributors
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class ContactConversationListModel : GLib.Object {

    public signal void emails_loaded();

    private GLib.GenericArray<Geary.Email> _emails = new GLib.GenericArray<Geary.Email>();
    private Geary.Contact? _selected_contact = null;
    private Geary.Account? _account = null;
    private GLib.Cancellable? _cancellable = null;
    private bool _loading = false;

    public int size {
        get { return (int) _emails.length; }
    }

    public ContactConversationListModel() {
    }

    public async void load_from_account(Geary.Account account,
                                         GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        if (_loading) {
            return;
        }

        _loading = true;
        _account = account;
        _cancellable = cancellable;
        _emails = new GLib.GenericArray<Geary.Email>();

        var inbox = account.get_special_folder(Geary.Folder.SpecialUse.INBOX);
        var sent = account.get_special_folder(Geary.Folder.SpecialUse.SENT);

        yield load_folder_emails(inbox, cancellable);
        yield load_folder_emails(sent, cancellable);

        sort_emails();
        
        _loading = false;
        emails_loaded();
    }

    private async void load_folder_emails(Geary.Folder? folder,
                                          GLib.Cancellable? cancellable)
        throws GLib.Error {
        if (folder == null) {
            return;
        }

        bool opened = yield folder.open_async(Geary.Folder.OpenFlags.NONE, cancellable);
        if (!opened) {
            return;
        }

        int count = 100;
        var required_fields = Geary.Email.Field.ORIGINATORS |
                             Geary.Email.Field.RECEIVERS |
                             Geary.Email.Field.DATE |
                             Geary.Email.Field.SUBJECT;

        var emails = yield folder.list_email_by_id_async(
            null,
            count,
            required_fields,
            Geary.Folder.ListFlags.NONE,
            cancellable
        );

        if (emails != null) {
            foreach (var email in emails) {
                _emails.add(email);
            }
        }

        yield folder.close_async(cancellable);
    }

    private void sort_emails() {
        var sorted = new GLib.GenericArray<Geary.Email>();
        
        for (int i = 0; i < _emails.length; i++) {
            sorted.add(_emails[i]);
        }

        sorted.sort((a, b) => {
            var date_a = a.date;
            var date_b = b.date;
            
            if (date_a == null && date_b == null) return 0;
            if (date_a == null) return 1;
            if (date_b == null) return -1;
            
            return date_b.value.compare(date_a.value);
        });

        _emails = sorted;
    }

    public void set_filter_contact(Geary.Contact? contact) {
        _selected_contact = contact;
    }

    public Geary.Contact? get_filter_contact() {
        return _selected_contact;
    }

    public bool matches_filter(Geary.Email email) {
        if (_selected_contact == null) {
            return true;
        }

        string normalized = _selected_contact.normalized_email;

        if (email.from != null) {
            foreach (var addr in email.from.get_all()) {
                if (Geary.Contact.normalise_email(addr.address) == normalized) {
                    return true;
                }
            }
        }

        if (email.to != null) {
            foreach (var addr in email.to.get_all()) {
                if (Geary.Contact.normalise_email(addr.address) == normalized) {
                    return true;
                }
            }
        }

        if (email.cc != null) {
            foreach (var addr in email.cc.get_all()) {
                if (Geary.Contact.normalise_email(addr.address) == normalized) {
                    return true;
                }
            }
        }

        return false;
    }

    public bool is_outgoing(Geary.Email email) {
        if (_account == null) {
            return false;
        }

        var sent_folder = _account.get_special_folder(Geary.Folder.SpecialUse.SENT);
        var outbox_folder = _account.get_special_folder(Geary.Folder.SpecialUse.OUTBOX);

        if (sent_folder != null || outbox_folder != null) {
            return true;
        }

        return false;
    }

    public new Geary.Email? get_item(uint position) {
        if (position >= _emails.length) {
            return null;
        }
        return _emails[position];
    }

    public uint get_n_items() {
        return _emails.length;
    }

    public GLib.Type get_item_type() {
        return typeof(Geary.Email);
    }

    public void clear() {
        _emails = new GLib.GenericArray<Geary.Email>();
        _selected_contact = null;
        _account = null;
    }
}
