const boot_info = @import("boot_info");
const BootInfo = boot_info.BootInfo;

export fn _start(info: *BootInfo) callconv(.c) noreturn {
    _ = info;

    // asm volatile ("outb %[val], %[port]"
    //     :
    //     : [val] "{al}" (@as(u8, 0)),
    //       [port] "N{dx}" (@as(u16, 0xf4)),
    // );

    while (true) {
        asm volatile ("hlt");
    }
}
