// Test root — imports all modules to discover their inline tests.
comptime {
    _ = @import("core/types.zig");
    _ = @import("core/boot_info.zig");
    _ = @import("arch/x86_64/mm/types.zig");
    _ = @import("arch/x86_64/mm/paging.zig");
    _ = @import("arch/x86_64/mm/layout.zig");
}
