/*
 * Copyright 2026
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Column 2 widget showing emails filtered by a selected contact.
 *
 * Replaces the traditional conversation list with a flat, chronologically
 * sorted email list for a single contact.  Each row shows subject,
 * preview, date, and a direction arrow (incoming / outgoing).
 */
internal class ContactEmailList.View : Gtk.Box {

    /** The required email fields for listing. */
    public const Geary.Email.Field REQUIRED_FIELDS = (
        Geary.Email.Field.ENVELOPE |
        Geary.Email.Field.PREVIEW |
        Geary.Email.Field.FLAGS
    );

    /** Emitted when the user activates (clicks) an email row. */
    public signal void email_selected(Geary.Email email);

    // Header widgets
    private Gtk.Box header_box;
    private Gtk.DrawingArea avatar_circle;
    private Gtk.Label contact_name_label;
    private Gtk.Label email_count_label;

    // List
    private Gtk.ScrolledWindow scrolled_window;
    private Gtk.ListBox list_box;

    // State
    private ContactList.Contact? current_contact = null;
    private string current_avatar_color = "#888888";
    private string current_initials = "?";
    private GLib.Cancellable? load_cancellable = null;

    internal View() {
        Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);

        build_header();
        build_list();

        this.show_all();
    }

    // -------------------------------------------------------------------
    //  Public API
    // -------------------------------------------------------------------

    /**
     * Sets the active contact and loads their emails.
     *
     * Passing null clears the view.
     */
    /** Returns the currently selected email row, if any. */
    public ContactEmailList.Row? get_selected_row() {
        var row = this.list_box.get_selected_row();
        return row as ContactEmailList.Row;
    }

    public void set_contact(ContactList.Contact? contact,
                            Geary.Account? account) {
        clear();

        if (contact == null || account == null) {
            return;
        }

        this.current_contact = contact;
        this.current_avatar_color = contact.avatar_color;
        this.current_initials = contact.get_initials();

        this.contact_name_label.set_text(contact.display_name);
        this.avatar_circle.queue_draw();

        // Cancel any previous in-flight load
        if (this.load_cancellable != null) {
            this.load_cancellable.cancel();
        }
        this.load_cancellable = new GLib.Cancellable();

        this.load_emails.begin(
            contact, account, this.load_cancellable
        );
    }

    /**
     * Removes all rows, resets header to empty state.
     */
    public void clear() {
        if (this.load_cancellable != null) {
            this.load_cancellable.cancel();
            this.load_cancellable = null;
        }

        this.current_contact = null;
        this.current_avatar_color = "#888888";
        this.current_initials = "?";

        this.list_box.foreach((child) => {
            child.destroy();
        });

        this.contact_name_label.set_text("");
        this.email_count_label.set_text("");
        this.avatar_circle.queue_draw();
    }

    // -------------------------------------------------------------------
    //  Email loading
    // -------------------------------------------------------------------

    /**
     * Fetches emails from Inbox and Sent that match the given contact
     * by querying the local SQLite DB directly (same source as column 1),
     * then batch-fetches full Email objects via account.list_local_email_async.
     */
    internal async void load_emails(ContactList.Contact contact,
                                    Geary.Account account,
                                    GLib.Cancellable? cancellable) {
        GLib.File? data_dir = account.information.data_dir;
        if (data_dir == null) return;

        string db_path = data_dir.get_child("geary.db").get_path();
        string contact_email = contact.rfc822_address.address.down();

        // Find folder IDs for Inbox and Sent
        int inbox_id = -1;
        int sent_id = -1;
        var msg_ids = new Gee.ArrayList<int64?>();
        // HashMap<int64?, …> needs explicit value-based hash/equal — the
        // default compares boxed references, so lookups never match.
        var direction_map = new Gee.HashMap<int64?, bool>(
            (k) => GLib.int64_hash(k),
            (a, b) => GLib.int64_equal(a, b)
        );

        try {
            Sqlite.Database db;
            int rc = Sqlite.Database.open_v2(db_path, out db, Sqlite.OPEN_READONLY);
            if (rc != Sqlite.OK) return;

            Sqlite.Statement folder_stmt;
            rc = db.prepare_v2(
                "SELECT id, name, attributes FROM FolderTable", -1, out folder_stmt
            );
            if (rc == Sqlite.OK) {
                while (folder_stmt.step() == Sqlite.ROW) {
                    string name = folder_stmt.column_text(1) ?? "";
                    string attrs = folder_stmt.column_text(2) ?? "";
                    if (name == "INBOX") {
                        inbox_id = folder_stmt.column_int(0);
                    } else if ("\\Sent" in attrs) {
                        sent_id = folder_stmt.column_int(0);
                    }
                }
            }

            if (inbox_id < 0 && sent_id < 0) return;

            // INSTR catches both "<email>" and bare "email" formats.
            // A post-fetch check with email_matches_contact rejects
            // substring false positives.
            if (inbox_id >= 0) {
                Sqlite.Statement inbox_stmt;
                rc = db.prepare_v2("""
                    SELECT m.id FROM MessageTable m
                    JOIN MessageLocationTable ml ON ml.message_id = m.id
                    WHERE ml.folder_id = ?1
                      AND INSTR(LOWER(m.from_field), ?2) > 0
                      AND m.date_time_t > 0
                """, -1, out inbox_stmt);
                if (rc == Sqlite.OK) {
                    inbox_stmt.bind_int(1, inbox_id);
                    inbox_stmt.bind_text(2, contact_email);
                    while (inbox_stmt.step() == Sqlite.ROW) {
                        int64 mid = inbox_stmt.column_int64(0);
                        msg_ids.add(mid);
                        direction_map.set(mid, false);
                    }
                }
            }

            if (sent_id >= 0) {
                Sqlite.Statement sent_stmt;
                rc = db.prepare_v2("""
                    SELECT m.id FROM MessageTable m
                    JOIN MessageLocationTable ml ON ml.message_id = m.id
                    WHERE ml.folder_id = ?1
                      AND (INSTR(LOWER(m.to_field), ?2) > 0
                           OR INSTR(LOWER(m.cc), ?2) > 0
                           OR INSTR(LOWER(m.bcc), ?2) > 0)
                      AND m.date_time_t > 0
                """, -1, out sent_stmt);
                if (rc == Sqlite.OK) {
                    sent_stmt.bind_int(1, sent_id);
                    sent_stmt.bind_text(2, contact_email);
                    while (sent_stmt.step() == Sqlite.ROW) {
                        int64 mid = sent_stmt.column_int64(0);
                        msg_ids.add(mid);
                        direction_map.set(mid, true);
                    }
                }
            }
        } catch (GLib.Error err) {
            debug("ContactEmailList: SQLite query failed: %s", err.message);
            return;
        }

        if (msg_ids.size == 0 || (cancellable != null && cancellable.is_cancelled())) {
            return;
        }

        // Convert SQLite message_ids to Geary EmailIdentifiers via variant
        var email_ids = new Gee.ArrayList<Geary.EmailIdentifier>();
        foreach (int64? mid in msg_ids) {
            try {
                // ImapDB.EmailIdentifier variant format: (y(xx)) = ('i', (message_id, uid))
                // uid = -1 means unknown UID
                var variant = new GLib.Variant.tuple(new GLib.Variant[] {
                    new GLib.Variant.byte('i'),
                    new GLib.Variant.tuple(new GLib.Variant[] {
                        new GLib.Variant.int64(mid),
                        new GLib.Variant.int64(-1)
                    })
                });
                email_ids.add(account.to_email_identifier(variant));
            } catch (GLib.Error err) {
                debug("Failed to create email id for message %lld: %s",
                      mid, err.message);
            }
        }

        if (email_ids.size == 0) return;

        // Batch-fetch all Email objects from local DB
        Gee.List<Geary.Email>? emails = null;
        try {
            emails = yield account.list_local_email_async(
                email_ids, REQUIRED_FIELDS, cancellable
            );
        } catch (GLib.Error err) {
            debug("ContactEmailList: failed to fetch emails: %s", err.message);
            return;
        }

        if (emails == null || (cancellable != null && cancellable.is_cancelled())) {
            return;
        }

        // Build direction-aware list and sort
        var all_emails = new Gee.ArrayList<EmailWithDirection>();
        foreach (Geary.Email email in emails) {
            if (!email_matches_contact(email, contact)) continue;
            // Recover the message_id from the variant to look up direction
            int64 mid = email.id.to_variant().get_child_value(1)
                            .get_child_value(0).get_int64();
            bool outgoing = direction_map.has_key(mid)
                ? direction_map.get(mid) : false;
            all_emails.add(new EmailWithDirection(email, outgoing));
        }

        all_emails.sort((a, b_item) => {
            return compare_email_date_desc(a.email, b_item.email);
        });

        // Populate rows
        int count = 0;
        foreach (var item in all_emails) {
            if (cancellable != null && cancellable.is_cancelled()) return;
            var row = new ContactEmailList.Row(item.email, item.outgoing);
            this.list_box.add(row);
            count++;
        }

        this.email_count_label.set_text(
            ngettext("%d email", "%d emails", (ulong) count).printf(count)
        );
    }

    // -------------------------------------------------------------------
    //  Matching / direction helpers
    // -------------------------------------------------------------------

    /**
     * Checks whether any address in the email (from, to, cc, bcc)
     * matches the contact's address.
     */
    private static bool email_matches_contact(Geary.Email email,
                                              ContactList.Contact contact) {
        Geary.RFC822.MailboxAddress addr = contact.rfc822_address;
        return address_list_contains(email.from, addr) ||
               address_list_contains(email.to, addr) ||
               address_list_contains(email.cc, addr) ||
               address_list_contains(email.bcc, addr);
    }

    private static bool address_list_contains(
        Geary.RFC822.MailboxAddresses? addresses,
        Geary.RFC822.MailboxAddress target
    ) {
        if (addresses == null) {
            return false;
        }
        foreach (Geary.RFC822.MailboxAddress addr in addresses.get_all()) {
            if (addr.equal_to(target)) {
                return true;
            }
        }
        return false;
    }

    /**
     * An email is outgoing if any of its ``from`` addresses belongs
     * to the account owner's sender mailboxes.
     */
    private static bool is_email_outgoing(Geary.Email email,
                                          Geary.AccountInformation info) {
        if (email.from == null) {
            return false;
        }
        foreach (Geary.RFC822.MailboxAddress from_addr in email.from.get_all()) {
            if (info.has_sender_mailbox(from_addr)) {
                return true;
            }
        }
        return false;
    }

    /**
     * Compare two emails by date descending (newest first).
     *
     * Falls back to date_received when the envelope date is absent.
     */
    private static int compare_email_date_desc(Geary.Email a,
                                               Geary.Email b) {
        GLib.DateTime? da = get_sort_date(a);
        GLib.DateTime? db = get_sort_date(b);

        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;

        // Descending: newer first
        return db.compare(da);
    }

    private static GLib.DateTime? get_sort_date(Geary.Email email) {
        if (email.date != null) {
            return email.date.value;
        }
        if (email.properties != null) {
            return email.properties.date_received;
        }
        return null;
    }

    // -------------------------------------------------------------------
    //  UI construction
    // -------------------------------------------------------------------

    private void build_header() {
        this.header_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 10);
        this.header_box.margin_top = 12;
        this.header_box.margin_bottom = 8;
        this.header_box.margin_start = 12;
        this.header_box.margin_end = 12;

        // Small avatar circle
        this.avatar_circle = new Gtk.DrawingArea();
        this.avatar_circle.set_size_request(36, 36);
        this.avatar_circle.draw.connect(on_draw_avatar);
        this.header_box.pack_start(this.avatar_circle, false, false, 0);

        // Name + count stacked
        var info_vbox = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
        info_vbox.valign = Gtk.Align.CENTER;

        this.contact_name_label = new Gtk.Label(null);
        this.contact_name_label.xalign = 0;
        this.contact_name_label.ellipsize = Pango.EllipsizeMode.END;
        this.contact_name_label.get_style_context().add_class("title");
        info_vbox.pack_start(this.contact_name_label, false, false, 0);

        this.email_count_label = new Gtk.Label(null);
        this.email_count_label.xalign = 0;
        this.email_count_label.get_style_context().add_class("dim-label");
        info_vbox.pack_start(this.email_count_label, false, false, 0);

        this.header_box.pack_start(info_vbox, true, true, 0);

        this.pack_start(this.header_box, false, false, 0);

        // Separator below header
        var sep = new Gtk.Separator(Gtk.Orientation.HORIZONTAL);
        this.pack_start(sep, false, false, 0);
    }

    private void build_list() {
        this.scrolled_window = new Gtk.ScrolledWindow(null, null);
        this.scrolled_window.hscrollbar_policy = Gtk.PolicyType.NEVER;
        this.scrolled_window.vscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
        this.scrolled_window.vexpand = true;

        this.list_box = new Gtk.ListBox();
        this.list_box.selection_mode = Gtk.SelectionMode.SINGLE;
        this.list_box.row_activated.connect(on_row_activated);
        this.list_box.set_header_func(list_header_func);

        this.scrolled_window.add(this.list_box);
        this.pack_start(this.scrolled_window, true, true, 0);
    }

    // -------------------------------------------------------------------
    //  Callbacks
    // -------------------------------------------------------------------

    private void on_row_activated(Gtk.ListBoxRow row) {
        var email_row = row as ContactEmailList.Row;
        if (email_row != null) {
            email_selected(email_row.email);
        }
    }

    private static void list_header_func(Gtk.ListBoxRow row,
                                         Gtk.ListBoxRow? before) {
        if (before != null) {
            var sep = new Gtk.Separator(Gtk.Orientation.HORIZONTAL);
            sep.show();
            row.set_header(sep);
        }
    }

    /**
     * Draws a small coloured circle with the contact's initials.
     */
    private bool on_draw_avatar(Gtk.Widget widget, Cairo.Context cr) {
        int width = widget.get_allocated_width();
        int height = widget.get_allocated_height();
        double radius = double.min(width, height) / 2.0;
        double cx = width / 2.0;
        double cy = height / 2.0;

        // Parse colour
        Gdk.RGBA colour = Gdk.RGBA();
        colour.parse(this.current_avatar_color);

        // Filled circle
        cr.arc(cx, cy, radius, 0, 2 * Math.PI);
        cr.set_source_rgba(colour.red, colour.green, colour.blue, 1.0);
        cr.fill();

        // Initials text
        cr.set_source_rgba(1.0, 1.0, 1.0, 1.0);
        cr.select_font_face("Sans",
                            Cairo.FontSlant.NORMAL,
                            Cairo.FontWeight.BOLD);
        cr.set_font_size(radius * 0.85);

        Cairo.TextExtents extents;
        cr.text_extents(this.current_initials, out extents);
        cr.move_to(
            cx - extents.width / 2.0 - extents.x_bearing,
            cy - extents.height / 2.0 - extents.y_bearing
        );
        cr.show_text(this.current_initials);

        return true;
    }

    // -------------------------------------------------------------------
    //  Private helper class
    // -------------------------------------------------------------------

    /**
     * Pairs an email with its computed direction flag for sorting
     * before row creation.
     */
    private class EmailWithDirection : GLib.Object {
        public Geary.Email email { get; private set; }
        public bool outgoing { get; private set; }

        public EmailWithDirection(Geary.Email email, bool outgoing) {
            this.email = email;
            this.outgoing = outgoing;
        }
    }
}
