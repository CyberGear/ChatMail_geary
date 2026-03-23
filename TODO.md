# Geary Project TODO

## In Progress

<!-- Tasks currently being worked on -->

## Planned

<!-- Tasks planned for future development -->
- [ ] Implement drafts, compose and other may be needed features in contact view

## Done

<!-- Completed tasks -->
- [x] Implement new "Contact-based" email view (basic implementation)
- [x] Explore codebase to understand current UI architecture
- [x] Explore data layer (Folder, Email, ContactStore APIs)
- [x] Fix build: install gcr-devel dependency
- [x] Fix build: meson type comparison for libhandy
- [x] Fix build: remove StyleManager (libhandy 1.2.1 compatibility)
- [x] Build and run application successfully

---

## Contact-based View Implementation Plan

### Overview
Replace folder-based 3-column view with contact-based 3-column view:
- Column 1: Contacts (from emails in selected folder)
- Column 2: All emails (inbox + sent), aggregated, filtered by contact
- Column 3: Email content preview (unchanged)

### Implementation Steps

#### Step 1: Create Contact List Component
**Directory:** `src/client/contact-list/`

**Files to create:**
- [x] `contact-list-tree.vala` - Main tree view for contacts
- [x] `contact-list-entry.vala` - Individual contact row (simpler version)
- [x] `contact-list-model.vala` - Data model for contacts

**Classes:**
```
ContactList.Tree : Sidebar.Tree
  - Displays contacts extracted from folder emails
  - Signal: contact_selected(Contact contact)

ContactList.Row : Sidebar.Entry
  - Shows contact name/email with avatar
  - Shows unread count badge

ContactList.Model : GLib.Object
  - Stores extracted contacts
  - Methods: load_from_folder(), get_contacts()
```

**Key methods:**
```vala
// Extract contacts from folder emails
public async void load_contacts_from_folder(Folder folder)

// Get unique contacts with counts
public Gee.Map<Contact, int> get_contact_counts()
```

#### Step 2: Create Contact-based Email List
**Directory:** Modify existing `src/client/conversation-list/`

**Changes needed:**
- [x] Create `ContactConversationListModel` that aggregates from multiple folders
- [x] Support filtering by contact
- [ ] Add visual distinction for incoming (left) vs outgoing (right)

**New file:** `contact-conversation-list-model.vala`
```vala
public class ContactConversationListModel : GLib.Object
  - Gee.ListModel implementation
  - Load from multiple folders (Inbox + Sent)
  - Filter by contact
  - Sort by date (newest first)
```

#### Step 3: Modify MainWindow
**File:** `src/client/application/application-main-window.vala`

**Changes:**
1. [x] Add toggle between views (menu item + keyboard shortcut)
2. [x] Store two sets of widgets: folder-based and contact-based
3. [x] Implement view switching logic (basic)

**New properties:**
```vala
public ContactList.Tree contact_list { get; private set; }
public bool use_contact_view { get; set; }
```

**New methods:**
```vala
private void toggle_view()
private void on_contact_selected(Contact contact)
private void load_contact_view(Folder folder)
```

#### Step 4: Add Toggle UI
**Location:** Application menu or toolbar

- Menu item: "View > Contact-based Mode" (Ctrl+Shift+C)
- Persist preference in config

#### Step 5: Contact Extraction Logic
**Helper class:** Extract contacts from email headers

```vala
public class ContactExtractor : GLib.Object
  // From RFC822.MailboxAddress
  public static Contact extract_from_address(MailboxAddress addr)
  
  // Aggregate unique contacts from email list
  public static Gee.Set<Contact> extract_unique(
    Gee.List<Email> emails
  )
```

**Email fields needed:**
- `Email.Field.ORIGINATORS` (from, sender, reply_to)
- `Email.Field.RECEIVERS` (to, cc, bcc)

### Key API References

| Component | File | Key Class/Method |
|-----------|------|------------------|
| Folder API | `src/engine/api/geary-folder.vala` | `list_email_by_id_async()` |
| Email API | `src/engine/api/geary-email.vala` | `from`, `to`, `cc` properties |
| RFC822 | `src/engine/rfc822/rfc822-mailbox-address.vala` | `MailboxAddress` |
| Account | `src/engine/api/geary-account.vala` | `get_special_folder()` |
| Contact | `src/engine/api/geary-contact.vala` | `Contact` class |

### File Changes Summary

**New files (3):**
1. [x] `src/client/contact-list/contact-list-tree.vala`
2. [x] `src/client/contact-list/contact-list-entry.vala`
3. [x] `src/client/contact-list/contact-list-model.vala`
4. [ ] `src/client/conversation-list/contact-conversation-list-model.vala`
5. [x] `src/client/util/contact-extractor.vala`

**Modified files (1):**
1. [x] `src/client/meson.build` (add new files)

### Testing Strategy
1. Test contact extraction from various email types
2. Test view toggle functionality
3. Test filtering works correctly
4. Test performance with large mailboxes
