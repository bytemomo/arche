
export fn _entry() callconv(.naked) noreturn {
    while (true) {
        asm volatile("hlt");
    }
}
