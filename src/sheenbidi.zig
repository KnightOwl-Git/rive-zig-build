const std = @import("std");

pub fn build(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, mod: *std.Build.Module) void {
    const upstream = b.dependency("sheenbidi", .{});
    const sheenbidi = b.addLibrary(.{
        .name = "sheenbidi",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    sheenbidi.root_module.addCSourceFiles(.{ .files = &.{
        "BidiChain.c",
        "BidiTypeLookup.c",
        "BracketQueue.c",
        "GeneralCategoryLookup.c",
        "IsolatingRun.c",
        "LevelRun.c",
        "PairingLookup.c",
        "RunQueue.c",
        "SBAlgorithm.c",
        "SBBase.c",
        "SBCodepointSequence.c",
        "SBLine.c",
        "SBLog.c",
        "SBMirrorLocator.c",
        "SBParagraph.c",
        "SBScriptLocator.c",
        "ScriptLookup.c",
        "ScriptStack.c",
        "StatusStack.c",
    }, .root = upstream.path("Source") });

    sheenbidi.root_module.addIncludePath(upstream.path("Headers"));
    mod.addIncludePath(upstream.path("Headers"));
    mod.linkLibrary(sheenbidi);
}
