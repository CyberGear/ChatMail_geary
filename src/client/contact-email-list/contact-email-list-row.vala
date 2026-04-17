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
 * directional chevron band indicating whether the message was incoming
 * or outgoing relative to the account owner.
 *
 * Incoming: blue downward chevrons on the left edge.
 * Outgoing: green upward chevrons on the right edge.
 *
 * Subject is bold when the email is unread; normal weight when read.
 */
internal class ContactEmailList.Row : Gtk.ListBoxRow {

    private const int CHEVRON_WIDTH = 40;
    private const int NUM_CHEVRONS = 4;

    /** The email represented by this row. */
    public Geary.Email email { get; private set; }

    /** Whether this email was sent by the account owner. */
    public bool is_outgoing { get; private set; }

    private Gtk.Label subject_label;
    private Gtk.Label preview_label;
    private Gtk.Label date_label;

    internal Row(Geary.Email email, bool is_outgoing) {
        this.email = email;
        this.is_outgoing = is_outgoing;

        get_style_context().add_class("contact-email-row");

        build_ui();
        populate();
    }

    /** Marks this row as read — removes bold from subject. */
    public void mark_read() {
        string subject_text = "";
        if (this.email.subject != null) {
            subject_text = Util.Email.strip_subject_prefixes(this.email);
        }
        this.subject_label.set_text(subject_text);
        get_style_context().remove_class("unread");
    }

    private bool is_unread() {
        return this.email.email_flags != null &&
               this.email.email_flags.is_unread();
    }

    private void build_ui() {
        var overlay_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);

        // Chevron band on the left (incoming) or right (outgoing)
        var chevron_area = new Gtk.DrawingArea();
        chevron_area.set_size_request(CHEVRON_WIDTH, -1);
        chevron_area.vexpand = true;
        chevron_area.draw.connect(on_draw_chevrons);

        // Content area with padding
        var content = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
        content.margin_top = 12;
        content.margin_bottom = 12;
        content.margin_start = 10;
        content.margin_end = 10;
        content.hexpand = true;

        // Centre content: subject + preview
        var centre_vbox = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
        centre_vbox.hexpand = true;

        this.subject_label = new Gtk.Label(null);
        this.subject_label.xalign = 0;
        this.subject_label.ellipsize = Pango.EllipsizeMode.END;
        this.subject_label.max_width_chars = 1;
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

        content.pack_start(centre_vbox, true, true, 0);

        // Date on the right
        this.date_label = new Gtk.Label(null);
        this.date_label.xalign = 1.0f;
        this.date_label.valign = Gtk.Align.START;
        this.date_label.get_style_context().add_class("dim-label");
        content.pack_end(this.date_label, false, false, 0);

        if (this.is_outgoing) {
            overlay_box.pack_start(content, true, true, 0);
            overlay_box.pack_end(chevron_area, false, false, 0);
            get_style_context().add_class("direction-outgoing");
        } else {
            overlay_box.pack_start(chevron_area, false, false, 0);
            overlay_box.pack_start(content, true, true, 0);
            get_style_context().add_class("direction-incoming");
        }

        this.add(overlay_box);
        this.show_all();
    }

    private void populate() {
        // Subject — bold only if unread
        string subject_text = "";
        if (this.email.subject != null) {
            subject_text = Util.Email.strip_subject_prefixes(this.email);
        }
        if (is_unread()) {
            this.subject_label.set_markup(
                "<b>%s</b>".printf(GLib.Markup.escape_text(subject_text))
            );
            get_style_context().add_class("unread");
        } else {
            this.subject_label.set_text(subject_text);
        }

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
    }

    private bool on_draw_chevrons(Gtk.Widget widget, Cairo.Context cr) {
        int width = widget.get_allocated_width();
        int height = widget.get_allocated_height();

        // Chevron colour: blue for incoming, green for outgoing
        double r, g, b;
        if (this.is_outgoing) {
            // Green #7cc8a0
            r = 0.486; g = 0.784; b = 0.627;
        } else {
            // Blue #7cacf2
            r = 0.486; g = 0.675; b = 0.949;
        }

        // Draw stacked chevrons pointing down (incoming) or up (outgoing)
        double gap = 2.0;
        double usable = height - (NUM_CHEVRONS - 1) * gap;
        double chevron_h = usable / NUM_CHEVRONS;
        double cx = width / 2.0;
        double indent = width * 0.12;

        for (int i = 0; i < NUM_CHEVRONS; i++) {
            double top = i * (chevron_h + gap);
            double bot = top + chevron_h;
            double peak = chevron_h * 0.50;

            // Fade: strongest at the flow direction
            double alpha;
            if (this.is_outgoing) {
                alpha = 0.35 + 0.65 * (1.0 - (double) i / NUM_CHEVRONS);
            } else {
                alpha = 0.35 + 0.65 * ((double) i / NUM_CHEVRONS);
            }
            cr.set_source_rgba(r, g, b, alpha);

            if (this.is_outgoing) {
                // Upward-pointing chevron
                cr.move_to(indent, bot);
                cr.line_to(cx, bot - peak);
                cr.line_to(width - indent, bot);
                cr.line_to(width - indent, top + peak);
                cr.line_to(cx, top);
                cr.line_to(indent, top + peak);
            } else {
                // Downward-pointing chevron
                cr.move_to(indent, top);
                cr.line_to(cx, top + peak);
                cr.line_to(width - indent, top);
                cr.line_to(width - indent, bot - peak);
                cr.line_to(cx, bot);
                cr.line_to(indent, bot - peak);
            }
            cr.close_path();
            cr.fill();
        }

        return true;
    }
}
