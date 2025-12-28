const std = @import("std");
const host_os = @import("builtin").os.tag;

var qt_dir: []const u8 = "";

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const extra_paths = b.option([]const []const u8, "extra-paths", "Extra library header and include search paths") orelse &.{};

    var optimize = b.standardOptimizeOption(.{});
    if (optimize == .Debug) optimize = .ReleaseFast;

    const is_macos = target.result.os.tag == .macos or host_os == .macos;
    const is_windows = target.result.os.tag == .windows or host_os == .windows;

    if (is_windows) {
        qt_dir = b.option([]const u8, "QTDIR", "The directory where Qt is installed") orelse win_root;
        std.fs.cwd().access(qt_dir, .{}) catch {
            std.log.err("QTDIR '{s}' does not exist\n", .{qt_dir});
            return error.QTDIRNotFound;
        };
    }

    const base_libs = switch (is_macos) {
        true => [_][]const u8{
            "QtCore",
            "QtGui",
            "QtWidgets",
        },
        false => [_][]const u8{
            "Qt6Core",
            "Qt6Gui",
            "Qt6Widgets",
        },
    };

    const qt6zig = b.dependency("libqt6zig", .{
        .target = target,
        .optimize = if (optimize == .Debug) .ReleaseFast else optimize,
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

    // Link Qt system libraries
    const sub_paths = [_][]const u8{ "/bin", "/lib", "" };

    for (extra_paths) |path| {
        for (sub_paths) |sub_path| {
            const extra_path = b.fmt("{s}{s}", .{ path, sub_path });
            std.fs.cwd().access(extra_path, .{}) catch {
                continue;
            };
            exe.root_module.addLibraryPath(.{ .cwd_relative = extra_path });
            if (is_macos)
                exe.root_module.addFrameworkPath(.{ .cwd_relative = extra_path });
        }
    }

    if (is_bsd_host)
        exe.root_module.addLibraryPath(.{ .cwd_relative = "/usr/local/lib/qt6" });
    if (is_macos) {
        exe.root_module.addFrameworkPath(.{ .cwd_relative = "/opt/homebrew/Frameworks" });
        exe.root_module.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/lib" });
    }
    if (is_windows) {
        const win_bin_dir = win_root ++ "/bin";
        var ok_bin_dir = true;
        std.fs.cwd().access(win_bin_dir, .{}) catch {
            if (extra_paths.len == 0) {
                std.log.err("'{s}' either does not exist or does not have a 'bin' subdirectory and no extra paths were provided\n", .{win_root});
                return error.WinQtBinDirNotFound;
            } else {
                ok_bin_dir = false;
            }
        };
        if (ok_bin_dir) {
            exe.root_module.addLibraryPath(.{ .cwd_relative = win_bin_dir });
        }
    }

    for (base_libs) |lib| {
        if (is_macos) {
            exe.root_module.linkFramework(lib, .{});
        } else {
            exe.root_module.linkSystemLibrary(lib, .{});
        }
    }

    if (is_linux_host) {
        exe.root_module.link_libcpp = false;

        const result = try std.process.Child.run(.{
            .allocator = b.allocator,
            .argv = &.{ "gcc", "--print-file-name=libstdc++.so.6" },
        });
        exe.root_module.addObjectFile(.{
            .cwd_relative = std.mem.trim(u8, result.stdout, &std.ascii.whitespace),
        });

        exe.root_module.linkSystemLibrary("unwind", .{});
    }

    // Link libqt6zig static libraries
    for (qt_libraries) |lib| {
        exe.root_module.linkLibrary(qt6zig.artifact(lib));
    }

    // Create a check step
    const check_step = b.step("check", "Check the build without generating an executable");
    check_step.dependOn(&exe.step);

    // Install the executable
    b.installArtifact(exe);

    // Create a run step
    const exe_install = b.addInstallArtifact(exe, .{});
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(&exe_install.step);

    const build_run_step = b.step("run", "Build and run the demo");
    build_run_step.dependOn(&run_cmd.step);

    if (is_windows) {
        const win_libs = base_libs ++ .{
            "libc++",
            "libunwind",
            "opengl32sw",
        };

        for (win_libs) |lib| {
            const bin_path = b.fmt("bin/{s}.dll", .{lib});
            const dll_path = b.fmt("{s}/{s}", .{ qt_dir, bin_path });
            std.fs.cwd().access(dll_path, .{}) catch {
                continue;
            };
            const install_win_dll = b.addInstallFile(.{ .cwd_relative = dll_path }, bin_path);
            run_cmd.step.dependOn(&install_win_dll.step);
        }

        const plugins_path = b.fmt("{s}/plugins", .{qt_dir});
        std.fs.cwd().access(plugins_path, .{}) catch {
            std.log.err("Plugins path '{s}' does not exist\n", .{plugins_path});
            return error.PluginsPathNotFound;
        };
        const install_plugins = b.addInstallDirectory(.{
            .source_dir = .{ .cwd_relative = plugins_path },
            .install_dir = .prefix,
            .install_subdir = "bin/plugins",
        });
        run_cmd.step.dependOn(&install_plugins.step);
    }
}

const is_bsd_host = switch (host_os) {
    .dragonfly, .freebsd, .netbsd, .openbsd => true,
    else => false,
};

const is_linux_host = switch (host_os) {
    .linux => true,
    else => false,
};

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
