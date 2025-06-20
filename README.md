## Zig-dotenv 

A dotenv library for zig.


### Env

 - Zig >= 0.15.0-dev.337+4e700fdf8


### Adding zig-dotenv as a dependency

Add the dependency to your project:

```sh
zig fetch --save=zig-dotenv git+https://github.com/deatil/zig-dotenv#main
```

or use local path to add dependency at `build.zig.zon` file

```zig
.{
    .dependencies = .{
        .@"zig-dotenv" = .{
            .path = "./lib/zig-dotenv",
        },
        ...
    }
}
```

And the following to your `build.zig` file:

```zig
const zig_totp_dep = b.dependency("zig-dotenv", .{});
exe.root_module.addImport("zig-dotenv", zig_totp_dep.module("zig-dotenv"));
```

The `zig-dotenv` structure can be imported in your application with:

```zig
const dotenv = @import("zig-dotenv");
```


### Get Starting

~~~zig
const std = @import("std");
const dotenv = @import("zig-dotenv");

pub fn main() !void {
    const alloc = std.heap.page_allocator;

    const env_data =
        \\FOO=abc
        \\BAR="def ghi"
        \\# Test
        \\BAZ=xyz
        ;
    
    var env = dotenv.Dotenv.init(alloc);
    defer env.deinit();

    try env.parse(env_data, .{});

    const got_foo = = env.get("FOO").?;

    // output: 
    // dotenv got: abc
    std.debug.print("dotenv got: {s} \n", .{got_foo});
}
~~~


### LICENSE

*  The library LICENSE is `Apache2`, using the library need keep the LICENSE.


### Copyright

*  Copyright deatil(https://github.com/deatil).
