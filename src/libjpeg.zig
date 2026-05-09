//OLD: USING ZIG DEPENDENCY INSTEAD... or maybe not?

const std = @import("std");
const util = @import("util.zig");

pub fn build(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, mod: *std.Build.Module) void {
    const upstream = b.dependency("libjpeg", .{});
    const libjpeg = util.addRiveDep(b, "libjpeg", target, optimize, .c);

    const InlineKeyword = enum { __inline__ };
    const config_header = b.addConfigHeader(.{
        .style = .{ .autoconf_undef = upstream.path("jconfig.cfg") },
        .include_path = "jconfig.h",
    }, .{
        .HAVE_PROTOTYPES = true,
        .HAVE_UNSIGNED_CHAR = true,
        .HAVE_UNSIGNED_SHORT = true,
        .void = null,
        .@"const" = null,
        .CHAR_IS_UNSIGNED = null,
        .HAVE_STDDEF_H = true,
        .HAVE_STDLIB_H = true,
        .HAVE_LOCALE_H = true,
        .NEED_BSD_STRINGS = null,
        .NEED_SYS_TYPES_H = null,
        .NEED_FAR_POINTERS = null,
        .NEED_SHORT_EXTERNAL_NAMES = null,
        .INCOMPLETE_TYPES_BROKEN = null,
        .RIGHT_SHIFT_IS_UNSIGNED = null,
        .INLINE = InlineKeyword.__inline__,
        .DEFAULT_MAX_MEM = null,
        .NO_MKTEMP = null,
        .RLE_SUPPORTED = null,
        .TWO_FILE_COMMANDLINE = null,
        .NEED_SIGNAL_CATCHER = null,
        .DONT_USE_B_MODE = null,
        .PROGRESS_REPORT = null,
    });

    libjpeg.root_module.addIncludePath(upstream.path("libjpeg"));
    libjpeg.root_module.addConfigHeader(config_header);
    libjpeg.root_module.addCSourceFiles(.{ .files = &.{
        "jaricom.c",
        "jcapimin.c",
        "jcapistd.c",
        "jcarith.c",
        "jccoefct.c",
        "jccolor.c",
        "jcdctmgr.c",
        "jchuff.c",
        "jcinit.c",
        "jcmainct.c",
        "jcmarker.c",
        "jcmaster.c",
        "jcomapi.c",
        "jcparam.c",
        "jcprepct.c",
        "jcsample.c",
        "jctrans.c",
        "jdapimin.c",
        "jdapistd.c",
        "jdarith.c",
        "jdatadst.c",
        "jdatasrc.c",
        "jdcoefct.c",
        "jdcolor.c",
        "jddctmgr.c",
        "jdhuff.c",
        "jdinput.c",
        "jdmainct.c",
        "jdmarker.c",
        "jdmaster.c",
        "jdmerge.c",
        "jdpostct.c",
        "jdsample.c",
        "jdtrans.c",
        "jerror.c",
        "jfdctflt.c",
        "jfdctfst.c",
        "jfdctint.c",
        "jidctflt.c",
        "jidctfst.c",
        "jidctint.c",
        "jquant1.c",
        "jquant2.c",
        "jutils.c",
        "jmemmgr.c",
        "jmemansi.c",
    }, .root = upstream.path("") });

    libjpeg.root_module.addIncludePath(upstream.path(""));
    // mod.addIncludePath(upstream.path(""));
    mod.linkLibrary(libjpeg);
}
