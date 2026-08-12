const builtin = @import("builtin");
const std = @import("std");
const qt6 = @import("libqt6zig");
const resources = @import("resources.zig");

const QHBoxLayout = qt6.QHBoxLayout;
const QTabWidget = qt6.QTabWidget;
const QFileDialog = qt6.QFileDialog;
const QTextEdit = qt6.QTextEdit;
const QIcon = qt6.QIcon;
const QListWidget = qt6.QListWidget;
const QListWidgetItem = qt6.QListWidgetItem;
const QVariant = qt6.QVariant;
const QTextCursor = qt6.QTextCursor;
const qnamespace_enums = qt6.qnamespace_enums;
const QWidget = qt6.QWidget;
const QSplitter = qt6.QSplitter;
const QApplication = qt6.QApplication;
const QMainWindow = qt6.QMainWindow;
const QKeySequence = qt6.QKeySequence;
const QAction = qt6.QAction;
const QMenuBar = qt6.QMenuBar;
const QMenu = qt6.QMenu;
const QLabel = qt6.QLabel;
const QStatusBar = qt6.QStatusBar;
const QLocale = qt6.QLocale;
const QTranslator = qt6.QTranslator;

var allocator: std.mem.Allocator = undefined;
var io: std.Io = undefined;

const line_number_role = qnamespace_enums.ItemDataRole.UserRole + 1;

const AppTabMap = std.AutoHashMapUnmanaged(QWidget, *AppTab);
const AppWindowMap = std.AutoHashMapUnmanaged(QTabWidget, *AppWindow);

var app_tab_map: AppTabMap = .empty;
var app_window_tab_map: AppWindowMap = .empty;

var main_window: *AppWindow = undefined;
var file_menu: QMenu = undefined;
var newtab: QAction = undefined;
var open: QAction = undefined;
var exit: QAction = undefined;

var options_menu: QMenu = undefined;
var language_menu: QMenu = undefined;

var english: QAction = undefined;
var french: QAction = undefined;
var spanish: QAction = undefined;

var help_menu: QMenu = undefined;
var about: QAction = undefined;

fn onTriggered(self: QAction) callconv(.c) void {
    const language = self.objectName(allocator);
    defer allocator.free(language);

    const locale = QLocale.new2(language);
    defer locale.delete();

    const translator = QTranslator.new();
    defer translator.delete();

    if (translator.load42(locale, "mdoutliner", "_", ":/translations"))
        _ = QApplication.installTranslator(translator)
    else
        return;

    const file_text = QApplication.translate(allocator, "Main", "&File");
    defer allocator.free(file_text);
    file_menu.setTitle(file_text);

    const new_text = QApplication.translate(allocator, "Main", "&New Tab");
    defer allocator.free(new_text);
    newtab.setText(new_text);

    const new_bind = QApplication.translate3(allocator, "Main", "Ctrl+N", "New tab");
    defer allocator.free(new_bind);

    const new_key = QKeySequence.new2(new_bind);
    defer new_key.delete();

    newtab.setShortcut(new_key);

    const open_text = QApplication.translate(allocator, "Main", "&Open...");
    defer allocator.free(open_text);
    open.setText(open_text);

    const open_bind = QApplication.translate3(allocator, "Main", "Ctrl+O", "Open a file");
    defer allocator.free(open_bind);

    const open_key = QKeySequence.new2(open_bind);
    defer open_key.delete();

    open.setShortcut(open_key);

    const exit_text = QApplication.translate(allocator, "Main", "&Exit");
    defer allocator.free(exit_text);
    exit.setText(exit_text);

    const exit_bind = QApplication.translate3(allocator, "Main", "Ctrl+Q", "Quit");
    defer allocator.free(exit_bind);

    const exit_key = QKeySequence.new2(exit_bind);
    defer exit_key.delete();

    exit.setShortcut(exit_key);

    const options_text = QApplication.translate(allocator, "Main", "&Options");
    defer allocator.free(options_text);
    options_menu.setTitle(options_text);

    const language_text = QApplication.translate(allocator, "Main", "&Language");
    defer allocator.free(language_text);
    language_menu.setTitle(language_text);

    const english_text = QApplication.translate(allocator, "Main", "&English");
    defer allocator.free(english_text);
    english.setText(english_text);

    const french_text = QApplication.translate(allocator, "Main", "&French");
    defer allocator.free(french_text);
    french.setText(french_text);

    const spanish_text = QApplication.translate(allocator, "Main", "&Spanish");
    defer allocator.free(spanish_text);
    spanish.setText(spanish_text);

    const help_text = QApplication.translate(allocator, "Main", "&Help");
    defer allocator.free(help_text);
    help_menu.setTitle(help_text);

    const about_text = QApplication.translate(allocator, "Main", "&About Qt");
    defer allocator.free(about_text);
    about.setText(about_text);
}

pub const AppTab = struct {
    tab: QWidget,
    outline: QListWidget,
    text_area: QTextEdit,

    pub fn create(alloc: std.mem.Allocator) !*AppTab {
        var ret = try alloc.create(AppTab);
        errdefer alloc.destroy(ret);

        ret.tab = .new2();

        const layout = QHBoxLayout.new(ret.tab);
        const panes = QSplitter.new2();
        layout.addWidget(panes);

        ret.outline = .new(ret.tab);
        panes.addWidget(ret.outline);
        ret.outline.onCurrentItemChanged(AppTab.handleJumpToBookmark);

        ret.text_area = .new(ret.tab);
        try app_tab_map.put(alloc, .{ .ptr = @ptrCast(ret.text_area.ptr) }, ret);
        try app_tab_map.put(alloc, .{ .ptr = @ptrCast(ret.outline.ptr) }, ret);

        ret.text_area.onTextChanged(AppTab.handleTextChanged);
        panes.addWidget(ret.text_area);

        var sizes = [_]i32{ 250, 550 };
        panes.setSizes(&sizes);

        return ret;
    }

    pub fn updateOutlineForContent(self: *AppTab, content: []const u8) void {
        self.outline.clear();

        var lines = std.mem.splitScalar(u8, content, '\n');
        var in_code_block = false;
        var line_number: i32 = 0;
        var prev_line: []const u8 = undefined;
        var buf: [32]u8 = undefined;

        while (lines.next()) |line| {
            if (!in_code_block)
                if (std.mem.startsWith(u8, line, "#")) {
                    const bookmark = QListWidgetItem.new7(line, self.outline);
                    const tooltip = std.fmt.bufPrint(&buf, "Line {d}", .{line_number + 1}) catch continue;

                    bookmark.setToolTip(tooltip);
                    const line_num = QVariant.new4(line_number);
                    defer line_num.delete();
                    bookmark.setData(line_number_role, line_num);
                } else if ((std.mem.startsWith(u8, line, "---") or
                    std.mem.startsWith(u8, line, "===")) and
                    !std.mem.eql(u8, prev_line, ""))
                {
                    const bookmark = QListWidgetItem.new7(prev_line, self.outline);
                    const tooltip = std.fmt.bufPrint(&buf, "Line {d}", .{line_number}) catch continue;

                    bookmark.setToolTip(tooltip);
                    const line_num = QVariant.new4(line_number - 1);
                    defer line_num.delete();
                    bookmark.setData(line_number_role, line_num);
                };

            if (std.mem.startsWith(u8, line, "```"))
                in_code_block = !in_code_block;

            prev_line = line;
            line_number += 1;
        }
    }

    pub fn destroy(self: *AppTab, alloc: std.mem.Allocator) void {
        self.tab.delete();
        self.tab.ptr = null;
        alloc.destroy(self);
    }

    pub fn handleJumpToBookmark(self: QListWidget, current: QListWidgetItem, _: QListWidgetItem) callconv(.c) void {
        if (app_tab_map.get(.{ .ptr = @ptrCast(self.ptr) })) |apptab| {
            if (current.ptr == null) return;

            const line_number_qvariant = current.data(line_number_role);
            const line_number = line_number_qvariant.toInt();
            defer line_number_qvariant.delete();

            const text_area_document = apptab.text_area.document();
            const target_block = text_area_document.findBlockByLineNumber(line_number);
            defer target_block.delete();

            const cursor = QTextCursor.new4(target_block);
            defer cursor.delete();

            cursor.setPosition(target_block.position());
            apptab.text_area.setTextCursor(cursor);
            apptab.text_area.setFocus();
        }
    }

    pub fn handleTextChanged(self: QTextEdit) callconv(.c) void {
        if (app_tab_map.get(.{ .ptr = @ptrCast(self.ptr) })) |apptab| {
            const content = self.toPlainText(allocator);
            defer allocator.free(content);

            if (content.len == 0) return;

            apptab.updateOutlineForContent(content);
        }
    }
};

pub const AppWindow = struct {
    w: QMainWindow,
    tabs: QTabWidget,

    pub fn create(alloc: std.mem.Allocator) !*AppWindow {
        var ret = try alloc.create(AppWindow);
        errdefer alloc.destroy(ret);

        ret.w = .new2();
        ret.w.setWindowTitle("Markdown Outliner");
        ret.w.resize(900, 600);

        const mnu = QMenuBar.new2();

        file_menu = mnu.addMenu2("&File");

        newtab = file_menu.addAction2("&New Tab");
        const new_tab_key_sequence = QKeySequence.new2("Ctrl+N");
        defer new_tab_key_sequence.delete();
        newtab.setShortcut(new_tab_key_sequence);
        const new_icon = QIcon.fromTheme("document-new");
        defer new_icon.delete();
        newtab.setIcon(new_icon);
        newtab.onTriggered(AppWindow.handleNewTab);

        open = file_menu.addAction2("&Open...");
        const open_key_sequence = QKeySequence.new2("Ctrl+O");
        defer open_key_sequence.delete();
        open.setShortcut(open_key_sequence);
        const open_icon = QIcon.fromTheme("document-open");
        defer open_icon.delete();
        open.setIcon(open_icon);
        open.onTriggered(AppWindow.handleFileOpen);

        _ = file_menu.addSeparator();

        exit = file_menu.addAction2("&Exit");
        const exit_key_sequence = QKeySequence.new2("Ctrl+Q");
        defer exit_key_sequence.delete();
        exit.setShortcut(exit_key_sequence);
        const exit_icon = QIcon.fromTheme("application-exit");
        defer exit_icon.delete();
        exit.setIcon(exit_icon);
        exit.onTriggered(AppWindow.handleExit);

        options_menu = mnu.addMenu2("&Options");

        language_menu = options_menu.addMenu2("&Language");
        const languageIcon = QIcon.fromTheme("preferences-desktop-locale");
        defer languageIcon.delete();
        language_menu.setIcon(languageIcon);
        english = language_menu.addAction2("&English");
        english.setObjectName("en");
        english.onTriggered(onTriggered);
        french = language_menu.addAction2("&French");
        french.setObjectName("fr");
        french.onTriggered(onTriggered);
        spanish = language_menu.addAction2("&Spanish");
        spanish.setObjectName("es");
        spanish.onTriggered(onTriggered);

        _ = options_menu.addMenu(language_menu);

        help_menu = mnu.addMenu2("&Help");
        about = help_menu.addAction2("&About Qt");
        const about_icon = QIcon.fromTheme("help-about");
        defer about_icon.delete();
        about.setIcon(about_icon);
        const about_shortcut_sequence = QKeySequence.new2("F1");
        defer about_shortcut_sequence.delete();
        about.setShortcut(about_shortcut_sequence);
        about.onTriggered(AppWindow.handleAbout);

        ret.w.setMenuBar(mnu);

        const close_key_param = "Ctrl+W";
        const close_key_sequence = QKeySequence.new2(close_key_param);
        defer close_key_sequence.delete();
        const close = ret.w.addAction4(close_key_param, close_key_sequence);
        close.setShortcut(close_key_sequence);
        close.onTriggered(AppWindow.handleCloseCurrentTab);

        ret.tabs = .new(ret.w);
        ret.tabs.setTabsClosable(true);
        ret.tabs.setMovable(true);
        ret.tabs.onTabCloseRequested(AppWindow.handleTabClose);
        ret.w.setCentralWidget(ret.tabs);

        if (builtin.mode == .Debug) {
            const label = QLabel.new3("## NOTE: This is a debug build.\n");
            label.setAlignment(qnamespace_enums.AlignmentFlag.AlignCenter);
            label.setTextFormat(qnamespace_enums.TextFormat.MarkdownText);
            label.setStyleSheet("background-color: rgb(240, 228, 66); color: rgb(0, 0, 0);");

            const status_bar = QStatusBar.new2();
            status_bar.setStyleSheet("background-color: rgb(240, 228, 66);");
            status_bar.addPermanentWidget2(label, 1);
            ret.w.setStatusBar(status_bar);
        }

        ret.createTabWithContents(alloc, "README.md", @embedFile("README.md"));

        try app_window_tab_map.put(alloc, ret.tabs, ret);
        main_window = ret;

        return ret;
    }

    pub fn createTabWithContents(
        self: *AppWindow,
        alloc: std.mem.Allocator,
        tab_title: []const u8,
        tab_content: []const u8,
    ) void {
        const tab = AppTab.create(alloc) catch @panic("Failed to create tab");
        // the new tab is cleaned up during handleTabClose

        tab.text_area.setText(tab_content);

        const icon = QIcon.fromTheme("text-markdown");
        defer icon.delete();

        const tab_idx = self.tabs.addTab2(tab.tab, icon, tab_title);
        self.tabs.setCurrentIndex(tab_idx);
    }

    pub fn handleTabClose(tab: QTabWidget, index: i32) callconv(.c) void {
        if (app_window_tab_map.get(tab)) |appwindow| {
            const widget = appwindow.tabs.widget(index);
            if (widget.ptr == null) return;

            appwindow.tabs.removeTab(index);

            var it = app_tab_map.iterator();
            while (it.next()) |entry| {
                const apptab = entry.value_ptr.*;
                if (apptab.tab.ptr == widget.ptr) {
                    _ = app_tab_map.fetchRemove(.{ .ptr = @ptrCast(apptab.text_area.ptr) });
                    _ = app_tab_map.fetchRemove(.{ .ptr = @ptrCast(apptab.outline.ptr) });
                    apptab.destroy(allocator);
                    break;
                }
            }
        }
    }

    pub fn handleCloseCurrentTab(_: QAction) callconv(.c) void {
        if (main_window.tabs.ptr != null) {
            const current_index = main_window.tabs.currentIndex();
            if (current_index >= 0)
                handleTabClose(main_window.tabs, current_index);
        }
    }

    pub fn handleNewTab(_: QAction) callconv(.c) void {
        main_window.createTabWithContents(allocator, "New Document", "");
    }

    pub fn handleFileOpen(_: QAction) callconv(.c) void {
        const fname = QFileDialog.getOpenFileName4(
            allocator,
            main_window.w,
            "Open markdown file...",
            "",
            "Markdown files (*.md *.txt);;All Files (*)",
        );
        defer allocator.free(fname);

        if (fname.len == 0) return;

        const file = std.Io.Dir.cwd().openFile(io, fname, .{}) catch
            @panic("Failed to open file");
        defer file.close(io);

        var buffer: [4096]u8 = undefined;
        var file_reader = file.reader(io, &buffer);
        const contents = file_reader.interface.allocRemaining(allocator, .unlimited) catch
            @panic("Failed to read file");
        defer allocator.free(contents);

        main_window.createTabWithContents(allocator, std.Io.Dir.path.basename(fname), contents);
    }

    pub fn handleExit(_: QAction) callconv(.c) void {
        QApplication.quit();
    }

    pub fn handleAbout(_: QAction) callconv(.c) void {
        QApplication.aboutQt();
    }
};

pub fn main(init: std.process.Init) !void {
    const argv = try qt6.init(init.gpa, init.minimal.args);
    defer qt6.deinit(init.gpa, argv);
    var argc: i32 = @intCast(argv.len);
    const qapp: QApplication = .new(init.arena.allocator(), &argc, argv);
    defer qapp.delete();

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

        var it = app_tab_map.iterator();
        while (it.next()) |entry| {
            const apptab = entry.value_ptr.*;
            if (apptab.tab.ptr != null) {
                apptab.tab.delete();
                apptab.tab.ptr = null;
                app_tab_map.removeByPtr(entry.key_ptr);
            }
        }
        it = app_tab_map.iterator();
        while (it.next()) |entry| init.gpa.destroy(entry.value_ptr.*);
        app_tab_map.deinit(init.gpa);
        app_window_tab_map.deinit(init.gpa);
    }

    const app = try AppWindow.create(init.gpa);
    defer init.gpa.destroy(app);

    app.w.show();

    _ = QApplication.exec();
}
