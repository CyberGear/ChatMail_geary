/*
 * Copyright 2026 the Geary contributors
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A non-interactive header row that separates contacts by account.
 *
 * Displays the account email in uppercase, small, muted text.
 */
internal class ContactList.AccountHeader : Gtk.ListBoxRow {

    /** The account this header represents. */
    public Geary.Account account { get; private set; }

    public AccountHeader(Geary.Account account) {
        this.account = account;
        this.selectable = false;
        this.activatable = false;

        get_style_context().add_class("contact-list-account-header");

        var label = new Gtk.Label(null);
        label.xalign = 0;
        label.margin_start = 8;
        label.margin_end = 8;
        label.margin_top = 12;
        label.margin_bottom = 4;

        string account_email = account.information.primary_mailbox.address;
        label.set_markup(
            "<small>%s</small>".printf(
                GLib.Markup.escape_text(account_email.up())
            )
        );
        label.get_style_context().add_class("dim-label");

        this.add(label);
        this.show_all();
    }
}
