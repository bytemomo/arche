const gdt = @import("gdt.zig");
const idt = @import("idt.zig");

pub const MAX_VECTORS = idt.TABLE_LEN;

pub fn init() void {
    gdt.init();
    idt.init();
}
