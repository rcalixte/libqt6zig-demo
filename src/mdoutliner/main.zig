const builtin = @import("builtin");
const std = @import("std");
const qt6 = @import("libqt6zig");
const resources = @import("resources.zig");
const C = qt6.C;
const qhboxlayout = qt6.qhboxlayout;
const qtabwidget = qt6.qtabwidget;
const qfiledialog = qt6.qfiledialog;
const qtextedit = qt6.qtextedit;
const qcoreapplication = qt6.qcoreapplication;
const qicon = qt6.qicon;
const qlistwidget = qt6.qlistwidget;
const qlistwidgetitem = qt6.qlistwidgetitem;
const qtextdocument = qt6.qtextdocument;
const qvariant = qt6.qvariant;
const qtextcursor = qt6.qtextcursor;
const qtextblock = qt6.qtextblock;
const qnamespace_enums = qt6.qnamespace_enums;
const qwidget = qt6.qwidget;
const qsplitter = qt6.qsplitter;
const qapplication = qt6.qapplication;
const qmainwindow = qt6.qmainwindow;
const qkeysequence = qt6.qkeysequence;
const qaction = qt6.qaction;
const qmenubar = qt6.qmenubar;
const qmenu = qt6.qmenu;
const qlabel = qt6.qlabel;
const qstatusbar = qt6.qstatusbar;
const qlocale = qt6.qlocale;
const qtranslator = qt6.qtranslator;

var allocator: std.mem.Allocator = undefined;
var io: std.Io = undefined;

const line_number_role = qnamespace_enums.ItemDataRole.UserRole + 1;

const AppTabMap = std.AutoHashMapUnmanaged(?*anyopaque, *AppTab);
const AppWindowMap = std.AutoHashMapUnmanaged(?*anyopaque, *AppWindow);

var app_tab_map: AppTabMap = undefined;
var app_window_tab_map: AppWindowMap = undefined;
var main_window: *AppWindow = undefined;

var file_menu: C.QMenu = undefined;
var newtab: C.QAction = undefined;
var open: C.QAction = undefined;
var exit: C.QAction = undefined;
var options_menu: C.QMenu = undefined;
var language_menu: C.QMenu = undefined;
var english: C.QAction = undefined;
var french: C.QAction = undefined;
var spanish: C.QAction = undefined;
var help_menu: C.QMenu = undefined;
var about: C.QAction = undefined;

fn onTriggered(self: ?*anyopaque) callconv(.c) void {
    const language = qaction.ObjectName(self, allocator);
    defer allocator.free(language);

    const locale = qlocale.New2(language);
    defer qlocale.Delete(locale);

    const translator = qtranslator.New();
    defer qtranslator.Delete(translator);

    if (qtranslator.Load42(translator, locale, "mdoutliner", "_", ":/translations"))
        _ = qapplication.InstallTranslator(translator)
    else
        return;

    const file_text = qapplication.Translate("Main", "&File", allocator);
    defer allocator.free(file_text);
    qmenu.SetTitle(file_menu, file_text);

    const new_text = qapplication.Translate("Main", "&New Tab", allocator);
    defer allocator.free(new_text);
    qaction.SetText(newtab, new_text);

    const new_bind = qapplication.Translate3("Main", "Ctrl+N", "New tab", allocator);
    defer allocator.free(new_bind);

    const newKey = qkeysequence.New2(new_bind);
    defer qkeysequence.Delete(newKey);

    qaction.SetShortcut(newtab, newKey);

    const open_text = qapplication.Translate("Main", "&Open...", allocator);
    defer allocator.free(open_text);
    qaction.SetText(open, open_text);

    const open_bind = qapplication.Translate3("Main", "Ctrl+O", "Open a file", allocator);
    defer allocator.free(open_bind);

    const open_key = qkeysequence.New2(open_bind);
    defer qkeysequence.Delete(open_key);

    qaction.SetShortcut(open, open_key);

    const exit_text = qapplication.Translate("Main", "&Exit", allocator);
    defer allocator.free(exit_text);
    qaction.SetText(exit, exit_text);

    const exit_bind = qapplication.Translate3("Main", "Ctrl+Q", "Quit", allocator);
    defer allocator.free(exit_bind);

    const exit_key = qkeysequence.New2(exit_bind);
    defer qkeysequence.Delete(exit_key);

    qaction.SetShortcut(exit, exit_key);

    const options_text = qapplication.Translate("Main", "&Options", allocator);
    defer allocator.free(options_text);
    qmenu.SetTitle(options_menu, options_text);

    const language_text = qapplication.Translate("Main", "&Language", allocator);
    defer allocator.free(language_text);
    qmenu.SetTitle(language_menu, language_text);

    const english_text = qapplication.Translate("Main", "&English", allocator);
    defer allocator.free(english_text);
    qaction.SetText(english, english_text);

    const french_text = qapplication.Translate("Main", "&French", allocator);
    defer allocator.free(french_text);
    qaction.SetText(french, french_text);

    const spanish_text = qapplication.Translate("Main", "&Spanish", allocator);
    defer allocator.free(spanish_text);
    qaction.SetText(spanish, spanish_text);

    const help_text = qapplication.Translate("Main", "&Help", allocator);
    defer allocator.free(help_text);
    qmenu.SetTitle(help_menu, help_text);

    const about_text = qapplication.Translate("Main", "&About Qt", allocator);
    defer allocator.free(about_text);
    qaction.SetText(about, about_text);
}

pub const AppTab = struct {
    tab: C.QWidget,
    outline: C.QListWidget,
    text_area: C.QTextEdit,

    pub fn updateOutlineForContent(self: *AppTab, content: []const u8) void {
        qlistwidget.Clear(self.outline);

        var lines = std.mem.splitScalar(u8, content, '\n');
        var in_code_block = false;
        var line_number: i32 = 0;
        var prev_line: []const u8 = undefined;
        var buf: [32]u8 = undefined;

        while (lines.next()) |line| {
            if (!in_code_block)
                if (std.mem.startsWith(u8, line, "#")) {
                    const bookmark = qlistwidgetitem.New7(line, self.outline);
                    const tooltip = std.fmt.bufPrint(&buf, "Line {d}", .{line_number + 1}) catch continue;

                    qlistwidgetitem.SetToolTip(bookmark, tooltip);
                    const line_num = qvariant.New4(line_number);
                    defer qvariant.Delete(line_num);
                    qlistwidgetitem.SetData(bookmark, line_number_role, line_num);
                } else if ((std.mem.startsWith(u8, line, "---") or std.mem.startsWith(u8, line, "===")) and !std.mem.eql(u8, prev_line, "")) {
                    const bookmark = qlistwidgetitem.New7(prev_line, self.outline);
                    const tooltip = std.fmt.bufPrint(&buf, "Line {d}", .{line_number}) catch continue;

                    qlistwidgetitem.SetToolTip(bookmark, tooltip);
                    const line_num = qvariant.New4(line_number - 1);
                    defer qvariant.Delete(line_num);
                    qlistwidgetitem.SetData(bookmark, line_number_role, line_num);
                };

            if (std.mem.startsWith(u8, line, "```"))
                in_code_block = !in_code_block;

            prev_line = line;
            line_number += 1;
        }
    }

    pub fn deinit(self: *AppTab) void {
        qwidget.Delete(self.tab);
        self.tab = null;
    }

    pub fn handleJumpToBookmark(self: ?*anyopaque, _: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
        if (app_tab_map.get(self)) |apptab| {
            const itm = qlistwidget.CurrentItem(apptab.outline);
            if (itm == null) return;

            const line_number_qvariant = qlistwidgetitem.Data(itm, line_number_role);
            const line_number = qvariant.ToInt(line_number_qvariant);
            defer qvariant.Delete(line_number_qvariant);

            const text_area_document = qtextedit.Document(apptab.text_area);
            if (text_area_document == null) return;

            const target_block = qtextdocument.FindBlockByLineNumber(text_area_document, line_number);
            if (target_block == null) return;

            const cursor = qtextcursor.New4(target_block);
            defer qtextcursor.Delete(cursor);

            qtextcursor.SetPosition(cursor, qtextblock.Position(target_block));
            qtextedit.SetTextCursor(apptab.text_area, cursor);
            qtextedit.SetFocus(apptab.text_area);
        }
    }

    pub fn handleTextChanged(self: ?*anyopaque) callconv(.c) void {
        if (app_tab_map.get(self)) |apptab| {
            const content = qtextedit.ToPlainText(self, allocator);
            defer allocator.free(content);

            if (content.len == 0) return;

            updateOutlineForContent(apptab, content);
        }
    }
};

pub fn NewAppTab() !*AppTab {
    var ret = try allocator.create(AppTab);

    ret.tab = qwidget.New2();

    const layout = qhboxlayout.New(ret.tab);
    const panes = qsplitter.New2();
    qhboxlayout.AddWidget(layout, panes);

    ret.outline = qlistwidget.New(ret.tab);
    qsplitter.AddWidget(panes, ret.outline);
    qlistwidget.OnCurrentItemChanged(ret.outline, AppTab.handleJumpToBookmark);

    ret.text_area = qtextedit.New(ret.tab);
    try app_tab_map.put(allocator, ret.text_area, ret);
    try app_tab_map.put(allocator, ret.outline, ret);

    qtextedit.OnTextChanged(ret.text_area, AppTab.handleTextChanged);
    qsplitter.AddWidget(panes, ret.text_area);

    var sizes = [_]i32{ 250, 550 };
    qsplitter.SetSizes(panes, &sizes);

    return ret;
}

pub const AppWindow = struct {
    w: C.QMainWindow,
    tabs: C.QTabWidget,

    pub fn createTabWithContents(self: *AppWindow, tab_title: []const u8, tab_content: []const u8) void {
        const tab = NewAppTab() catch @panic("Failed to create tab");
        // the new tab is cleaned up during handleTabClose

        qtextedit.SetText(tab.text_area, tab_content);

        const icon = qicon.FromTheme("text-markdown");
        defer qicon.Delete(icon);

        const tab_idx = qtabwidget.AddTab2(self.tabs, tab.tab, icon, tab_title);
        qtabwidget.SetCurrentIndex(self.tabs, tab_idx);
    }

    pub fn handleTabClose(tab: ?*anyopaque, index: i32) callconv(.c) void {
        if (app_window_tab_map.get(tab)) |appwindow| {
            const widget = qtabwidget.Widget(appwindow.tabs, index);
            if (widget != null) {
                var tab_to_free: ?*AppTab = null;

                var it = app_tab_map.iterator();
                while (it.next()) |entry| {
                    const apptab = entry.value_ptr.*;
                    if (apptab.tab == widget) {
                        tab_to_free = apptab;
                        _ = app_tab_map.fetchRemove(apptab.text_area);
                        _ = app_tab_map.fetchRemove(apptab.outline);
                        break;
                    }
                }
                qtabwidget.RemoveTab(appwindow.tabs, index);

                if (tab_to_free) |apptab| {
                    apptab.deinit();
                    allocator.destroy(apptab);
                }
            }
        }
    }

    pub fn handleCloseCurrentTab(_: ?*anyopaque) callconv(.c) void {
        if (main_window.tabs != null) {
            const current_index = qtabwidget.CurrentIndex(main_window.tabs);
            if (current_index >= 0)
                handleTabClose(main_window.tabs, current_index);
        }
    }

    pub fn handleNewTab(_: ?*anyopaque) callconv(.c) void {
        createTabWithContents(main_window, "New Document", "");
    }

    pub fn handleFileOpen(_: ?*anyopaque) callconv(.c) void {
        const fname = qfiledialog.GetOpenFileName4(
            main_window.w,
            "Open markdown file...",
            "",
            "Markdown files (*.md *.txt);;All Files (*)",
            allocator,
        );
        defer allocator.free(fname);

        if (fname.len == 0) return;

        const file = std.Io.Dir.cwd().openFile(io, fname, .{}) catch @panic("Failed to open file");
        defer file.close(io);

        var buffer: [4096]u8 = undefined;
        var file_reader = file.reader(io, &buffer);
        const contents = file_reader.interface.allocRemaining(allocator, .unlimited) catch @panic("Failed to read file");
        defer allocator.free(contents);

        createTabWithContents(main_window, std.fs.path.basename(fname), contents);
    }

    pub fn handleExit(_: ?*anyopaque) callconv(.c) void {
        qcoreapplication.Quit();
    }

    pub fn handleAbout(_: ?*anyopaque) callconv(.c) void {
        qapplication.AboutQt();
    }
};

pub fn NewAppWindow() !*AppWindow {
    var ret = try allocator.create(AppWindow);

    ret.w = qmainwindow.New2();
    qmainwindow.SetWindowTitle(ret.w, "Markdown Outliner");
    qmainwindow.Resize(ret.w, 900, 600);

    const mnu = qmenubar.New2();

    file_menu = qmenubar.AddMenu2(mnu, "&File");

    newtab = qmenubar.AddAction2(file_menu, "&New Tab");
    const new_tab_key_sequence = qkeysequence.New2("Ctrl+N");
    defer qkeysequence.Delete(new_tab_key_sequence);
    qaction.SetShortcut(newtab, new_tab_key_sequence);
    const new_icon = qicon.FromTheme("document-new");
    defer qicon.Delete(new_icon);
    qaction.SetIcon(newtab, new_icon);
    qaction.OnTriggered(newtab, AppWindow.handleNewTab);

    open = qmenubar.AddAction2(file_menu, "&Open...");
    const open_key_sequence = qkeysequence.New2("Ctrl+O");
    defer qkeysequence.Delete(open_key_sequence);
    qaction.SetShortcut(open, open_key_sequence);
    const open_icon = qicon.FromTheme("document-open");
    defer qicon.Delete(open_icon);
    qaction.SetIcon(open, open_icon);
    qaction.OnTriggered(open, AppWindow.handleFileOpen);

    _ = qmenubar.AddSeparator(file_menu);

    exit = qmenubar.AddAction2(file_menu, "&Exit");
    const exit_key_sequence = qkeysequence.New2("Ctrl+Q");
    defer qkeysequence.Delete(exit_key_sequence);
    qaction.SetShortcut(exit, exit_key_sequence);
    const exit_icon = qicon.FromTheme("application-exit");
    defer qicon.Delete(exit_icon);
    qaction.SetIcon(exit, exit_icon);
    qaction.OnTriggered(exit, AppWindow.handleExit);

    options_menu = qmenubar.AddMenu2(mnu, "&Options");

    language_menu = qmenubar.AddMenu2(options_menu, "&Language");
    const languageIcon = qicon.FromTheme("preferences-desktop-locale");
    defer qicon.Delete(languageIcon);
    qmenu.SetIcon(language_menu, languageIcon);
    english = qmenubar.AddAction2(language_menu, "&English");
    qaction.SetObjectName(english, "en");
    qaction.OnTriggered(english, onTriggered);
    french = qmenubar.AddAction2(language_menu, "&French");
    qaction.SetObjectName(french, "fr");
    qaction.OnTriggered(french, onTriggered);
    spanish = qmenubar.AddAction2(language_menu, "&Spanish");
    qaction.SetObjectName(spanish, "es");
    qaction.OnTriggered(spanish, onTriggered);

    _ = qmenubar.AddMenu(options_menu, language_menu);

    help_menu = qmenubar.AddMenu2(mnu, "&Help");
    about = qmenubar.AddAction2(help_menu, "&About Qt");
    const about_icon = qicon.FromTheme("help-about");
    defer qicon.Delete(about_icon);
    qaction.SetIcon(about, about_icon);
    const about_shortcut_sequence = qkeysequence.New2("F1");
    defer qkeysequence.Delete(about_shortcut_sequence);
    qaction.SetShortcut(about, about_shortcut_sequence);
    qaction.OnTriggered(about, AppWindow.handleAbout);

    qmainwindow.SetMenuBar(ret.w, mnu);

    const close_key_param = "Ctrl+W";
    const close_key_sequence = qkeysequence.New2(close_key_param);
    defer qkeysequence.Delete(close_key_sequence);
    const close = qmainwindow.AddAction4(ret.w, close_key_param, close_key_sequence);
    qaction.SetShortcut(close, close_key_sequence);
    qaction.OnTriggered(close, AppWindow.handleCloseCurrentTab);

    ret.tabs = qtabwidget.New(ret.w);
    qtabwidget.SetTabsClosable(ret.tabs, true);
    qtabwidget.SetMovable(ret.tabs, true);
    qtabwidget.OnTabCloseRequested(ret.tabs, AppWindow.handleTabClose);
    qmainwindow.SetCentralWidget(ret.w, ret.tabs);

    if (builtin.mode == .Debug) {
        const label = qlabel.New3("## NOTE: This is a debug build.\n");
        qlabel.SetAlignment(label, qnamespace_enums.AlignmentFlag.AlignCenter);
        qlabel.SetTextFormat(label, qnamespace_enums.TextFormat.MarkdownText);
        qlabel.SetStyleSheet(label, "background-color: rgb(240, 228, 66); color: rgb(0, 0, 0);");

        const status_bar = qstatusbar.New2();
        qstatusbar.SetStyleSheet(status_bar, "background-color: rgb(240, 228, 66);");
        qstatusbar.AddPermanentWidget2(status_bar, label, 1);
        qmainwindow.SetStatusBar(ret.w, status_bar);
    }

    AppWindow.createTabWithContents(ret, "README.md", @embedFile("README.md"));

    try app_window_tab_map.put(allocator, ret.tabs, ret);
    main_window = ret;

    return ret;
}

pub fn main(init: std.process.Init) !void {
    const argv = try qt6.init(init.gpa, init.minimal.args);
    defer qt6.deinit(init.gpa, argv);
    var argc: i32 = @intCast(argv.len);
    const qapp = qapplication.New(&argc, argv, init.arena.allocator());
    defer qapplication.Delete(qapp);

    allocator = init.gpa;
    io = init.io;

    var ok = resources.init();
    if (!ok)
        try std.Io.File.stdout().writeStreamingAll(init.io, "Resource initialization failed!\n");
    defer {
        ok = resources.deinit();
        if (!ok)
            std.Io.File.stdout().writeStreamingAll(
                init.io,
                "Resource deinitialization failed!\n",
            ) catch @panic("Failed to stdout deinit\n");
    }

    app_tab_map = .empty;
    app_window_tab_map = .empty;

    defer {
        var processed_tabs: std.AutoHashMapUnmanaged(*AppTab, void) = .empty;
        defer processed_tabs.deinit(allocator);

        var it = app_tab_map.iterator();
        while (it.next()) |entry| {
            const apptab = entry.value_ptr.*;
            if (!processed_tabs.contains(apptab)) {
                _ = processed_tabs.put(allocator, apptab, {}) catch @panic("Failed to put AppTab into processed_tabs");

                allocator.destroy(apptab);
            }
        }
        app_tab_map.deinit(allocator);
        app_window_tab_map.deinit(allocator);
    }

    const app = try NewAppWindow();
    defer allocator.destroy(app);

    qmainwindow.Show(app.w);

    _ = qapplication.Exec();
}
