/*
 * Copyright 2026
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A list box row displaying a single email in the contact email list.
 *
 * Shows the email subject, a short preview snippet, the date, and a
 * directional arrow indicating whether the message was incoming or
 * outgoing relative to the account owner.
 */
internal class ContactEmailList.Row : Gtk.ListBoxRow {

    /** The email represented by this row. */
    public Geary.Email email { get; private set; }

    /** Whether this email was sent by the account owner. */
    public bool is_outgoing { get; private set; }

    private Gtk.Label left_arrow_label;
    private Gtk.Label subject_label;
    private Gtk.Label preview_label;
    private Gtk.Label date_label;
    private Gtk.Label right_arrow_label;

    internal Row(Geary.Email email, bool is_outgoing) {
        this.email = email;
        this.is_outgoing = is_outgoing;

        get_style_context().add_class("contact-email-row");

        build_ui();
        populate();
    }

    private void build_ui() {
        var hbox = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
        hbox.margin_top = 6;
        hbox.margin_bottom = 6;
        hbox.margin_start = 8;
        hbox.margin_end = 8;

        // Left arrow column -- fixed width for alignment
        this.left_arrow_label = new Gtk.Label(null);
        this.left_arrow_label.width_request = 16;
        this.left_arrow_label.xalign = 0.5f;
        this.left_arrow_label.valign = Gtk.Align.CENTER;
        hbox.pack_start(this.left_arrow_label, false, false, 0);

        // Centre content: subject + preview
        var centre_vbox = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);

        this.subject_label = new Gtk.Label(null);
        this.subject_label.xalign = 0;
        this.subject_label.ellipsize = Pango.EllipsizeMode.END;
        this.subject_label.max_width_chars = 1;  // let container decide
        this.subject_label.hexpand = true;
        centre_vbox.pack_start(this.subject_label, false, false, 0);

        this.preview_label = new Gtk.Label(null);
        this.preview_label.xalign = 0;
        this.preview_label.ellipsize = Pango.EllipsizeMode.END;
        this.preview_label.max_width_chars = 1;
        this.preview_label.lines = 1;
        this.preview_label.single_line_mode = true;
        this.preview_label.get_style_context().add_class("dim-label");
        centre_vbox.pack_start(this.preview_label, false, false, 0);

        hbox.pack_start(centre_vbox, true, true, 0);

        // Right side: date + arrow stacked vertically
        var right_vbox = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
        right_vbox.valign = Gtk.Align.CENTER;

        this.date_label = new Gtk.Label(null);
        this.date_label.xalign = 1.0f;
        this.date_label.get_style_context().add_class("dim-label");
        right_vbox.pack_start(this.date_label, false, false, 0);

        this.right_arrow_label = new Gtk.Label(null);
        this.right_arrow_label.width_request = 16;
        this.right_arrow_label.xalign = 1.0f;
        right_vbox.pack_start(this.right_arrow_label, false, false, 0);

        hbox.pack_end(right_vbox, false, false, 0);

        this.add(hbox);
        this.show_all();
    }

    private void populate() {
        // Subject (bold)
        string subject_text = "";
        if (this.email.subject != null) {
            subject_text = Util.Email.strip_subject_prefixes(this.email);
        }
        this.subject_label.set_markup(
            "<b>%s</b>".printf(GLib.Markup.escape_text(subject_text))
        );

        // Preview (small, dim)
        string preview_text = this.email.get_preview_as_string();
        this.preview_label.set_markup(
            "<small>%s</small>".printf(GLib.Markup.escape_text(preview_text))
        );

        // Date (small, muted)
        string date_text = "";
        if (this.email.date != null) {
            date_text = Util.Date.pretty_print(
                this.email.date.value,
                Util.Date.ClockFormat.LOCALE_DEFAULT
            );
        } else if (this.email.properties != null) {
            date_text = Util.Date.pretty_print(
                this.email.properties.date_received,
                Util.Date.ClockFormat.LOCALE_DEFAULT
            );
        }
        this.date_label.set_markup(
            "<small>%s</small>".printf(GLib.Markup.escape_text(date_text))
        );

        // Direction arrows and CSS classes
        if (this.is_outgoing) {
            this.left_arrow_label.set_text("");
            this.right_arrow_label.set_markup(
                "<span foreground=\"#7cc8a0\">\xe2\x86\x91</span>"
            );
            get_style_context().add_class("direction-outgoing");
        } else {
            this.left_arrow_label.set_markup(
                "<span foreground=\"#7cacf2\">\xe2\x86\x93</span>"
            );
            this.right_arrow_label.set_text("");
            get_style_context().add_class("direction-incoming");
        }
    }
}
