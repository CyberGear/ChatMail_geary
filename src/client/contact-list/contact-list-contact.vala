/*
 * Copyright 2026 the Geary contributors
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Data class wrapping contact information with fields needed for display.
 *
 * Provides display-oriented properties such as avatar colour and initials
 * that are derived deterministically from the underlying email address.
 */
internal class ContactList.Contact : GLib.Object {

    /** Fixed palette of eight pleasant avatar background colours. */
    private const string[] AVATAR_PALETTE = {
        "#E57373",  // red
        "#81C784",  // green
        "#64B5F6",  // blue
        "#FFB74D",  // orange
        "#BA68C8",  // purple
        "#4DB6AC",  // teal
        "#F06292",  // pink
        "#A1887F"   // brown
    };

    /** The RFC 822 address for this contact. */
    public Geary.RFC822.MailboxAddress rfc822_address { get; private set; }

    /** Human-readable display name. */
    public string display_name { get; private set; }

    /** Bare email address string. */
    public string email { get; private set; }

    /** Timestamp of the most recent email activity, or null if unknown. */
    public GLib.DateTime? last_activity { get; set; }

    /** Number of unread messages from this contact. */
    public uint unread_count { get; set; }

    /**
     * Hex colour string for the avatar background.
     *
     * Computed deterministically from the email address so the same
     * contact always receives the same colour.
     */
    public string avatar_color { get; private set; }

    public Contact(Geary.RFC822.MailboxAddress address,
                   string display_name,
                   GLib.DateTime? last_activity,
                   uint unread_count) {
        this.rfc822_address = address;
        this.display_name = display_name;
        this.email = address.address;
        this.last_activity = last_activity;
        this.unread_count = unread_count;
        this.avatar_color = compute_avatar_color(this.email);
    }

    /**
     * Returns up to two initial characters for avatar display.
     *
     * If a display name is available the initials are taken from the first
     * two words (e.g. "Jane Doe" -> "JD").  Otherwise the first character
     * of the email address is used.
     */
    public string get_initials() {
        if (!Geary.String.is_empty_or_whitespace(this.display_name)) {
            string[] parts = this.display_name.strip().split(" ");
            if (parts.length >= 2) {
                string first = parts[0].get_char(0).toupper().to_string();
                string second = parts[parts.length - 1].get_char(0).toupper().to_string();
                return first + second;
            }
            return parts[0].get_char(0).toupper().to_string();
        }

        if (!Geary.String.is_empty_or_whitespace(this.email)) {
            return this.email.get_char(0).toupper().to_string();
        }

        return "?";
    }

    /**
     * Picks a colour from the fixed palette based on a simple hash of the
     * email address.
     */
    private static string compute_avatar_color(string email) {
        uint hash = 0;
        for (int i = 0; i < email.length; i++) {
            hash = hash * 31 + (uint) email[i];
        }
        return AVATAR_PALETTE[hash % AVATAR_PALETTE.length];
    }
}
