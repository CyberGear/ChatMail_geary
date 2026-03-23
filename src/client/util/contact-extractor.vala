/*
 * Copyright 2025 ChatMail Contributors
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class ContactExtractor : GLib.Object {

    public static Geary.Contact? extract_from_address(Geary.RFC822.MailboxAddress addr,
                                                      int importance) {
        if (addr.address == null || addr.address == "") {
            return null;
        }

        string? name = addr.name;
        if (name != null && name.strip() == "") {
            name = null;
        }

        return new Geary.Contact(addr.address, name, importance);
    }

    public static void extract_from_email(Geary.Email email,
                                          Gee.Set<Geary.Contact> contacts) {
        if (email.from != null) {
            foreach (var addr in email.from.get_all()) {
                var contact = extract_from_address(addr, Geary.Contact.Importance.RECEIVED_FROM);
                if (contact != null) {
                    contacts.add(contact);
                }
            }
        }

        if (email.sender != null) {
            var contact = extract_from_address(email.sender, Geary.Contact.Importance.RECEIVED_FROM);
            if (contact != null) {
                contacts.add(contact);
            }
        }

        if (email.to != null) {
            foreach (var addr in email.to.get_all()) {
                var contact = extract_from_address(addr, Geary.Contact.Importance.SENT_TO);
                if (contact != null) {
                    contacts.add(contact);
                }
            }
        }

        if (email.cc != null) {
            foreach (var addr in email.cc.get_all()) {
                var contact = extract_from_address(addr, Geary.Contact.Importance.SEEN);
                if (contact != null) {
                    contacts.add(contact);
                }
            }
        }

        if (email.bcc != null) {
            foreach (var addr in email.bcc.get_all()) {
                var contact = extract_from_address(addr, Geary.Contact.Importance.SEEN);
                if (contact != null) {
                    contacts.add(contact);
                }
            }
        }
    }
}
