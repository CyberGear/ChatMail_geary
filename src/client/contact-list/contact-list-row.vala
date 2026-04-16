/*
 * Copyright 2026 the Geary contributors
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A list-box row that displays a single contact.
 *
 * Layout: [Avatar circle 30x30] [Name (bold) / Email (dim)] [Unread badge]
 *
 * The UI is built in code rather than from a template file.
 */
internal class ContactList.Row : Gtk.ListBoxRow {

    private const int AVATAR_SIZE = 30;

    /** The contact data backing this row. */
    public ContactList.Contact contact { get; private set; }

    private Gtk.DrawingArea avatar;
    private Gtk.Label name_label;
    private Gtk.Label email_label;
    private Gtk.Label badge_label;

    public Row(ContactList.Contact contact) {
        this.contact = contact;

        get_style_context().add_class("contact-list-row");

        // Root horizontal box
        var hbox = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
        hbox.margin_start = 8;
        hbox.margin_end = 8;
        hbox.margin_top = 6;
        hbox.margin_bottom = 6;

        // Avatar drawing area
        this.avatar = new Gtk.DrawingArea();
        this.avatar.set_size_request(AVATAR_SIZE, AVATAR_SIZE);
        this.avatar.get_style_context().add_class("contact-avatar");
        this.avatar.draw.connect(on_draw_avatar);
        hbox.pack_start(this.avatar, false, false, 0);

        // Vertical box for name + email
        var vbox = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
        vbox.valign = Gtk.Align.CENTER;

        this.name_label = new Gtk.Label(null);
        this.name_label.xalign = 0;
        this.name_label.ellipsize = Pango.EllipsizeMode.END;
        this.name_label.get_style_context().add_class("contact-name");
        // Bold only if there are unread emails
        if (contact.unread_count > 0) {
            this.name_label.set_markup(
                "<b>%s</b>".printf(GLib.Markup.escape_text(contact.display_name))
            );
        } else {
            this.name_label.set_text(contact.display_name);
        }
        vbox.pack_start(this.name_label, false, false, 0);

        this.email_label = new Gtk.Label(contact.email);
        this.email_label.xalign = 0;
        this.email_label.ellipsize = Pango.EllipsizeMode.END;
        this.email_label.get_style_context().add_class("contact-email");
        this.email_label.get_style_context().add_class("dim-label");
        vbox.pack_start(this.email_label, false, false, 0);

        hbox.pack_start(vbox, true, true, 0);

        // Unread badge
        this.badge_label = new Gtk.Label(null);
        this.badge_label.get_style_context().add_class("contact-badge");
        this.badge_label.valign = Gtk.Align.CENTER;
        this.badge_label.no_show_all = true;
        update_badge();
        hbox.pack_end(this.badge_label, false, false, 0);

        this.add(hbox);
        this.show_all();
    }

    /** Updates the name label bold state based on unread count. */
    public void update_read_state() {
        if (this.contact.unread_count > 0) {
            this.name_label.set_markup(
                "<b>%s</b>".printf(GLib.Markup.escape_text(contact.display_name))
            );
        } else {
            this.name_label.set_text(contact.display_name);
        }
    }

    /** Refreshes the badge from the current contact state. */
    public void update_badge() {
        if (this.contact.total_count > 0) {
            this.badge_label.set_text(this.contact.total_count.to_string());
            this.badge_label.show();
        } else {
            this.badge_label.hide();
        }
    }

    /** Cairo draw handler for the circular avatar with initials. */
    private bool on_draw_avatar(Cairo.Context cr) {
        double cx = AVATAR_SIZE / 2.0;
        double cy = AVATAR_SIZE / 2.0;
        double radius = AVATAR_SIZE / 2.0;

        // Parse the hex colour
        Gdk.RGBA colour = Gdk.RGBA();
        colour.parse(this.contact.avatar_color);

        // Draw filled circle
        cr.arc(cx, cy, radius, 0, 2 * Math.PI);
        cr.set_source_rgba(colour.red, colour.green, colour.blue, 1.0);
        cr.fill();

        // Draw initials in white
        cr.set_source_rgb(1.0, 1.0, 1.0);
        var layout = Pango.cairo_create_layout(cr);
        var font_desc = Pango.FontDescription.from_string("Sans Bold 11");
        layout.set_font_description(font_desc);
        layout.set_text(this.contact.get_initials(), -1);

        int text_width, text_height;
        layout.get_pixel_size(out text_width, out text_height);

        cr.move_to(cx - text_width / 2.0, cy - text_height / 2.0);
        Pango.cairo_show_layout(cr, layout);

        return true;
    }
}
