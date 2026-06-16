const std = @import("std");
const host_os = @import("builtin").target.os.tag;

const configureQtExeRootModule = @import("libqt6zig").configureQtExeRootModule;

var qt_dir: []const u8 = "";

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const extra_paths = b.option([]const []const u8, "extra-paths", "Extra library header and include search paths") orelse &.{};

    const is_windows = target.result.os.tag == .windows or host_os == .windows;

    if (is_windows) {
        qt_dir = b.option([]const u8, "QTDIR", "The directory where Qt is installed") orelse win_root;
        std.Io.Dir.cwd().access(b.graph.io, qt_dir, .{}) catch {
            std.log.err("QTDIR '{s}' does not exist\n", .{qt_dir});
            return error.QTDIRNotFound;
        };
    }

    const qt6zig = b.dependency("libqt6zig", .{
        .target = target,
        .optimize = optimize,
        .@"extra-paths" = extra_paths,
    });

    const exe = b.addExecutable(.{
        .name = "mdoutliner",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/mdoutliner/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.root_module.addImport("libqt6zig", qt6zig.module("libqt6zig"));

    // Link libqt6zig static libraries
    for (qt_libraries) |lib|
        exe.root_module.linkLibrary(qt6zig.artifact(lib));

    if (optimize == .Debug)
        for (debug_libraries) |lib|
            exe.root_module.linkLibrary(qt6zig.artifact(lib));

    // Create a check step
    const check_step = b.step("check", "Check the build without generating an executable");
    check_step.dependOn(&exe.step);

    // Create a run step
    const exe_install = b.addInstallArtifact(exe, .{});
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(&exe_install.step);

    const build_run_step = b.step("run", "Build and run the demo");
    build_run_step.dependOn(&run_cmd.step);
    var win_steps = [_]*std.Build.Step{&run_cmd.step};

    const win_libs: []const []const u8 = if (is_windows) &.{
        "libc++",
        "libunwind",
        "opengl32sw",
    } else &.{};

    // Configure Qt system libraries
    try configureQtExeRootModule(b, exe, .{
        .extra_paths = extra_paths,
        .win_libs = win_libs,
        .win_qt_dir = qt_dir,
        .win_root = qt_dir,
        .win_steps = if (is_windows) &win_steps else &.{},
    });

    // Install the executable
    b.installArtifact(exe);
}

const win_root = "C:/Qt/6.8.3/llvm-mingw_64";

const qt_libraries = [_][]const u8{
    "qaction",
    "qactiongroup",
    "qapplication",
    "qboxlayout",
    "qcoreapplication",
    "qfiledialog",
    "qicon",
    "qkeysequence",
    "qlistwidget",
    "qlocale",
    "qmainwindow",
    "qmenu",
    "qmenubar",
    "qobject",
    "qresource",
    "qsplitter",
    "qtabwidget",
    "qtextcursor",
    "qtextdocument",
    "qtextedit",
    "qtextobject",
    "qtranslator",
    "qvariant",
    "qwidget",
};

const debug_libraries = [_][]const u8{
    "qlabel",
    "qstatusbar",
};
