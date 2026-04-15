/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2016,2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Displays the messages in a conversation and in-window composers.
 */
[GtkTemplate (ui = "/org/gnome/Geary/conversation-viewer.ui")]
public class ConversationViewer : Gtk.Stack, Geary.BaseInterface {

    /**
     * The current conversation listbox, if any.
     */
    public ConversationListBox? current_list {
        get; private set; default = null;
    }

    /** Returns the currently displayed composer if any. */
    public Composer.Widget? current_composer {
        get; private set; default = null;
    }

    /**
     * The most recent web view created in this viewer.
     *
     * Keep the last created web view around so others can share the
     * same WebKitGTK WebProcess.
     */
    internal ConversationWebView? previous_web_view { get; set; default = null; }

    private Application.Configuration config;

    private Gee.Set<Geary.App.Conversation>? selection_while_composing = null;
    private GLib.Cancellable? find_cancellable = null;

    // Stack pages
    [GtkChild] private unowned Gtk.Spinner loading_page;
    [GtkChild] private unowned Gtk.Grid no_conversations_page;
    [GtkChild] private unowned Gtk.Grid conversation_page;
    [GtkChild] private unowned Gtk.Grid multiple_conversations_page;
    [GtkChild] private unowned Gtk.Grid empty_folder_page;
    [GtkChild] private unowned Gtk.Grid empty_search_page;
    [GtkChild] private unowned Gtk.Grid composer_page;
    [GtkChild] private unowned Gtk.ScrolledWindow conversation_scroller;

    [GtkChild] internal unowned Gtk.SearchBar conversation_find_bar;

    [GtkChild] internal unowned Gtk.SearchEntry conversation_find_entry;
    private Components.EntryUndo conversation_find_undo;

    [GtkChild] private unowned Gtk.Button conversation_find_next;

    [GtkChild] private unowned Gtk.Button conversation_find_prev;


    /* Emitted when a new conversation list was added to this view. */
    public signal void conversation_added(ConversationListBox list);

    /* Emitted when a new conversation list was removed from this view. */
    public signal void conversation_removed(ConversationListBox list);


    static construct {
        set_css_name("geary-conversation-viewer");
    }

    /**
     * Constructs a new conversation view instance.
     */
    public ConversationViewer(Application.Configuration config) {
        base_ref();
        this.config = config;

        Hdy.StatusPage no_conversations =
            new Hdy.StatusPage();
        no_conversations.icon_name = "folder-symbolic";
        // Translators: Title label for placeholder when no
        // conversations have been selected.
        no_conversations.title = _("No Conversations Selected");
        // Translators: Sub-title label for placeholder when no
        // conversations have been selected.
        no_conversations.description = _(
            "Selecting a conversation from the list will display it here."
        );
        no_conversations.hexpand = true;
        no_conversations.vexpand = true;
        no_conversations.show ();
        this.no_conversations_page.add(no_conversations);

        Hdy.StatusPage multi_conversations =
            new Hdy.StatusPage();
        multi_conversations.icon_name = "folder-symbolic";
        // Translators: Title label for placeholder when multiple
        // conversations have been selected.
        multi_conversations.title = _("Multiple Conversations Selected");
        // Translators: Sub-title label for placeholder when multiple
        // conversations have been selected.
        multi_conversations.description = _(
            "Choosing an action will apply to all selected conversations."
        );
        multi_conversations.hexpand = true;
        multi_conversations.vexpand = true;
        multi_conversations.show ();
        this.multiple_conversations_page.add(multi_conversations);

        Hdy.StatusPage empty_folder =
            new Hdy.StatusPage();
        empty_folder.icon_name = "folder-symbolic";
        // Translators: Title label for placeholder when no
        // conversations have exist in a folder.
        empty_folder.title = _("No Conversations Found");
        // Translators: Sub-title label for placeholder when no
        // conversations have exist in a folder.
        empty_folder.description = _(
            "This folder does not contain any conversations."
        );
        empty_folder.hexpand = true;
        empty_folder.vexpand = true;
        empty_folder.show ();
        this.empty_folder_page.add(empty_folder);

        Hdy.StatusPage empty_search =
            new Hdy.StatusPage();
        empty_search.icon_name = "folder-symbolic";
        // Translators: Title label for placeholder when no
        // conversations have been found in a search.
        empty_search.title = _("No Conversations Found");
        // Translators: Sub-title label for placeholder when no
        // conversations have been found in a search.
        empty_search.description = _(
            "Your search returned no results, try refining your search terms."
        );
        empty_search.hexpand = true;
        empty_search.vexpand = true;
        empty_search.show ();
        this.empty_search_page.add(empty_search);

        this.conversation_find_undo = new Components.EntryUndo(
            this.conversation_find_entry
        );

        // XXX Do this in Glade when possible.
        this.conversation_find_bar.connect_entry(this.conversation_find_entry);
    }

    ~ConversationViewer() {
        base_unref();
    }

    /**
     * Puts the view into composer mode, showing a full-height composer.
     */
    public void do_compose(Composer.Widget composer) {
        var main_window = get_toplevel() as Application.MainWindow;
        if (main_window != null) {
            Composer.Box box = new Composer.Box(
                composer, main_window.conversation_headerbar
            );
            this.current_composer = composer;

            // XXX move the ConversationListView management code into
            // MainWindow or somewhere more appropriate
            ConversationList.View conversation_list = main_window.conversation_list_view;
            this.selection_while_composing = conversation_list.selected;
            conversation_list.unselect_all();

            box.vanished.connect(on_composer_closed);
            this.composer_page.add(box);
            set_visible_child(this.composer_page);
            composer.update_window_title();
        }
    }

    /**
     * Puts the view into composer mode, showing an embedded composer.
     */
    public void do_compose_embedded(Composer.Widget composer,
                                    Geary.Email? referred) {
        this.current_composer = composer;
        Composer.Embed embed = new Composer.Embed(
            referred,
            composer,
            this.conversation_scroller
        );
        embed.vanished.connect(on_composer_closed);

        // We need to temporarily disable kinetic scrolling so that if
        // it still has some momentum when the composer is inserted
        // and scrolled to, it won't jump away again. See Bug 778027.
        var kinetic = this.conversation_scroller.kinetic_scrolling;
        if (kinetic) this.conversation_scroller.kinetic_scrolling = false;

        if (this.current_list != null) {
            this.current_list.add_embedded_composer(
                embed,
                composer.saved_id != null
            );
            composer.update_window_title();
        }

        if (kinetic) this.conversation_scroller.kinetic_scrolling = true;

        // Set a minimal composer height
        composer.set_size_request(
            -1, this.conversation_scroller.get_allocated_height() / 3 * 2
        );
    }

    /**
     * Shows the loading UI.
     */
    public void show_loading() {
        this.loading_page.start();
        set_visible_child(this.loading_page);
    }

    /**
     * Shows the UI when no conversations have been selected
     */
    public void show_none_selected() {
        set_visible_child(this.no_conversations_page);
    }

    /**
     * Shows the UI when multiple conversations have been selected
     */
    public void show_multiple_selected() {
        set_visible_child(this.multiple_conversations_page);
    }

    /**
     * Shows the empty folder UI.
     */
    public void show_empty_folder() {
        set_visible_child(this.empty_folder_page);
    }

   /**
     * Shows the empty search UI.
     */
    public void show_empty_search() {
        set_visible_child(this.empty_search_page);
    }

    /** Shows and focuses the find entry. */
    public void enable_find() {
        this.conversation_find_bar.set_search_mode(true);
        this.conversation_find_entry.grab_focus();
    }

    /**
     * Shows a single email in the viewer (no conversation threading).
     */
    public void load_single_email(Geary.Email email,
                                  Geary.AccountInformation account_info) {
        remove_current_list();

        var container = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);

        // Header section
        var header = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
        header.margin_start = 24;
        header.margin_end = 24;
        header.margin_top = 18;
        header.margin_bottom = 18;

        // Subject
        if (email.subject != null) {
            var subject_label = new Gtk.Label(
                Util.Email.strip_subject_prefixes(email)
            );
            subject_label.xalign = 0;
            subject_label.wrap = true;
            subject_label.selectable = true;
            subject_label.get_style_context().add_class("email-viewer-subject");
            var subject_attrs = new Pango.AttrList();
            subject_attrs.insert(Pango.attr_weight_new(Pango.Weight.SEMIBOLD));
            subject_attrs.insert(Pango.attr_scale_new(1.25));
            subject_label.attributes = subject_attrs;
            header.pack_start(subject_label, false, false, 0);
        }

        // Sender info
        var sender_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 10);
        sender_box.margin_top = 8;

        if (email.from != null && email.from.size > 0) {
            var from_addr = email.from.get(0);
            string initials = "?";
            if (from_addr.has_distinct_name()) {
                var parts = from_addr.name.split(" ");
                if (parts.length >= 2) {
                    initials = parts[0].substring(0, 1).up()
                             + parts[parts.length - 1].substring(0, 1).up();
                } else if (parts.length == 1 && parts[0].length > 0) {
                    initials = parts[0].substring(0, 1).up();
                }
            } else if (from_addr.address.length > 0) {
                initials = from_addr.address.substring(0, 1).up();
            }

            // Avatar
            var avatar = new Gtk.DrawingArea();
            avatar.set_size_request(30, 30);
            avatar.draw.connect((cr) => {
                cr.arc(15, 15, 15, 0, 2 * Math.PI);
                cr.set_source_rgb(0.486, 0.557, 0.949); // #7c8ef2
                cr.fill();
                cr.select_font_face("Sans",
                    Cairo.FontSlant.NORMAL, Cairo.FontWeight.BOLD);
                cr.set_font_size(11);
                Cairo.TextExtents te;
                cr.text_extents(initials, out te);
                cr.move_to(15 - te.width / 2 - te.x_bearing,
                           15 - te.height / 2 - te.y_bearing);
                cr.set_source_rgb(1, 1, 1);
                cr.show_text(initials);
                return true;
            });
            sender_box.pack_start(avatar, false, false, 0);

            // Sender name and details
            var info_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
            string from_text;
            if (from_addr.has_distinct_name()) {
                from_text = "<b>%s</b> <span alpha='60%'>&lt;%s&gt;</span>".printf(
                    GLib.Markup.escape_text(from_addr.name),
                    GLib.Markup.escape_text(from_addr.address)
                );
            } else {
                from_text = "<b>%s</b>".printf(
                    GLib.Markup.escape_text(from_addr.address)
                );
            }
            var from_label = new Gtk.Label(null);
            from_label.set_markup(from_text);
            from_label.xalign = 0;
            from_label.selectable = true;
            info_box.pack_start(from_label, false, false, 0);

            // To line and date
            var meta_parts = new GLib.StringBuilder();
            if (email.to != null && email.to.size > 0) {
                meta_parts.append("to ");
                bool is_to_me = false;
                foreach (var addr in email.to) {
                    if (account_info.has_sender_mailbox(addr)) {
                        is_to_me = true;
                        break;
                    }
                }
                if (is_to_me) {
                    meta_parts.append("me");
                } else {
                    meta_parts.append(
                        GLib.Markup.escape_text(email.to.get(0).address)
                    );
                }
            }
            if (email.date != null) {
                if (meta_parts.len > 0) meta_parts.append(" · ");
                meta_parts.append(
                    Util.Date.pretty_print(
                        email.date.value,
                        Util.Date.ClockFormat.LOCALE_DEFAULT
                    )
                );
            }
            if (meta_parts.len > 0) {
                var meta_label = new Gtk.Label(null);
                meta_label.set_markup(
                    "<span color='#707088' size='small'>%s</span>".printf(
                        meta_parts.str
                    )
                );
                meta_label.xalign = 0;
                info_box.pack_start(meta_label, false, false, 0);
            }

            sender_box.pack_start(info_box, true, true, 0);
        }

        header.pack_start(sender_box, false, false, 0);
        container.pack_start(header, false, false, 0);

        // Separator
        var sep = new Gtk.Separator(Gtk.Orientation.HORIZONTAL);
        container.pack_start(sep, false, false, 0);

        // Body (preview text for now, full body rendering can be added later)
        var body_scroll = new Gtk.ScrolledWindow(null, null);
        body_scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
        body_scroll.vscrollbar_policy = Gtk.PolicyType.AUTOMATIC;

        var body_label = new Gtk.Label(email.get_preview_as_string());
        body_label.wrap = true;
        body_label.xalign = 0;
        body_label.yalign = 0;
        body_label.selectable = true;
        body_label.margin_start = 24;
        body_label.margin_end = 24;
        body_label.margin_top = 24;
        body_label.margin_bottom = 24;
        var body_attrs = new Pango.AttrList();
        body_attrs.insert(Pango.attr_scale_new(1.05));
        body_label.attributes = body_attrs;
        body_scroll.add(body_label);

        container.pack_start(body_scroll, true, true, 0);
        container.show_all();

        // Put it in the conversation scroller
        Gtk.Viewport viewport = new Gtk.Viewport(null, null);
        viewport.show();
        viewport.add(container);
        this.conversation_scroller.add(viewport);

        base.set_visible_child(this.conversation_page);
    }

    /**
     * Shows a conversation in the viewer.
     */
    public async void load_conversation(Geary.App.Conversation conversation,
                                        Gee.Collection<Geary.EmailIdentifier> scroll_to,
                                        Geary.App.EmailStore store,
                                        Application.ContactStore contacts,
                                        bool start_mark_timer)
        throws GLib.Error {
        var old_viewport = remove_current_list();

        ConversationListBox new_list = new ConversationListBox(
            conversation,
            !start_mark_timer,
            store,
            contacts,
            this.config,
            this.conversation_scroller.get_vadjustment()
        );

        // Need to fire this signal early so the the controller
        // can hook in to its signals to catch any emails added
        // during loading.
        this.conversation_added(new_list);

        // Also set up find infrastructure early so matching emails
        // are expanded and highlighted as they are added.
        this.conversation_find_next.set_sensitive(false);
        this.conversation_find_prev.set_sensitive(false);
        new_list.search.matches_updated.connect((count) => {
                bool found = count > 0;
                this.conversation_find_entry.set_icon_from_icon_name(
                    Gtk.EntryIconPosition.PRIMARY,
                    found || Geary.String.is_empty(this.conversation_find_entry.text)
                    ? "edit-find-symbolic" : "computer-fail-symbolic"
                );
                this.conversation_find_next.set_sensitive(found);
                this.conversation_find_prev.set_sensitive(found);
            });
        add_new_list(new_list);
        set_visible_child(this.conversation_page);

        // Highlight matching terms from find if active, otherwise
        // from the search folder if that's where we are at
        var query = get_find_search_query(conversation.base_folder.account);
        if (query == null) {
            var search_folder = conversation.base_folder as Geary.App.SearchFolder;
            if (search_folder != null) {
                query = search_folder.query;
            }
        }

        yield new_list.load_conversation(scroll_to, query);
        old_viewport = null;
    }

    // Add a new conversation list to the UI
    private void add_new_list(ConversationListBox list) {
        this.current_list = list;
        list.show();

        // Manually create a Viewport rather than letting
        // ScrolledWindow do it so Container.set_focus_{h,v}adjustment
        // are not set on the list - it makes changing focus jumpy
        // when a row or its web_view are larger than the viewport.
        Gtk.Viewport viewport = new Gtk.Viewport(null, null);
        viewport.show();
        viewport.add(list);

        this.conversation_scroller.add(viewport);
    }

    // Remove any existing conversation list, cancelling its loading
    private Gtk.Widget remove_current_list() {
        // Remove the viewport that contains the current list
        Gtk.Widget? scrolled_child = this.conversation_scroller.get_child();
        if (scrolled_child != null) {
            conversation_scroller.remove(scrolled_child);
        }

        // Reset the scrollbars to their initial positions
        this.conversation_scroller.hadjustment.set_value(0);
        this.conversation_scroller.vadjustment.set_value(0);

        if (this.current_list != null) {
            this.current_list.cancel_conversation_load();
            this.conversation_removed(this.current_list);
            this.current_list = null;
        }
        return scrolled_child;
    }

    /**
     * Sets the currently visible page of the stack.
     */
    private new void set_visible_child(Gtk.Widget widget) {
        debug("Showing: %s", widget.get_name());
        Gtk.Widget current = get_visible_child();
        if (current == this.conversation_page) {
            if (widget != this.conversation_page) {
                // By removing the current list, any load it is currently
                // performing is also cancelled, which is important to
                // avoid a possible crit warning when switching folders,
                // etc.
                remove_current_list();
            }
        } else if (current == this.loading_page) {
            // Stop the spinner running so it doesn't trigger repaints
            // and wake up Geary even when idle. See Bug 783025.
            this.loading_page.stop();
        }
        base.set_visible_child(widget);
    }

    private async void update_find_results() {
        ConversationListBox? list = this.current_list;
        if (list != null) {
            if (this.find_cancellable != null) {
                this.find_cancellable.cancel();
            }
            GLib.Cancellable cancellable = new GLib.Cancellable();
            cancellable.cancelled.connect(() => {
                    list.search.cancel();
                });
            this.find_cancellable = cancellable;
            try {
                var query = get_find_search_query(
                    list.conversation.base_folder.account
                );
                if (query != null) {
                    yield list.search.highlight_matching_email(query, true);
                }
            } catch (GLib.Error err) {
                warning("Error updating find results: %s", err.message);
            }
        }
    }

    private Geary.SearchQuery? get_find_search_query(Geary.Account account)
        throws GLib.Error {
        Geary.SearchQuery? query = null;
        if (this.conversation_find_bar.get_search_mode()) {
            string text = this.conversation_find_entry.get_text().strip();
            // Require find string of at least two chars to avoid
            // opening every message in the conversation as soon as
            // the user presses a key
            if (text.length >= 2) {
                var expr_factory = new Util.Email.SearchExpressionFactory(
                    this.config.get_search_strategy(),
                    account.information
                );
                query = account.new_search_query(
                    expr_factory.parse_query(text),
                    text
                );
            }
        }
        return query;
    }

    [GtkCallback]
    private void on_find_mode_changed(Object obj, ParamSpec param) {
        if (this.current_list != null) {
            if (this.conversation_find_bar.get_search_mode()) {
                // Find became enabled
                ConversationEmail? email_view =
                    this.current_list.get_selection_view();
                if (email_view != null) {
                    email_view.get_selection_for_find.begin((obj, res) => {
                            string text = email_view.get_selection_for_find.end(res);
                            if (text != null) {
                                this.conversation_find_entry.set_text(text);
                                this.conversation_find_entry.select_region(0, -1);
                            }
                        });
                }
            } else {
                // Find became disabled, re-show search terms if any
                this.current_list.search.unmark_terms();
                Geary.App.SearchFolder? search_folder = (
                    this.current_list.conversation.base_folder
                    as Geary.App.SearchFolder
                );
                this.conversation_find_undo.reset();
                if (search_folder != null) {
                    Geary.SearchQuery? query = search_folder.query;
                    if (query != null) {
                        this.current_list.search.highlight_matching_email.begin(
                            query,
                            true
                        );
                    }
                }
            }
        }
    }

    [GtkCallback]
    private void on_find_text_changed(Gtk.SearchEntry entry) {
        this.conversation_find_next.set_sensitive(false);
        this.conversation_find_prev.set_sensitive(false);
        this.update_find_results.begin();
    }

    [GtkCallback]
    private void on_find_next(Gtk.Widget entry) {
         if (this.current_list != null) {
             //this.current_list.show_prev_search_term();
         }
    }

    [GtkCallback]
    private void on_find_prev(Gtk.Widget entry) {
        if (this.current_list != null) {
            //this.current_list.show_next_search_term();
        }
    }

    [GtkCallback]
    private bool on_conversation_scroll() {
        if (this.current_list != null) {
            this.current_list.mark_visible_read();
        }
        return Gdk.EVENT_PROPAGATE;
    }

    private void on_composer_closed() {
        this.current_composer = null;
        if (get_visible_child() == this.composer_page) {
            set_visible_child(this.conversation_page);

            // Restore the old selection
            var main_window = get_toplevel() as Application.MainWindow;
            if (main_window != null) {
                main_window.update_title();

                if (this.selection_while_composing != null) {
                    var conversation_list = main_window.conversation_list_view;
                    if (this.selection_while_composing.is_empty) {
                        conversation_list.conversations_selected(
                            this.selection_while_composing
                        );
                    } else {
                        conversation_list.select_conversations(
                            this.selection_while_composing
                        );
                    }

                    this.selection_while_composing = null;
                }
            }
        }
    }
}
