
const mm = @import("mm/init.zig");
const gdt = @import("gdt.zig");
const idt = @import("idt.zig");
const boot_info = @import("../../core/boot_info.zig");

pub const MAX_VECTORS = idt.TABLE_LEN;

pub fn init(info: *boot_info.BootInfo) void {
    gdt.init();
    idt.init();
    mm.init(info);
}
