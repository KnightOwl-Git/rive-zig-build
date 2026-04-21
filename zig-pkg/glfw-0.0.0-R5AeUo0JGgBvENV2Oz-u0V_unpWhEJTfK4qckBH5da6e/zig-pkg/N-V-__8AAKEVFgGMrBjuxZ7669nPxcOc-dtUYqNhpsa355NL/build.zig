const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addLibrary(.{
        .name = "vulkan-headers",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .static,
    });
    lib.root_module.addCSourceFile(.{
        .file = b.addWriteFiles().add("empty.c", ""),
    });

    inline for (.{ "vk_video", "vulkan" }) |subdir| {
        lib.installHeadersDirectory(b.path("include/" ++ subdir), subdir, .{});
    }
    b.installArtifact(lib);
}
