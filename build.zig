///based on allyourcddebases/SDL3 and Castholm's version
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

//TODO: remove redundancies between core and renderer now that I've merged the libraries

pub fn build(b: *std.Build) !void {
    //Rive is being pulled from github here

    const target = b.standardTargetOptions(.{});

    //TODO: Prefer releaseSmall
    const optimize = b.option(
        std.builtin.OptimizeMode,
        "optimize",
        "Optimization mode (default is small)",
    ) orelse .small;
    // const glfw = b.dependency("glfw", .{
    //     .target = target,
    //     .optimize = optimize,
    // });

    // const glfw_lib = glfw.artifact("glfw");

    // const linuxDeps = b.dependency("sdl_linux_deps", .{});

    var windows = false;
    var linux = false;
    var macos = false;
    // var system_include_path: ?std.Build.LazyPath = null;
    // var system_framework_path: ?std.Build.LazyPath = null;
    // var library_path: ?std.Build.LazyPath = null;
    switch (target.result.os.tag) {
        .windows => {
            windows = true;
        },
        .linux => {
            linux = true;
        },
        .macos => {
            macos = true;

            // //this code is taken from Castholm's SDL port
            // if (b.sysroot) |sysroot| {
            //     system_include_path = .{ .cwd_relative = b.pathJoin(&.{ sysroot, "usr/include" }) };
            //     system_framework_path = .{ .cwd_relative = b.pathJoin(&.{ sysroot, "System/Library/Frameworks" }) };
            //     library_path = .{ .cwd_relative = "/usr/lib" };
            //     // glfw_lib.addSystemIncludePath(.{ .cwd_relative = b.pathJoin(&.{ sysroot, "usr/include" }) });
            //     // glfw_lib.addFrameworkPath(.{ .cwd_relative = b.pathJoin(&.{ sysroot, "System/Library/Frameworks" }) });
            //     // glfw_lib.addLibraryPath(library_path.?);
            // } else if (!target.query.isNative()) {
            //     std.log.err("'--sysroot' is required when building the Rive Renderer for non-native macOS targets. Use xcrun --show-sdk-path.", .{});
            //     std.process.exit(1);
            // }
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

    rive_lib.linker_allow_shlib_undefined = true;

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
    rive_mod.addIncludePath(upstream.path("renderer/include")); //these should only be included if with_canvas is enabled, to do soon
    rive_mod.addIncludePath(upstream.path("dependencies"));
    // rive_mod.addIncludePath(upstream.path("scripting"));

    rive_lib.installHeadersDirectory(upstream.path("include"), "", .{ .include_extensions = &.{ ".h", ".hpp" } });

    //compile Rive source
    rive_mod.addCSourceFiles(try glob(b, .{
        .root = upstream.builder.root,
        .subpath = "src",
        .allowed_exts = &.{".cpp"},
        .recursive = true,
        .exclude = &.{
            "lua_scripted_context.cpp",
            "lua_gpu.cpp",
        },
        .flags = &.{ "-fno-sanitize=pointer-overflow", "" }, //seems like this is necessary for text to work??
    }));
    rive_mod.addCSourceFiles(.{ .files = &.{"no_op_factory.cpp"}, .root = upstream.path("utils") });
    // rive_mod.addCSourceFiles(.{ .files = &riveSource.rive_src, .root = upstream.path("src") });

    rive_mod.addCMacro("_RIVE_INTERNAL_", "");

    //TODO: Make macros optional

    rive_mod.addCMacro("WITH_RIVE_TEXT", "");
    rive_mod.addCMacro("WITH_RIVE_TOOLS", "1");
    rive_mod.addCMacro("WITH_RIVE_LAYOUT", "");
    rive_mod.addCMacro("WITH_RIVE_SCRIPTING", "");
    rive_mod.addCMacro("WITH_RIVE_SCRIPTING_LUAU", "");
    rive_mod.addCMacro("RIVE_CANVAS", "1");
    rive_mod.addCMacro("RIVE_ORE", "");
    rive_mod.addCMacro("ORE_BACKEND_METAL", "");

    //swap scripted context if on mac:
    if (macos) {
        rive_mod.addCSourceFiles(.{
            .root = upstream.path("src/lua"),
            .files = &.{ "renderer/lua_gpu_apple.mm", "lua_scripted_context_apple.mm" },
            .flags = &.{""},
        });
    } else {
        rive_mod.addCSourceFiles(.{
            .root = upstream.path("src/lua"),
            .files = &.{ "renderer/lua_gpu.cpp", "lua_scripted_context.cpp" },
            .flags = &.{""},
        });
    }

    //******RIVE RENDERER*******

    //TODO: Make this optional
    rive_mod.addCMacro("RIVE_DECODERS", "");
    rive_mod.addCMacro("RIVE_PNG", "");
    rive_mod.addCMacro("RIVE_JPEG", "");
    rive_mod.addCMacro("RIVE_WEBP", "");
    rive_mod.addCMacro("RIVE_ORE", "");
    rive_mod.addCMacro("ORE_BACKEND_GL", ""); // this is for rive's GPU canvas
    // Set the include path

    b.dependOnDirectoryContents(upstream.path("src"));

    //compile Rive Renderer

    const dx12_headers = b.dependency("directX", .{});
    const vulkan_headers = b.dependency("Vulkan-Headers", .{});
    const vulkan_memory_allocator = b.dependency("VulkanMemoryAllocator", .{});

    //these decoders' include directories needed for the renderer to compile - flags are off for now, I may add support later

    const astc_encoder = b.dependency("astc_encoder", .{});
    const bc_encoder = b.dependency("bc7enc_rdo", .{});
    // const etc_encoder = b.dependency("ETCPACK", .{});

    rive_mod.addIncludePath(astc_encoder.path("source"));
    rive_mod.addIncludePath(bc_encoder.path(""));
    // rive_mod.addIncludePath(etc_encoder.path("source"));

    //build astc encoder
    rive_mod.addCSourceFiles(try glob(b, .{
        .root = astc_encoder.builder.root,
        .subpath = "source",
        .allowed_exts = &.{".cpp"},
        .prefix = "astcenc_",
        .flags = &.{""},
    }));

    //build bc encoder

    rive_mod.addCSourceFiles(.{ .root = bc_encoder.path(""), .files = &.{
        "bc7decomp.cpp",
        "bc7decomp_ref.cpp",
        "rgbcx.cpp",
    } });

    rive_mod.addIncludePath(upstream.path("renderer/include"));
    rive_mod.addIncludePath(upstream.path("renderer/src"));
    rive_mod.addIncludePath(upstream.path("renderer/ore/metal"));
    rive_mod.addIncludePath(upstream.path("renderer/glad/include"));
    rive_mod.addIncludePath(upstream.path("renderer/glad"));
    rive_mod.addIncludePath(upstream.path("decoders/include"));

    // if (linux) {
    // const libjpeg = b.dependency("libjpeg", .{});
    // rive_mod.linkLibrary(libjpeg.artifact("jpeg"));
    const libpng = b.dependency("libpng", .{});
    rive_mod.linkLibrary(libpng.artifact("png"));
    libpng.artifact("png").bundle_ubsan_rt = true;
    libwebp.build(b, target, optimize, rive_mod);
    libjpeg.build(b, target, optimize, rive_mod);
    // }

    rive_lib.installHeadersDirectory(upstream.path("renderer/include"), "", .{ .include_extensions = &.{ ".h", ".hpp" } });
    rive_lib.installHeadersDirectory(upstream.path("decoders/include"), "", .{ .include_extensions = &.{ ".h", ".hpp" } });
    rive_lib.installHeadersDirectory(upstream.path("renderer/src"), "", .{ .include_extensions = &.{ ".h", ".hpp" } });
    rive_lib.installHeadersDirectory(upstream.path("renderer/glad/include"), "", .{});
    rive_lib.installHeadersDirectory(upstream.path("renderer/glad"), "", .{});

    rive_mod.addCSourceFiles(try glob(b, .{ .root = upstream.builder.root, .subpath = "renderer/src", .allowed_exts = &.{".cpp"}, .flags = &.{
        "-std=c++20",
        "",
    } })); //Zig's Debug mode will panic if c++ standard isn't set to 20+ due to a negative bitwise shift operation
    //make this optional along with the rest of the decoder stuff

    b.dependOnDirectoryContents(upstream.path("renderer/src"));
    rive_mod.addCSourceFiles(try glob(b, .{
        .root = upstream.builder.root,
        .subpath = "decoders/src",
        .allowed_exts = &.{".cpp"},
        .flags = &.{""},
    }));

    rive_mod.addCSourceFiles(try glob(b, .{
        .root = upstream.builder.root,
        .subpath = "renderer/src/ore",
        .allowed_exts = &.{".cpp"},
        .flags = &.{""},
    }));
    rive_mod.addCSourceFiles(try glob(b, .{
        .root = upstream.builder.root,
        .subpath = "renderer/src/ore/gl",
        .allowed_exts = &.{".cpp"},
        .flags = &.{""},
    }));

    if (macos) {
        rive_mod.addCSourceFiles(try glob(b, .{
            .root = upstream.builder.root,
            .subpath = "renderer/src/metal",
            .allowed_exts = &.{".mm"},
            .flags = &.{""},
        }));
        rive_mod.addCSourceFiles(try glob(b, .{
            .root = upstream.builder.root,
            .subpath = "renderer/src/ore/metal",
            .allowed_exts = &.{".mm"},
            .flags = &.{""},
        }));

        rive_mod.addCSourceFiles(try glob(b, .{
            .root = upstream.builder.root,
            .subpath = "renderer/src/ore/gl",
            .allowed_exts = &.{".mm"},
            .flags = &.{""},
        }));
    } else if (windows) {
        rive_mod.addCSourceFiles(try glob(b, .{
            .root = upstream.builder.root,
            .subpath = "renderer/src/vulkan",
            .allowed_exts = &.{".cpp"},
            .flags = &.{""},
        }));

        rive_mod.addCSourceFiles(try glob(b, .{
            .root = upstream.builder.root,
            .subpath = "renderer/src/ore/vulkan",
            .allowed_exts = &.{".cpp"},
            .flags = &.{""},
        }));

        rive_mod.addCSourceFiles(try glob(b, .{
            .root = upstream.builder.root,
            .subpath = "renderer/src/d3d",
            .allowed_exts = &.{".cpp"},
            .flags = &.{""},
        }));

        rive_mod.addCSourceFiles(try glob(b, .{
            .root = upstream.builder.root,
            .subpath = "renderer/src/d3d11",
            .allowed_exts = &.{".cpp"},
            .flags = &.{""},
        }));

        rive_mod.addCSourceFiles(try glob(b, .{
            .root = upstream.builder.root,
            .subpath = "renderer/src/ore/d3d11",
            .flags = &.{""},
            .allowed_exts = &.{".cpp"},
        }));

        rive_mod.addCSourceFiles(try glob(b, .{
            .root = upstream.builder.root,
            .subpath = "renderer/src/d3d12",
            .allowed_exts = &.{".cpp"},
            .flags = &.{""},
        }));

        rive_mod.addCSourceFiles(try glob(b, .{
            .root = upstream.builder.root,
            .subpath = "renderer/src/ore/d3d12",
            .allowed_exts = &.{".cpp"},
            .flags = &.{""},
        }));

        //TODO: Add ORE if rive canvas enabled
    } else if (linux) {
        rive_mod.addCSourceFiles(try glob(b, .{
            .root = upstream.builder.root,
            .subpath = "renderer/src/vulkan",
            .allowed_exts = &.{".cpp"},
            .flags = &.{""},
        }));

        rive_mod.addCSourceFiles(try glob(b, .{
            .root = upstream.builder.root,
            .subpath = "renderer/src/ore/vulkan",
            .allowed_exts = &.{".cpp"},
            .flags = &.{""},
        }));

        rive_mod.addCSourceFiles(try glob(b, .{
            .root = upstream.builder.root,
            .subpath = "renderer/rive_vk_bootstrap/src",
            .allowed_exts = &.{".cpp"},
            .flags = &.{""},
        }));

        rive_mod.addCMacro("RIVE_VULKAN", "");
        rive_mod.addCMacro("VK_NO_PROTOTYPES", "");
        rive_mod.addCMacro("VMA_STATIC_VULKAN_FUNCTIONS", "0");
        rive_mod.addCMacro("VMA_DYNAMIC_VULKAN_FUNCTIONS", "1");

        rive_mod.addIncludePath(vulkan_headers.path("include"));
        rive_mod.addIncludePath(vulkan_memory_allocator.path("include"));
        rive_mod.addIncludePath(upstream.path("renderer/rive_vk_bootstrap/include"));
        rive_mod.addIncludePath(upstream.path("renderer/shader_hotload"));
        rive_mod.addCSourceFile(.{ .file = upstream.path("renderer/shader_hotload/shader_hotload.cpp") });
    }
    rive_mod.addCSourceFiles(.{
        .root = upstream.path("renderer"),
        .files = &.{
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
        },
        .flags = &.{""},
    });

    // platform specific links

    // if (system_include_path) |path| {
    //     rive_mod.addSystemIncludePath(path);
    // }

    // if (system_framework_path) |path| {
    //     rive_mod.addSystemFrameworkPath(path);
    // }
    // if (library_path) |path| {
    //     rive_mod.addLibraryPath(path);
    // }

    rive_mod.addCMacro("RIVE_ORE", ""); // this is for rive's GPU canvas. Make this optional, and also decouple it from target

    if (macos) {
        rive_mod.addCMacro("RIVE_MACOSX", "");
        rive_mod.addCMacro("ORE_BACKEND_METAL", ""); // this is for rive's GPU canvas. Make this optional, and also decouple it from target

        // rive_mod.linkFramework("Metal", .{});
        // rive_mod.linkFramework("Foundation", .{});
        // rive_mod.linkFramework("CoreGraphics", .{});
        // rive_mod.linkFramework("ImageIO", .{});
        // rive_mod.linkFramework("QuartzCore", .{});
        // rive_mod.linkFramework("IOKit", .{});
        // rive_mod.linkSystemLibrary("objc", .{});
    } else if (windows) {
        rive_mod.addIncludePath(dx12_headers.path("include/directx"));
        rive_mod.addCMacro("ORE_BACKEND_D3D11", ""); // this is for rive's GPU canvas
        rive_mod.addCMacro("ORE_BACKEND_D3D12", ""); // this is for rive's GPU canvas
    } else if (linux) {}

    rive_mod.addCMacro("RIVE_DESKTOP_GL", "");
    rive_mod.addCMacro("ORE_BACKEND_VK", ""); // this is for rive's GPU canvas
    rive_mod.addCMacro("ORE_BACKEND_GL", ""); // this is for rive's GPU canvas

    //compile Rive shaders for renderer

    //TODO: see if I can do this directly in zig instead of relying on the makefile

    const make_cmd = b.addSystemCommand(&.{"make"});

    //TODO: Don't require the user to download python ply themselves, this is a regression from 0.16

    // const ply_dep = b.dependency("python_ply", .{});
    // const ply_root: std.Build.Cache.Path = ply_dep.builder.root;
    const shaders_dir = upstream.path("renderer/src/shaders");

    const pls_generated_headers = b.path("zig-out/include/generated/shaders");

    // const string = try std.mem.concat(b.allocator, u8, &.{ "./", try ply_root.toString(b.allocator), "/src" });
    //
    // std.debug.print("pythonpathhhhh: {s}\n", .{string});
    //
    // make_cmd.setEnvironmentVariable("PYTHONPATH", string);

    //construct the make command

    make_cmd.addArg("-C");
    make_cmd.addDirectoryArg(shaders_dir);

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
    rive_lib.step.dependOn(&make_cmd.step);
    rive_mod.addIncludePath(b.path("zig-out/include"));

    // *****PATH FIDDLE******* turning off for now since glfw isn't updated

    const glfw = b.dependency("glfw_zig", .{
        .target = target,
        .optimize = optimize,
    });

    //Note: in order to build the Path Fiddle demo project on Linux, you must have OpenGL dev tools installed even though it will use vulkan by default (i.e. libGL-mesa-dev or equivalent)
    const path_fiddle = b.addExecutable(.{ .name = "path_fiddle", .root_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libcpp = true,
        .link_libc = true,
    }) });

    InstallArtifactFmt(path_fiddle);

    path_fiddle.bundle_ubsan_rt = true;

    path_fiddle.root_module.addCSourceFiles(.{
        .files = &.{ "path_fiddle.cpp", "fiddle_context_gl.cpp", "fiddle_context_vulkan.cpp", "fiddle_context_dawn.cpp", "fiddle_context_d3d.cpp", "fiddle_context_d3d12.cpp", "fiddle_context.cpp" },
        .root = upstream.path("renderer/path_fiddle"),

        .flags = &.{""},
    });

    if (macos) {
        path_fiddle.root_module.addCSourceFiles(.{
            .files = &.{"fiddle_context_metal.mm"},
            .flags = &.{ "-fobjc-arc", "" },
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
    path_fiddle.root_module.linkLibrary(rive_lib);

    path_fiddle.step.dependOn(&rive_lib.step);

    path_fiddle.root_module.linkLibrary(glfw.artifact("glfw"));

    // path_fiddle.root_module.addSystemIncludePath(linuxDeps.path("include"));

    // if (system_framework_path) |path| {
    //     path_fiddle.root_module.addSystemFrameworkPath(path);
    // }

    path_fiddle.root_module.addCMacro("RIVE_DESKTOP_GL", "");
    path_fiddle.root_module.addCMacro("RIVE_CANVAS", "");
    path_fiddle.root_module.addCMacro("RIVE_ORE", "");

    if (macos) {
        path_fiddle.root_module.addCMacro("RIVE_MACOSX", "");
        path_fiddle.root_module.linkFramework("Metal", .{});
        path_fiddle.root_module.linkFramework("QuartzCore", .{});
        path_fiddle.root_module.linkFramework("Cocoa", .{});
        path_fiddle.root_module.linkFramework("IOKit", .{});
        path_fiddle.root_module.linkSystemLibrary("objc", .{});
    }

    const run_exe = b.addRunArtifact(path_fiddle);
    const run_step = b.step("run", "Run Path Fiddle");

    run_step.dependOn(&run_exe.step);
}
