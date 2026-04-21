# libjpeg
This is [libjpeg](https://ijg.org/) packaged for zig.

## How to use it

First, update your `build.zig.zon`:

```
zig fetch --save https://github.com/timsurber/libjpeg/archive/refs/heads/main.zip
```

Next, add this snippet to your `build.zig` script:

```zig

const libjpeg_dep = b.dependency("libjpeg", .{
    .target = target,
    .optimize = optimize,
});
your_compilation.linkLibrary(libjpeg_dep.artifact("jpeg"));
```

This will provide libjpeg as a static library to `your_compilation`.