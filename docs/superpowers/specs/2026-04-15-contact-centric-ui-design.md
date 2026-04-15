# Contact-Centric UI Redesign

## Problem

Geary's current UI organizes email by folders (Inbox, Sent, Drafts...), requiring users to switch between folders to see correspondence with a specific person. This is the traditional email client model but doesn't match how people actually think about their email — by who they're communicating with.

## Goal

Redesign the three-column layout from **Folders → Conversations → Email** to **Contacts → Emails with Contact → Email Content**, creating a messaging-style experience where people are the primary organizing unit.

## Design Decisions

| Decision | Choice |
|----------|--------|
| Contact display | Avatar (colored initials) + name + email + unread badge |
| Account grouping | Separated by account (header per account) |
| Contact sorting | Most recent email first |
| Direction indicator | Received: blue ↓ arrow on left. Sent: green ↑ arrow on right |
| Email threading | Single email view (no conversation threading) |
| Compose | Reply/compose opens in column 3 |
| Color scheme | Unified dark palette (see Color Palette section) |

## Layout

### Column 1 — Contact List (replaces FolderList.Tree)

```
┌─────────────────────┐
│ 🔍 Search contacts  │
├─────────────────────┤
│ ME@GMAIL.COM        │  ← account header
├─────────────────────┤
│ [AJ] Alice Johnson  │  ← selected (highlighted)
│      alice@ex...  3 │     avatar + name + email + unread badge
│ [BS] Bob Smith      │
│      bob@work   1   │
│ [CW] Carol Williams │
│      carol@co...    │
├─────────────────────┤
│ WORK@COMPANY.COM    │  ← second account header
├─────────────────────┤
│ [HR] HR Department  │
│      hr@comp... 2   │
└─────────────────────┘
```

- **Data source**: All unique email addresses found in Inbox and Sent folders for each account
- **Excluded**: The user's own email addresses (`account.information.sender_mailboxes`)
- **Avatar**: Circular badge with initials derived from display name (or first letter of email if no name)
- **Avatar color**: Deterministic from email address hash (consistent color per contact)
- **Unread badge**: Count of unread emails from this contact in Inbox
- **Search**: Filters contacts by name or email substring
- **Sorting**: Contacts with the most recent email (sent or received) appear first

### Column 2 — Contact Email List (replaces ConversationList.View)

```
┌──────────────────────────────┐
│ [AJ] Alice Johnson  6 emails │  ← contact header
├──────────────────────────────┤
│ ↓  Re: Project timeline  2h │  ← incoming (arrow left)
│    Thanks for the update...  │
│                              │
│    Project timeline    Yest  │  ← outgoing (arrow right)
│    Hi Alice, here's...    ↑  │
│                              │
│ ↓  Quick question    Mar 12  │  ← incoming
│    Hey, do you have a...     │
└──────────────────────────────┘
```

- **Data source**: All emails from Inbox where `from` matches contact, plus all emails from Sent where `to`/`cc`/`bcc` contains contact
- **Direction detection**: If `email.from` matches any of `account.information.sender_mailboxes` → outgoing; otherwise → incoming
- **Arrow placement**: Incoming = blue `↓` on left margin, right margin empty. Outgoing = left margin empty, green `↑` on right margin
- **Row content**: Subject (bold), preview snippet, date
- **Sorting**: Newest first (by email date)
- **Selection**: Clicking an email shows it in column 3

### Column 3 — Email Viewer (modified from ConversationViewer)

- Displays a **single email** (not a conversation thread)
- Shows: sender avatar + name, recipients, date, subject, full email body
- Reply/compose opens inline below the email content
- When no email is selected: shows placeholder ("Select an email to read")

## Color Palette

```
Background:
  --bg-primary:    #1e1e2e   (deepest, column 3 and account headers)
  --bg-secondary:  #252536   (columns 1 and 2 background)
  --bg-selected:   #32324a   (selected item highlight)
  --border:        #3a3a50   (separators)

Text:
  --text-primary:   #e0e0ec  (names, subjects, body text)
  --text-secondary: #a0a0b8  (preview snippets, email body)
  --text-muted:     #707088  (emails, dates, counts)

Accent:
  --accent:    #7c8ef2       (selection indicator, badges, active avatar)
  --incoming:  #7cacf2       (received arrow)
  --outgoing:  #7cc8a0       (sent arrow)
```

Note: These colors define the visual design target. In GTK implementation, colors will be applied through CSS stylesheets that respect the system GTK theme, using these as the dark theme variant.

## Architecture

### New Components to Create

1. **`ContactList.View`** — GTK widget replacing `FolderList.Tree` in column 1
   - Extends `Gtk.ScrolledWindow` containing a `Gtk.ListBox`
   - Includes search entry at top
   - Groups contacts under account headers using `Gtk.ListBox` row separators

2. **`ContactList.Model`** — Implements `GLib.ListModel` for contacts
   - Wraps contact data with last-activity date and unread count
   - Sorts by last email date descending
   - Filters by search query
   - One model instance per account

3. **`ContactList.Row`** — Widget for individual contact rows
   - Avatar (drawn with Cairo), name label, email label, unread badge

4. **`ContactList.AccountHeader`** — Widget for account group headers

5. **`ContactEmailList.View`** — GTK widget replacing `ConversationList.View` in column 2
   - Extends `Gtk.ScrolledWindow` containing a `Gtk.ListBox`
   - Contact header bar at top
   - Populates from cross-folder email query

6. **`ContactEmailList.Row`** — Widget for individual email rows
   - Direction arrow, subject, preview, date

7. **`ContactEmailList.Model`** — Implements `GLib.ListModel` for emails with a contact
   - Queries emails from Inbox + Sent matching contact address
   - Sorts by date descending

### Modified Components

8. **`Application.MainWindow`** — Rewire column connections
   - Replace `folder_list` (FolderList.Tree) with `contact_list` (ContactList.View)
   - Replace `conversation_list_view` (ConversationList.View) with `contact_email_list` (ContactEmailList.View)
   - Replace `select_folder()` flow with `select_contact()` flow
   - Replace `on_conversations_selected()` with `on_email_selected()` flow
   - Modify `ConversationViewer` usage to load single emails instead of conversations

9. **`application-main-window.ui`** — Update widget references in UI template

10. **`ConversationViewer`** — Add single-email display mode
    - New method: `load_single_email(Email, EmailStore, ContactStore)`
    - Reuses existing `ConversationWebView` for HTML rendering

### Data Flow

```
Startup / Account loaded:
  Account.get_special_folder(INBOX) ──┐
  Account.get_special_folder(SENT)  ──┤
                                      ▼
                            ContactList.Model
                            (queries ContactStore + 
                             computes last-activity dates
                             from folder email listings)
                                      │
                                      ▼
                            ContactList.View (column 1)

Contact selected:
  ContactList.View.contact_selected signal
          │
          ▼
  MainWindow.on_contact_selected(contact, account)
          │
          ▼
  Query: emails from Inbox where from=contact
       + emails from Sent where to/cc/bcc contains contact
          │
          ▼
  ContactEmailList.Model (sorted by date desc)
          │
          ▼
  ContactEmailList.View (column 2)

Email selected:
  ContactEmailList.View.email_selected signal
          │
          ▼
  MainWindow.on_email_selected(email)
          │
          ▼
  ConversationViewer.load_single_email(email)
          │
          ▼
  Email rendered in column 3
```

### Cross-Folder Email Query Strategy

The key technical challenge: querying emails across Inbox and Sent filtered by contact.

**Approach**: Use the existing `ImapDB` SQLite database directly via a new query method on the account/engine layer. The database already has `MessageTable` with sender info and `MessageLocationTable` linking messages to folders. We add a method like:

```
Account.list_emails_for_contact_async(
    contact_address: RFC822.MailboxAddress,
    folders: Collection<Folder>,    // [inbox, sent]
    fields: Email.Field,
    cancellable: Cancellable
) -> Collection<Email>
```

This queries the local database for messages where:
- The message is in one of the specified folders AND
- The `from`, `to`, `cc`, or `bcc` fields contain the contact's email address

### Contact List Population

**Approach**: Iterate over emails in Inbox and Sent (using existing `Folder.list_email_async()` with `ENVELOPE` fields), extract unique addresses, merge with `ContactStore` data for display names, compute last-activity dates, and sort.

This can be done lazily — load the first N contacts sorted by recent activity, then load more on scroll. The existing `ContactStore` already has harvested contacts with importance levels, which helps prioritize.

### Existing Code to Reuse

| Need | Existing code | Path |
|------|--------------|------|
| Contact data | `Geary.ContactStore` / `ContactStoreImpl` | `src/engine/api/geary-contact-store.vala`, `src/engine/common/common-contact-store-impl.vala` |
| Contact model | `Geary.Contact` | `src/engine/api/geary-contact.vala` |
| Email address handling | `RFC822.MailboxAddress` | `src/engine/rfc822/rfc822-mailbox-address.vala` |
| Account email info | `AccountInformation.sender_mailboxes` | `src/engine/api/geary-account-information.vala` |
| Special folder access | `Account.get_special_folder(SpecialUse)` | `src/engine/api/geary-account.vala` |
| Email listing | `Folder.list_email_async()` | `src/engine/api/geary-folder.vala` |
| Direction check | `AccountInformation.has_sender_mailbox()` | `src/engine/api/geary-account-information.vala` |
| WebView email rendering | `ConversationWebView` | `src/client/conversation-viewer/conversation-web-view.vala` |
| Row display patterns | `ConversationList.Row` (reference) | `src/client/conversation-list/conversation-list-row.vala` |
| Participant display | `ConversationList.Participant` | `src/client/conversation-list/conversation-list-participant.vala` |
| Leaflet responsive layout | `HdyLeaflet` setup in MainWindow | `src/client/application/application-main-window.vala` |
| Avatar drawing | Existing Cairo patterns in client utils | `src/client/util/` |

## Scope Boundaries

**In scope:**
- New contact list widget (column 1)
- New contact email list widget (column 2)
- Single-email viewer mode for column 3
- Reply/compose inline in column 3
- Search/filter contacts
- Unread badge per contact
- Direction arrows for incoming/outgoing
- HdyLeaflet responsive folding (same two-level approach)

**Out of scope:**
- Contact avatars from GNOME Contacts / Gravatar (use initials only)
- Drag and drop between contacts
- Contact management (add/edit/delete contacts)
- Changing the email engine or IMAP sync behavior
- Modifying the plugin system
- Multi-select emails in column 2

## Verification

1. Configure a Gmail account via GNOME Online Accounts
2. Launch Geary — contact list should populate from Inbox+Sent
3. Click a contact — column 2 shows their emails with correct direction arrows
4. Click an email — column 3 shows the single email content
5. Reply inline — composer opens in column 3
6. Search contacts — list filters correctly
7. Resize window — leaflet folding works correctly
8. Multiple accounts — each shows its own contact group
9. Run `just test-engine` — existing engine tests still pass
10. Run `just test-client` (with display) — client tests still pass
