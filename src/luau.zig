const std = @import("std");
const util = @import("util.zig");
const glob = util.glob;

pub fn build(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, mod: *std.Build.Module) !void {
    const luau_upstream = b.dependency("luau", .{});
    const libHydrogen_upstream = b.dependency("libhydrogen", .{});

    const luau = b.addLibrary(.{
        .name = "luau",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libcpp = true,
            .link_libc = true,
        }),
    });

    luau.root_module.addIncludePath(luau_upstream.path("VM/include"));
    luau.root_module.addIncludePath(luau_upstream.path("Common/include"));

    const root: std.Build.Cache.Path = luau_upstream.builder.root;

    std.debug.print("luau: {s}\n", .{root.sub_path});
    luau.root_module.addCSourceFiles(try glob(b, .{ .root = luau_upstream.builder.root, .subpath = "VM/src", .allowed_exts = &.{".cpp"}, .recursive = true }));
    // luau.root_module.addCSourceFiles(try glob(b, .{ .root = luau_upstream.path("Compiler/src"), .allowed_exts = &.{".cpp"}, .recursive = true }));
    luau.root_module.addCSourceFiles(.{ .files = &.{"libhydrogen.c"}, .root = libHydrogen_upstream.path("") });
    //
    // luau.linkLibrary(libHydrogen_upstream.artifact("hydrogen"));
    luau.root_module.addCMacro("LUA_USE_LONGJMP", "TRUE");

    luau.root_module.addCMacro("RIVE_LUAU", "");

    luau.root_module.addIncludePath(luau_upstream.path("VM/include"));
    luau.root_module.addIncludePath(luau_upstream.path("VM/src"));
    // luau.root_module.addIncludePath(luau_upstream.path("Compiler/src"));
    // luau.root_module.addIncludePath(luau_upstream.path("Compiler/include"));
    // luau.root_module.addIncludePath(luau_upstream.path("Ast/include"));
    // luau.root_module.addIncludePath(luau_upstream.path("Common/include"));
    mod.addIncludePath(luau_upstream.path("VM/include"));
    mod.addIncludePath(luau_upstream.path("VM/src"));
    // mod.addIncludePath(luau_upstream.path("Compiler/src"));
    mod.addIncludePath(libHydrogen_upstream.path(""));
    mod.linkLibrary(luau);
}
