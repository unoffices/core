/*
   Copyright (C) 2009-2013 Christian Dywan <christian@twotoasts.de>

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2.1 of the License, or (at your option) any later version.

   See the file COPYING for the full license text.
*/

namespace Gtk {
    extern static void widget_size_request (Gtk.Widget widget, out Gtk.Requisition requisition);
}

namespace Sokoke {
    extern static bool show_uri (Gdk.Screen screen, string uri, uint32 timestamp) throws Error;
    extern static void widget_get_text_size (Gtk.Widget widget, string sample, out int width, out int height);
}

namespace Transfers {
    private class Transfer : GLib.Object {
        internal WebKit.Download download;

        internal signal void changed ();
        internal signal void remove ();
        internal signal void removed ();

        internal Transfer (WebKit.Download download) {
            this.download = download;
            download.notify["status"].connect (transfer_changed);
            download.notify["progress"].connect (transfer_changed);
        }

        void transfer_changed (GLib.ParamSpec pspec) {
            changed ();
        }
    }

    private class Sidebar : Gtk.VBox, Midori.Viewable {
        Gtk.Toolbar? toolbar = null;
        Gtk.ToolButton clear;
        Gtk.ListStore store = new Gtk.ListStore (1, typeof (Transfer));
        Gtk.TreeView treeview;
        Katze.Array array;

        public unowned string get_stock_id () {
            return Midori.Stock.TRANSFER;
        }

        public unowned string get_label () {
            return _("Transfers");
        }

        public Gtk.Widget get_toolbar () {
            if (toolbar == null) {
                toolbar = new Gtk.Toolbar ();
                toolbar.set_icon_size (Gtk.IconSize.BUTTON);
                toolbar.insert (new Gtk.ToolItem (), -1);
                var separator = new Gtk.SeparatorToolItem ();
                separator.draw = false;
                separator.set_expand (true);
                toolbar.insert (separator, -1);
                clear = new Gtk.ToolButton.from_stock (Gtk.STOCK_CLEAR);
                clear.label = _("Clear All");
                clear.is_important = true;
                clear.clicked.connect (clear_clicked);
                clear.sensitive = !array.is_empty ();
                toolbar.insert (clear, -1);
                toolbar.show_all ();
            }
            return toolbar;
        }

        void clear_clicked () {
            foreach (GLib.Object item in array.get_items ()) {
                var transfer = item as Transfer;
                if (Midori.Download.is_finished (transfer.download))
                    transfer.remove ();
            }
        }

        public Sidebar (Katze.Array array) {
            Gtk.TreeViewColumn column;

            treeview = new Gtk.TreeView.with_model (store);
            treeview.headers_visible = false;

            store.set_sort_column_id (0, Gtk.SortType.ASCENDING);
            store.set_sort_func (0, tree_sort_func);

            column = new Gtk.TreeViewColumn ();
            Gtk.CellRendererPixbuf renderer_icon = new Gtk.CellRendererPixbuf ();
            column.pack_start (renderer_icon, false);
            column.set_cell_data_func (renderer_icon, on_render_icon);
            treeview.append_column (column);

            column = new Gtk.TreeViewColumn ();
            column.set_sizing (Gtk.TreeViewColumnSizing.AUTOSIZE);
            Gtk.CellRendererProgress renderer_progress = new Gtk.CellRendererProgress ();
            column.pack_start (renderer_progress, true);
            column.set_expand (true);
            column.set_cell_data_func (renderer_progress, on_render_text);
            treeview.append_column (column);

            column = new Gtk.TreeViewColumn ();
            Gtk.CellRendererPixbuf renderer_button = new Gtk.CellRendererPixbuf ();
            column.pack_start (renderer_button, false);
            column.set_cell_data_func (renderer_button, on_render_button);
            treeview.append_column (column);

            treeview.row_activated.connect (row_activated);
            treeview.button_release_event.connect (button_released);
            treeview.popup_menu.connect (menu_popup);
            treeview.show ();
            pack_start (treeview, true, true, 0);

            this.array = array;
            array.add_item.connect (transfer_added);
            array.remove_item.connect_after (transfer_removed);
            foreach (GLib.Object item in array.get_items ())
                transfer_added (item);
        }

        void row_activated (Gtk.TreePath path, Gtk.TreeViewColumn column) {
            Gtk.TreeIter iter;
            if (store.get_iter (out iter, path)) {
                Transfer transfer;
                store.get (iter, 0, out transfer);

                if (Midori.Download.action_clear (transfer.download, treeview))
                    transfer.remove ();
            }
        }

        bool button_released (Gdk.EventButton event) {
            if (event.button == 3)
                return show_popup_menu (event);
            return false;
        }

        bool menu_popup () {
            return show_popup_menu (null);
        }

        bool show_popup_menu (Gdk.EventButton? event) {
            Gtk.TreeIter iter;
            if (treeview.get_selection ().get_selected (null, out iter)) {
                Transfer transfer;
                store.get (iter, 0, out transfer);

                bool finished = transfer.download.status == WebKit.DownloadStatus.FINISHED;
                var menu = new Gtk.Menu ();
                var menuitem = new Gtk.ImageMenuItem.from_stock (Gtk.STOCK_OPEN, null);
                menuitem.activate.connect (() => {
                    Midori.Download.open (transfer.download, treeview);
                });
                menuitem.sensitive = finished;
                menu.append (menuitem);
                menuitem = new Gtk.ImageMenuItem.with_mnemonic (_("Open Destination _Folder"));
                menuitem.image = new Gtk.Image.from_stock (Gtk.STOCK_DIRECTORY, Gtk.IconSize.MENU);
                menuitem.activate.connect (() => {
                    var folder = GLib.File.new_for_uri (transfer.download.destination_uri);
                    Sokoke.show_uri (get_screen (), folder.get_parent ().get_uri (), 0);
                });
                menu.append (menuitem);
                menuitem = new Gtk.ImageMenuItem.with_mnemonic (_("Copy Link Loc_ation"));
                menuitem.activate.connect (() => {
                    string uri = transfer.download.destination_uri;
                    get_clipboard (Gdk.SELECTION_PRIMARY).set_text (uri, -1);
                    get_clipboard (Gdk.SELECTION_CLIPBOARD).set_text (uri, -1);
                });
                menuitem.image = new Gtk.Image.from_stock (Gtk.STOCK_COPY, Gtk.IconSize.MENU);
                menu.append (menuitem);
                menu.show_all ();
                // Katze.widget_popup (treeview, menu, null, Katze.MenuPosition.CURSOR);
                menu.popup (null, null, null, event != null ? event.button : 0, event != null ? event.time : 0);

                return true;
            }
            return false;
        }

        int tree_sort_func (Gtk.TreeModel model, Gtk.TreeIter a, Gtk.TreeIter b) {
            Transfer transfer1, transfer2;
            model.get (a, 0, out transfer1);
            model.get (b, 0, out transfer2);
            return transfer1.download.status - transfer2.download.status;
        }

        void transfer_changed () {
            treeview.queue_draw ();
        }

        void transfer_added (GLib.Object item) {
            var transfer = item as Transfer;
            Gtk.TreeIter iter;
            store.append (out iter);
            store.set (iter, 0, transfer);
            transfer.changed.connect (transfer_changed);
            clear.sensitive = true;
        }

        void transfer_removed (GLib.Object item) {
            var transfer = item as Transfer;
            transfer.changed.disconnect (transfer_changed);
            Gtk.TreeIter iter;
            if (store.iter_children (out iter, null)) {
                do {
                    Transfer found;
                    store.get (iter, 0, out found);
                    if (transfer == found) {
                        store.remove (iter);
                        break;
                    }
                } while (store.iter_next (ref iter));
            }
            if (array.is_empty ())
                clear.sensitive = false;
        }

        void on_render_icon (Gtk.CellLayout column, Gtk.CellRenderer renderer,
            Gtk.TreeModel model, Gtk.TreeIter iter) {

            Transfer transfer;
            model.get (iter, 0, out transfer);
            string content_type = Midori.Download.get_content_type (transfer.download, null);
            var icon = GLib.ContentType.get_icon (content_type) as ThemedIcon;
            icon.append_name ("text-html");
            renderer.set ("gicon", icon,
                          "stock-size", Gtk.IconSize.DND,
                          "xpad", 1, "ypad", 12);
        }

        void on_render_text (Gtk.CellLayout column, Gtk.CellRenderer renderer,
            Gtk.TreeModel model, Gtk.TreeIter iter) {

            Transfer transfer;
            model.get (iter, 0, out transfer);
            string tooltip = Midori.Download.get_tooltip (transfer.download);
            double progress = Midori.Download.get_progress (transfer.download);
            renderer.set ("text", tooltip,
                          "value", (int)(progress * 100));
        }

        void on_render_button (Gtk.CellLayout column, Gtk.CellRenderer renderer,
            Gtk.TreeModel model, Gtk.TreeIter iter) {

            Transfer transfer;
            model.get (iter, 0, out transfer);
            string stock_id = Midori.Download.action_stock_id (transfer.download);
            renderer.set ("stock-id", stock_id,
                          "stock-size", Gtk.IconSize.MENU);
        }
    }

    private class TransferButton : Gtk.ToolItem {
        Transfer transfer;
        Gtk.ProgressBar progress;
        Gtk.Image icon;
        Gtk.Button button;

        public TransferButton (Transfer transfer) {
            this.transfer = transfer;

            var box = new Gtk.HBox (false, 0);
            progress = new Gtk.ProgressBar ();
#if HAVE_GTK3
            progress.show_text = true;
#endif
            progress.ellipsize = Pango.EllipsizeMode.MIDDLE;
            string filename = Path.get_basename (transfer.download.destination_uri);
            progress.text = filename;
            int width;
            Sokoke.widget_get_text_size (progress, "M", out width, null);
            progress.set_size_request (width * 10, 1);
            box.pack_start (progress, false, false, 0);

            icon = new Gtk.Image ();
            button = new Gtk.Button ();
            button.relief = Gtk.ReliefStyle.NONE;
            button.focus_on_click = false;
            button.clicked.connect (button_clicked);
            button.add (icon);
            box.pack_start (button, false, false, 0);

            add (box);
            show_all ();

            transfer.changed.connect (transfer_changed);
            transfer_changed ();
            transfer.removed.connect (transfer_removed);
        }

        void button_clicked () {
            if (Midori.Download.action_clear (transfer.download, button))
                transfer.remove ();
        }

        void transfer_changed () {
            progress.fraction = Midori.Download.get_progress (transfer.download);
            progress.tooltip_text = Midori.Download.get_tooltip (transfer.download);
            string stock_id = Midori.Download.action_stock_id (transfer.download);
            icon.set_from_stock (stock_id, Gtk.IconSize.MENU);
        }

        void transfer_removed () {
            destroy ();
        }
    }

    private class Toolbar : Gtk.Toolbar {
        Katze.Array array;
        Gtk.ToolButton clear;

        void clear_clicked () {
            foreach (GLib.Object item in array.get_items ()) {
                var transfer = item as Transfer;
                if (Midori.Download.is_finished (transfer.download))
                    array.remove_item (item);
            }
        }

        public Toolbar (Katze.Array array) {
            set_icon_size (Gtk.IconSize.BUTTON);
            set_style (Gtk.ToolbarStyle.BOTH_HORIZ);
            show_arrow = false;

            clear = new Gtk.ToolButton.from_stock (Gtk.STOCK_CLEAR);
            clear.label = _("Clear All");
            clear.is_important = true;
            clear.clicked.connect (clear_clicked);
            clear.sensitive = !array.is_empty ();
            insert (clear, -1);
            show_all ();

            this.array = array;
            array.add_item.connect (transfer_added);
            array.remove_item.connect_after (transfer_removed);
            foreach (GLib.Object item in array.get_items ())
                transfer_added (item);
        }

        void transfer_added (GLib.Object item) {
            var transfer = item as Transfer;
            insert (new TransferButton (transfer), -1);
            clear.sensitive = true;

            Gtk.Requisition req;
            Gtk.widget_size_request (parent, out req);
            int reqwidth = req.width;
            int winwidth;
            (get_toplevel () as Gtk.Window).get_size (out winwidth, null);
            if (reqwidth > winwidth)
                clear_clicked ();
        }

        void transfer_removed (GLib.Object item) {
            if (array.is_empty ())
                clear.sensitive = false;
        }
    }

    private class Manager : Midori.Extension {
        internal Katze.Array array;
        internal GLib.List<Gtk.Widget> widgets;

        void download_added (WebKit.Download download) {
            var transfer = new Transfer (download);
            transfer.remove.connect (transfer_remove);
            transfer.changed.connect (transfer_changed);
            array.remove_item.connect (transfer_removed);
            array.add_item (transfer);
        }

        void transfer_changed (Transfer transfer) {
            if (transfer.download.get_status () == WebKit.DownloadStatus.FINISHED) {
                /* FIXME: The following 2 blocks ought to be done in core */
                var type = Midori.Download.get_type (transfer.download);
                if (type == Midori.DownloadType.OPEN) {
                    if (Midori.Download.action_clear (transfer.download, widgets.nth_data (0)))
                        transfer.remove ();
                }

                string uri = transfer.download.destination_uri;
                string filename = Path.get_basename (uri);
                var item = new Katze.Item ();
                item.uri = uri;
                item.name = filename;
                Midori.Browser.update_history (item, "download", "create");
                if (!Midori.Download.has_wrong_checksum (transfer.download))
                    Gtk.RecentManager.get_default ().add_item (uri);

                string msg = _("The file '<b>%s</b>' has been downloaded.").printf (filename);
                get_app ().send_notification (_("Transfer completed"), msg);
            }
        }

        void transfer_remove (Transfer transfer) {
            array.remove_item (transfer);
        }

        void transfer_removed (GLib.Object item) {
            var transfer = item as Transfer;
            transfer.removed ();
        }

        bool browser_closed (Gtk.Widget widget, Gdk.EventAny event) {
            var browser = widget as Midori.Browser;
            bool pending_downloads = false;
            foreach (GLib.Object item in array.get_items ()) {
                var transfer = item as Transfer;
                if (!Midori.Download.is_finished (transfer.download)) {
                    pending_downloads = true;
                    break;
                }
            }
            if (pending_downloads) {
                var dialog = new Gtk.MessageDialog (browser,
                    Gtk.DialogFlags.DESTROY_WITH_PARENT,
                    Gtk.MessageType.WARNING, Gtk.ButtonsType.NONE,
                    _("Some files are being downloaded"));
                dialog.title = _("Some files are being downloaded");
                dialog.add_buttons (Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
                                    _("_Quit Midori"), Gtk.ResponseType.ACCEPT);
                dialog.format_secondary_text (
                    _("The transfers will be cancelled if Midori quits."));
                bool cancel = dialog.run () != Gtk.ResponseType.ACCEPT;
                dialog.destroy ();
                return cancel;
            }
            return false;
        }

        void browser_added (Midori.Browser browser) {
            var viewable = new Sidebar (array);
            viewable.show ();
            browser.panel.append_page (viewable);
            widgets.append (viewable);
            var toolbar = new Toolbar (array);
#if HAVE_GTK3
            browser.statusbar.pack_end (toolbar);
#else
            browser.statusbar.pack_start (toolbar);
#endif
            widgets.append (toolbar);
            // TODO: popover
            // TODO: progress in dock item
            browser.add_download.connect (download_added);
            browser.delete_event.connect (browser_closed);
        }

        void activated (Midori.App app) {
            array = new Katze.Array (typeof (Transfer));
            widgets = new GLib.List<Gtk.Widget> ();
            foreach (var browser in app.get_browsers ())
                browser_added (browser);
            app.add_browser.connect (browser_added);
        }

        void deactivated () {
            var app = get_app ();
            app.add_browser.disconnect (browser_added);
            foreach (var browser in app.get_browsers ()) {
                browser.add_download.disconnect (download_added);
                browser.delete_event.disconnect (browser_closed);
            }
            foreach (var widget in widgets)
                widget.destroy ();
            array.remove_item.disconnect (transfer_removed);
        }

        internal Manager () {
            GLib.Object (name: _("Transfer Manager"),
                         description: _("View downloaded files"),
                         version: "0.1" + Midori.VERSION_SUFFIX,
                         authors: "Christian Dywan <christian@twotoasts.de>");

            this.activate.connect (activated);
            this.deactivate.connect (deactivated);
        }
    }
}

public Midori.Extension extension_init () {
    return new Transfers.Manager ();
}
