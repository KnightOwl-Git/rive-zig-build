///based on allyourcodebases/SDL3 and Castholm's version
const std = @import("std");
const util = @import("src/util.zig");
const glob = util.glob;
const InstallArtifactFmt = util.InstallArtifactFmt;

const riveSource = @import("src/rive.zon");

//Libraries Rive depends on
const yoga = @import("src/yoga.zig");
const sheenbidi = @import("src/sheenbidi.zig");
const harfbuzz = @import("src/harfbuzz.zig");
const luau = @import("src/luau.zig");
// const libpng = @import("src/libpng.zig");
const libjpeg = @import("src/libjpeg.zig");
const libwebp = @import("src/libwebp.zig");

pub const rive_options = &.{
    "no-scripting",
    "no-layout",
    "no-decoders",
    "no-text",
    "no-audio",
};

pub fn build(b: *std.Build) !void {
    //Rive is being pulled from github here

    const target = b.standardTargetOptions(.{});

    //TODO: Prefer releaseSmall
    const optimize = b.option(
        std.builtin.OptimizeMode,
        "optimize",
        "Optimization mode (default is ReleaseSmall)",
    ) orelse .ReleaseSmall;

    // const glfw = b.dependency("glfw", .{
    //     .target = target,
    //     .optimize = optimize,
    // });

    // const glfw_lib = glfw.artifact("glfw");

    const linuxDeps = b.dependency("sdl_linux_deps", .{});

    var windows = false;
    var linux = false;
    var macos = false;
    var system_include_path: ?std.Build.LazyPath = null;
    var system_framework_path: ?std.Build.LazyPath = null;
    var library_path: ?std.Build.LazyPath = null;
    switch (target.result.os.tag) {
        .windows => {
            windows = true;
        },
        .linux => {
            linux = true;
        },
        .macos => {
            macos = true;

            //this code is taken from Castholm's SDL port
            if (b.sysroot) |sysroot| {
                system_include_path = .{ .cwd_relative = b.pathJoin(&.{ sysroot, "usr/include" }) };
                system_framework_path = .{ .cwd_relative = b.pathJoin(&.{ sysroot, "System/Library/Frameworks" }) };
                library_path = .{ .cwd_relative = "/usr/lib" };
                // glfw_lib.addSystemIncludePath(.{ .cwd_relative = b.pathJoin(&.{ sysroot, "usr/include" }) });
                // glfw_lib.addFrameworkPath(.{ .cwd_relative = b.pathJoin(&.{ sysroot, "System/Library/Frameworks" }) });
                // glfw_lib.addLibraryPath(library_path.?);
            } else if (!target.query.isNative()) {
                std.log.err("'--sysroot' is required when building the Rive Renderer for non-native macOS targets. Use xcrun --show-sdk-path.", .{});
                std.process.exit(1);
            }
        },
        else => {},
    }

    const linkage = b.option(
        std.builtin.LinkMode,
        "linkage",
        "whether to build a static or dynamic library, defaults to static",
    ) orelse .static;

    //Dependencies

    const upstream = b.dependency("rive", .{});

    //********RIVE CORE**********

    const rive_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libcpp = true,
        .link_libc = true,
    });

    const rive_lib = b.addLibrary(.{
        .name = "rive",
        .root_module = rive_mod,
        .linkage = linkage,
    });

    InstallArtifactFmt(rive_lib);

    //optional dependencies

    //is there a way for both of these functions to use the same parameters?
    yoga.build(b, target, optimize, rive_mod);
    sheenbidi.build(b, target, optimize, rive_mod);
    harfbuzz.build(b, target, optimize, rive_mod);
    try luau.build(b, target, optimize, rive_mod);

    // const libpng = b.dependency("libpng", .{});
    // rive_mod.linkLibrary(libpng.artifact("png"));

    rive_mod.addIncludePath(upstream.path("include"));
    rive_mod.addIncludePath(upstream.path("dependencies"));
    // rive_mod.addIncludePath(upstream.path("scripting"));

    rive_lib.installHeadersDirectory(upstream.path("include"), "", .{ .include_extensions = &.{ ".h", ".hpp" } });

    //compile Rive source
    rive_mod.addCSourceFiles(try glob(b, .{ .root = upstream.path("src"), .allowed_exts = &.{".cpp"}, .recursive = true })); //Zig's Debug mode will panic if c++ standard isn't set to 20+ due to a negative bitwise shift operation
    // rive_mod.addCSourceFiles(.{ .files = &riveSource.rive_src, .root = upstream.path("src") });
    rive_mod.addCMacro("_RIVE_INTERNAL_", "");

    //TODO: Make macros optional

    rive_mod.addCMacro("WITH_RIVE_TEXT", "");
    rive_mod.addCMacro("WITH_RIVE_LAYOUT", "");
    rive_mod.addCMacro("WITH_RIVE_SCRIPTING", "");

    //******RIVE RENDERER*******

    const rive_renderer_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libcpp = true,
        .link_libc = true,
    });

    //TODO:next, figure out how to merge the two libraries for easier use

    const rive_renderer_lib = b.addLibrary(.{
        .name = "rive_renderer",
        .root_module = rive_renderer_mod,
        .linkage = linkage,
    });

    InstallArtifactFmt(rive_renderer_lib);

    //TODO: Make this optional
    rive_renderer_mod.addCMacro("RIVE_DECODERS", "");
    rive_renderer_mod.addCMacro("RIVE_PNG", "");
    rive_renderer_mod.addCMacro("RIVE_JPEG", "");
    rive_renderer_mod.addCMacro("RIVE_WEBP", "");

    // Set the include path

    //compile Rive Renderer

    const dx12_headers = b.dependency("directX", .{});
    const vulkan_headers = b.dependency("Vulkan-Headers", .{});
    const vulkan_memory_allocator = b.dependency("VulkanMemoryAllocator", .{});

    // rive_renderer_mod.addIncludePath(upstream.path("include"));
    rive_renderer_mod.linkLibrary(rive_lib);
    rive_renderer_mod.addIncludePath(upstream.path("renderer/include"));
    rive_renderer_mod.addIncludePath(upstream.path("renderer/src"));
    rive_renderer_mod.addIncludePath(upstream.path("renderer/glad/include"));
    rive_renderer_mod.addIncludePath(upstream.path("renderer/glad"));
    rive_renderer_mod.addIncludePath(upstream.path("decoders/include"));

    // if (linux) {
    // const libjpeg = b.dependency("libjpeg", .{});
    // rive_renderer_mod.linkLibrary(libjpeg.artifact("jpeg"));
    const libpng = b.dependency("libpng", .{});
    rive_renderer_mod.linkLibrary(libpng.artifact("png"));
    libwebp.build(b, target, optimize, rive_renderer_mod);
    libjpeg.build(b, target, optimize, rive_mod);
    // }

    rive_renderer_lib.installHeadersDirectory(upstream.path("renderer/include"), "", .{ .include_extensions = &.{ ".h", ".hpp" } });
    rive_renderer_lib.installHeadersDirectory(upstream.path("renderer/src"), "", .{ .include_extensions = &.{ ".h", ".hpp" } });
    rive_renderer_lib.installHeadersDirectory(upstream.path("renderer/glad/include"), "", .{});
    rive_renderer_lib.installHeadersDirectory(upstream.path("renderer/glad"), "", .{});

    rive_renderer_mod.addCSourceFiles(try glob(b, .{ .root = upstream.path("renderer/src"), .allowed_exts = &.{".cpp"}, .flags = &.{"-std=c++20"} })); //Zig's Debug mode will panic if c++ standard isn't set to 20+ due to a negative bitwise shift operation
    //make this optional along with the rest of the decoder stuff
    rive_renderer_mod.addCSourceFiles(try glob(b, .{ .root = upstream.path("decoders/src"), .allowed_exts = &.{".cpp"} }));

    if (macos) {
        rive_renderer_mod.addCSourceFiles(try glob(b, .{
            .root = upstream.path("renderer/src/metal"),
            .allowed_exts = &.{".mm"},
        }));
    } else if (windows) {
        rive_renderer_mod.addCSourceFiles(try glob(b, .{
            .root = upstream.path("renderer/src/vulkan"),
            .allowed_exts = &.{".mm"},
        }));

        rive_renderer_mod.addCSourceFiles(try glob(b, .{
            .root = upstream.path("renderer/src/d3d"),
            .allowed_exts = &.{".cpp"},
        }));

        rive_renderer_mod.addCSourceFiles(try glob(b, .{
            .root = upstream.path("renderer/src/d3d11"),
            .allowed_exts = &.{".cpp"},
        }));

        rive_renderer_mod.addCSourceFiles(try glob(b, .{
            .root = upstream.path("renderer/src/d3d12"),
            .allowed_exts = &.{".cpp"},
        }));
    } else if (linux) {
        rive_renderer_mod.addCSourceFiles(try glob(b, .{
            .root = upstream.path("renderer/src/vulkan"),
            .allowed_exts = &.{".cpp"},
        }));

        rive_renderer_mod.addCSourceFiles(try glob(b, .{
            .root = upstream.path("renderer/rive_vk_bootstrap/src"),
            .allowed_exts = &.{".cpp"},
        }));

        rive_renderer_mod.addCMacro("RIVE_VULKAN", "");
        rive_renderer_mod.addCMacro("VK_NO_PROTOTYPES", "");
        rive_renderer_mod.addCMacro("VMA_STATIC_VULKAN_FUNCTIONS", "0");
        rive_renderer_mod.addCMacro("VMA_DYNAMIC_VULKAN_FUNCTIONS", "1");

        rive_renderer_mod.addIncludePath(vulkan_headers.path("include"));
        rive_renderer_mod.addIncludePath(vulkan_memory_allocator.path("include"));
        rive_renderer_mod.addIncludePath(upstream.path("renderer/rive_vk_bootstrap/include"));
        rive_renderer_mod.addIncludePath(upstream.path("renderer/shader_hotload"));
        rive_renderer_mod.addCSourceFile(.{ .file = upstream.path("renderer/shader_hotload/shader_hotload.cpp") });
    }
    rive_renderer_mod.addCSourceFiles(.{ .root = upstream.path("renderer"), .files = &.{
        "src/gl/gl_state.cpp",
        "src/gl/gl_utils.cpp",
        "src/gl/load_store_actions_ext.cpp",
        "src/gl/render_buffer_gl_impl.cpp",
        "src/gl/render_context_gl_impl.cpp",
        "src/gl/render_target_gl.cpp",
        "src/gl/pls_impl_webgl.cpp",
        "src/gl/pls_impl_rw_texture.cpp",
        "glad/src/egl.c",
        "glad/src/gles2.c",
        "glad/glad_custom.c",
    } });

    // platform specific links

    if (system_include_path) |path| {
        rive_renderer_mod.addSystemIncludePath(path);
    }

    if (system_framework_path) |path| {
        rive_renderer_mod.addSystemFrameworkPath(path);
    }
    if (library_path) |path| {
        rive_renderer_mod.addLibraryPath(path);
    }

    if (macos) {
        rive_renderer_mod.addCMacro("RIVE_MACOSX", "");
        rive_renderer_mod.linkFramework("Metal", .{});
        rive_renderer_mod.linkFramework("Foundation", .{});
    } else if (windows) {
        rive_renderer_mod.addIncludePath(dx12_headers.path("include/directx"));
    } else if (linux) {}
    rive_renderer_mod.addCMacro("RIVE_DESKTOP_GL", "");

    //compile Rive shaders for renderer

    //TODO: see if I can do this directly in zig instead of relying on the makefile

    const make_cmd = b.addSystemCommand(&.{"make"});

    const ply_dep = b.dependency("python_ply", .{});
    const ply_path = ply_dep.path("src");
    const ply_path_resolved = ply_path.getPath(b);
    const shaders_dir = upstream.path("renderer/src/shaders");

    const shaders_dir_resolved = shaders_dir.getPath(b);

    const pls_generated_headers = b.path("zig-out/include/generated/shaders");

    make_cmd.setEnvironmentVariable("PYTHONPATH", ply_path_resolved);

    //construct the make command

    make_cmd.addArg("-C");
    make_cmd.addArg(shaders_dir_resolved);

    const nproc = std.Thread.getCpuCount() catch 1;
    make_cmd.addArg(b.fmt("-j{d}", .{nproc}));

    make_cmd.addPrefixedDirectoryArg("OUT=", pls_generated_headers);
    // make_cmd.addArg(b.fmt("FLAGS='-p {s}'", .{ply_path_resolved}));

    if (macos) {
        make_cmd.addArg("rive_pls_macosx_metallib");
    } else if (windows) {
        make_cmd.addArg("d3d");
        // make_cmd.addArg("spirv");
    } else if (linux) {
        make_cmd.addArg("spirv");
    }
    rive_renderer_lib.step.dependOn(&make_cmd.step);
    rive_renderer_mod.addIncludePath(b.path("zig-out/include"));

    // *****PATH FIDDLE*******

    //Note: in order to build the Path Fiddle demo project on Linux, you must have OpenGL dev tools installed even though it will use vulkan by default (i.e. libGL-mesa-dev or equivalent)
    const path_fiddle = b.addExecutable(.{ .name = "path_fiddle", .root_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libcpp = true,
        .link_libc = true,
    }) });

    // InstallArtifactFmt(path_fiddle);

    path_fiddle.bundle_ubsan_rt = true;

    path_fiddle.root_module.addCSourceFiles(.{
        .files = &.{ "path_fiddle.cpp", "fiddle_context_gl.cpp", "fiddle_context_vulkan.cpp", "fiddle_context_dawn.cpp", "fiddle_context_d3d.cpp", "fiddle_context_d3d12.cpp" },
        .root = upstream.path("renderer/path_fiddle"),
    });

    if (macos) {
        path_fiddle.root_module.addCSourceFiles(.{
            .files = &.{"fiddle_context_metal.mm"},
            .flags = &.{"-fobjc-arc"},
            .root = upstream.path("renderer/path_fiddle"),
        });
    }
    if (linux) {
        path_fiddle.root_module.addCMacro("RIVE_VULKAN", "");
        // path_fiddle.root_module.addIncludePath(vulkan_headers.path("include"));
        // path_fiddle.root_module.addIncludePath(vulkan_memory_allocator.path("include"));
        path_fiddle.root_module.addIncludePath(upstream.path("renderer/rive_vk_bootstrap/include"));
        path_fiddle.root_module.addIncludePath(upstream.path("renderer/shader_hotload"));

        // path_fiddle.root_module.linkSystemLibrary("GL", .{});
        // const opengl_headers = b.lazyDependency("mesa", .{}).?.path("include");
        // path_fiddle.root_module.addIncludePath(opengl_headers);
    }
    path_fiddle.root_module.linkLibrary(rive_renderer_lib);
    path_fiddle.root_module.linkLibrary(rive_lib);

    path_fiddle.step.dependOn(&rive_renderer_lib.step);
    //NOTE:Path fiddle is broken for now since I don't have a working glfw dependency at the moment

    // path_fiddle.root_module.linkLibrary(glfw_lib);

    path_fiddle.root_module.addSystemIncludePath(linuxDeps.path("include"));

    //
    // if (target.query.isNative()) {
    //     path_fiddle.root_module.linkSystemLibrary("jpeg", .{});
    //     path_fiddle.root_module.linkSystemLibrary("png", .{});
    //     path_fiddle.root_module.linkSystemLibrary("webp", .{});
    // }

    if (system_framework_path) |path| {
        path_fiddle.root_module.addSystemFrameworkPath(path);
    }

    path_fiddle.root_module.addCMacro("RIVE_DESKTOP_GL", "");
    if (macos) {
        path_fiddle.root_module.addCMacro("RIVE_MACOSX", "");
        path_fiddle.root_module.linkFramework("Metal", .{});
        path_fiddle.root_module.linkSystemLibrary("objc", .{});
    }

    const run_exe = b.addRunArtifact(path_fiddle);
    const run_step = b.step("run", "Run Path Fiddle");

    run_step.dependOn(&run_exe.step);
}
