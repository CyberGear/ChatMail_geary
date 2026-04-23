/*
 * Copyright 2026 the Geary contributors
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Column 1 widget: displays a searchable, per-account contact list.
 *
 * Replaces the traditional folder sidebar with a list of contacts grouped
 * by account and sorted by most-recent email activity.
 */
internal class ContactList.View : Gtk.Box {

    /** Emitted when the user activates a contact row. */
    public signal void contact_selected(ContactList.Contact contact,
                                        Geary.Account account);

    private Gtk.SearchEntry search_entry;
    private Gtk.ListBox list_box;
    private Gtk.ScrolledWindow scrolled;

    /**
     * Per-account models keyed by the account object.
     *
     * The unfiltered models are kept so that search can be re-applied
     * without re-querying the contact store.
     */
    private Gee.HashMap<Geary.Account, Model> account_models =
        new Gee.HashMap<Geary.Account, Model>();

    /**
     * Maps each account to the set of rows (header + contact rows)
     * currently shown in the list box, so they can be cleanly removed.
     */
    private Gee.HashMap<Geary.Account, Gee.ArrayList<Gtk.ListBoxRow>> account_rows =
        new Gee.HashMap<Geary.Account, Gee.ArrayList<Gtk.ListBoxRow>>();

    public View() {
        Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        this.set_size_request(240, -1);
        this.get_style_context().add_class("contact-list-view");

        // Search entry
        this.search_entry = new Gtk.SearchEntry();
        this.search_entry.placeholder_text = _("Search contacts\u2026");
        this.search_entry.margin_start = 6;
        this.search_entry.margin_end = 6;
        this.search_entry.margin_top = 6;
        this.search_entry.margin_bottom = 6;
        this.search_entry.search_changed.connect(on_search_changed);
        this.pack_start(this.search_entry, false, false, 0);

        // Scrolled window containing the list box
        this.scrolled = new Gtk.ScrolledWindow(null, null);
        this.scrolled.hscrollbar_policy = Gtk.PolicyType.NEVER;
        this.scrolled.vscrollbar_policy = Gtk.PolicyType.AUTOMATIC;

        this.list_box = new Gtk.ListBox();
        this.list_box.selection_mode = Gtk.SelectionMode.SINGLE;
        this.list_box.row_activated.connect(on_row_activated);
        this.scrolled.add(this.list_box);

        this.pack_start(this.scrolled, true, true, 0);
        this.show_all();
    }

    /**
     * Decrements the unread count for the given contact email and
     * updates the row's bold state. Call this when an email from a
     * contact is marked as read.
     */
    public void decrement_unread(string contact_email) {
        string key = contact_email.down();
        foreach (var entry in this.account_rows.entries) {
            foreach (var gtk_row in entry.value) {
                var row = gtk_row as Row;
                if (row != null && row.contact.email.down() == key) {
                    if (row.contact.unread_count > 0) {
                        row.contact.unread_count--;
                    }
                    row.update_read_state();
                    return;
                }
            }
        }
    }

    /**
     * Adds an account and kicks off an asynchronous contact load.
     *
     * An empty model with just the account header is shown immediately;
     * contacts are filled in once the async query completes. Also
     * listens for new emails so the contact list refreshes as sync
     * progresses.
     */
    public void add_account(Geary.Account account) {
        var model = new Model();
        this.account_models.set(account, model);
        rebuild_rows_for_account(account, model);

        // Re-populate contacts when new emails arrive (sync in progress)
        account.email_appended.connect(() => {
            refresh_account.begin(account);
        });
        account.email_locally_complete.connect(() => {
            refresh_account.begin(account);
        });

        // Wait for the account to be fully opened before querying
        // contacts. The DB may not be ready immediately.
        account.opened.connect(() => {
            populate_account.begin(account, null);
        });
        // Also try now in case the account is already open
        if (account.is_open()) {
            populate_account.begin(account, null);
        } else {
            // Retry after a short delay
            GLib.Timeout.add(3000, () => {
                populate_account.begin(account, null);
                return GLib.Source.REMOVE;
            });
        }
    }

    /**
     * Refreshes contacts for an account, throttled to avoid
     * hammering the DB during rapid sync.
     */
    private Gee.HashSet<Geary.Account> refreshing =
        new Gee.HashSet<Geary.Account>();

    private async void refresh_account(Geary.Account account) {
        // Throttle: skip if already refreshing this account
        if (this.refreshing.contains(account)) {
            return;
        }
        this.refreshing.add(account);

        // Small delay to batch rapid signals during sync
        GLib.Timeout.add(2000, () => {
            this.refreshing.remove(account);
            populate_account.begin(account, null);
            return GLib.Source.REMOVE;
        });
    }

    /** Removes all rows belonging to the given account. */
    public void remove_account(Geary.Account account) {
        if (this.account_rows.has_key(account)) {
            foreach (var row in this.account_rows.get(account)) {
                this.list_box.remove(row);
            }
            this.account_rows.unset(account);
        }
        this.account_models.unset(account);
    }

    /**
     * Asynchronously populates contacts for an account.
     *
     * Loads contacts from the contact store and attempts to determine
     * the most recent email activity time for each contact by examining
     * the INBOX folder.
     */
    public async void populate_account(Geary.Account account,
                                       GLib.Cancellable? cancellable) {
        var model = new Model();

        // Use the SAME filter logic as the email list (column 2):
        //   Inbox: contact is the sender (from_field)
        //   Sent:  contact is a recipient (to_field)
        // This ensures contacts shown here will have emails when selected.
        GLib.File? data_dir = account.information.data_dir;
        if (data_dir == null) return;

        string db_path = data_dir.get_child("geary.db").get_path();
        string owner_email = account.information.primary_mailbox.address.down();

        // Find Inbox and Sent folder IDs
        int inbox_id = -1;
        int sent_id = -1;
        try {
            Sqlite.Database db;
            int rc = Sqlite.Database.open_v2(db_path, out db, Sqlite.OPEN_READONLY);
            if (rc != Sqlite.OK) return;

            // Find folder IDs by attributes
            Sqlite.Statement folder_stmt;
            rc = db.prepare_v2(
                "SELECT id, attributes FROM FolderTable", -1, out folder_stmt
            );
            if (rc == Sqlite.OK) {
                while (folder_stmt.step() == Sqlite.ROW) {
                    int fid = folder_stmt.column_int(0);
                    string attrs = folder_stmt.column_text(1) ?? "";
                    if ("\\HasNoChildren" in attrs || true) {
                        if (attrs.down().contains("inbox") ||
                            folder_stmt.column_text(1) == "\\HasNoChildren") {
                            // check by name
                        }
                    }
                }
            }
            // Simpler: find by name
            Sqlite.Statement name_stmt;
            rc = db.prepare_v2(
                "SELECT id, name, attributes FROM FolderTable", -1, out name_stmt
            );
            if (rc == Sqlite.OK) {
                while (name_stmt.step() == Sqlite.ROW) {
                    string name = name_stmt.column_text(1) ?? "";
                    string attrs = name_stmt.column_text(2) ?? "";
                    if (name == "INBOX") {
                        inbox_id = name_stmt.column_int(0);
                    } else if ("\\Sent" in attrs) {
                        sent_id = name_stmt.column_int(0);
                    }
                }
            }

            if (inbox_id < 0 && sent_id < 0) return;

            // Query contacts: from inbox senders + sent recipients.
            // Handles two RFC822 address formats in from_field/to_field:
            //   1. "Display Name <email@host>"  -> extract between < and >
            //   2. "email@host"                 -> the field is the address
            // Multi-recipient bare lists ("a@x, b@y") are skipped; mixed
            // formats are grouped by the final extracted email.
            string sql = """
                WITH inbox_senders AS (
                    SELECT LOWER(
                             CASE WHEN INSTR(m.from_field, '<') > 0
                                       AND INSTR(m.from_field, '>') > INSTR(m.from_field, '<')
                                  THEN SUBSTR(m.from_field,
                                              INSTR(m.from_field, '<') + 1,
                                              INSTR(m.from_field, '>') - INSTR(m.from_field, '<') - 1)
                                  ELSE TRIM(m.from_field)
                             END
                           ) as email,
                           m.date_time_t,
                           CASE WHEN (m.flags IS NULL OR m.flags = '' OR m.flags NOT LIKE '%%\Seen%%')
                                THEN 1 ELSE 0 END as is_unread
                    FROM MessageTable m
                    JOIN MessageLocationTable ml ON ml.message_id = m.id
                    WHERE ml.folder_id = ?1
                      AND m.from_field IS NOT NULL
                      AND m.from_field LIKE '%%@%%'
                      AND (m.from_field LIKE '%%<%%>%%' OR m.from_field NOT LIKE '%%,%%')
                      AND m.date_time_t > 0
                ),
                sent_recipients AS (
                    SELECT LOWER(
                             CASE WHEN INSTR(m.to_field, '<') > 0
                                       AND INSTR(m.to_field, '>') > INSTR(m.to_field, '<')
                                  THEN SUBSTR(m.to_field,
                                              INSTR(m.to_field, '<') + 1,
                                              INSTR(m.to_field, '>') - INSTR(m.to_field, '<') - 1)
                                  ELSE TRIM(m.to_field)
                             END
                           ) as email,
                           m.date_time_t,
                           0 as is_unread
                    FROM MessageTable m
                    JOIN MessageLocationTable ml ON ml.message_id = m.id
                    WHERE ml.folder_id = ?2
                      AND m.to_field IS NOT NULL
                      AND m.to_field LIKE '%%@%%'
                      AND (m.to_field LIKE '%%<%%>%%' OR m.to_field NOT LIKE '%%,%%')
                      AND m.date_time_t > 0
                ),
                all_emails AS (
                    SELECT email, date_time_t, is_unread FROM inbox_senders
                    UNION ALL
                    SELECT email, date_time_t, is_unread FROM sent_recipients
                )
                SELECT a.email,
                       MAX(a.date_time_t) as last_date,
                       COUNT(*) as total_cnt,
                       SUM(a.is_unread) as unread_cnt,
                       c.real_name
                FROM all_emails a
                LEFT JOIN ContactTable c ON LOWER(c.email) = a.email
                WHERE a.email != '' AND a.email != ?3
                GROUP BY a.email
                ORDER BY last_date DESC
                LIMIT 500
            """;

            Sqlite.Statement stmt;
            rc = db.prepare_v2(sql, -1, out stmt);
            if (rc == Sqlite.OK) {
                stmt.bind_int(1, inbox_id);
                stmt.bind_int(2, sent_id);
                stmt.bind_text(3, owner_email);

                while (stmt.step() == Sqlite.ROW) {
                    string email = stmt.column_text(0);
                    int64 ts = stmt.column_int64(1);
                    int total = stmt.column_int(2);
                    int unread = stmt.column_int(3);
                    string? real_name = stmt.column_text(4);

                    if (email == null || email.length == 0) continue;

                    string display = (real_name != null && real_name.length > 0)
                        ? real_name : email;
                    var addr = new Geary.RFC822.MailboxAddress(display, email);
                    var last_activity = new DateTime.from_unix_local(ts);
                    var contact = new Contact(
                        addr, display, last_activity,
                        (uint) total, (uint) unread
                    );
                    model.add_contact(contact);
                }
            }
        } catch (GLib.Error e) {
            warning("ContactList: DB error: %s", e.message);
        }

        warning("ContactList: model has %d contacts", model.size);

        this.account_models.set(account, model);
        rebuild_rows_for_account(account, model);
    }

    // -------
    //  Private helpers
    // -------

    /**
     * Clears any existing rows for the account and rebuilds them from
     * the given model.
     */
    private void rebuild_rows_for_account(Geary.Account account,
                                          Model model) {
        // Remove old rows if present
        if (this.account_rows.has_key(account)) {
            foreach (var old_row in this.account_rows.get(account)) {
                this.list_box.remove(old_row);
            }
        }

        var rows = new Gee.ArrayList<Gtk.ListBoxRow>();

        // Account header
        var header = new AccountHeader(account);
        header.show_all();
        this.list_box.add(header);
        rows.add(header);

        // Contact rows
        for (int i = 0; i < model.size; i++) {
            var contact = model.get_contact(i);
            var row = new Row(contact);
            row.show_all();
            this.list_box.add(row);
            rows.add(row);
        }

        this.account_rows.set(account, rows);
        this.list_box.show_all();
    }

    /** Rebuilds visible rows for all accounts based on the current search query. */
    private void on_search_changed() {
        string query = this.search_entry.text.strip();

        foreach (var entry in this.account_models.entries) {
            Geary.Account account = entry.key;
            Model source_model = entry.value;

            Model display_model;
            if (query.length == 0) {
                display_model = source_model;
            } else {
                display_model = source_model.filter(query);
            }

            rebuild_rows_for_account(account, display_model);
        }
    }

    /** Handles row activation by emitting the contact_selected signal. */
    private void on_row_activated(Gtk.ListBoxRow row) {
        var contact_row = row as Row;
        if (contact_row == null) {
            return;
        }

        // Determine which account this row belongs to
        foreach (var entry in this.account_rows.entries) {
            if (entry.value.contains(row)) {
                contact_selected(contact_row.contact, entry.key);
                return;
            }
        }
    }
}
