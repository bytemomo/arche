pub fn lgdt(base: u64, limit: u16) void {
    const gdtr: packed struct(u80) {
        limit: u16,
        base: u64,
    } = .{ .limit = limit, .base = base };

    asm volatile ("lgdt (%[gdtr])"
        :
        : [gdtr] "r" (&gdtr),
        : .{ .memory = true });
}

pub fn ltr(sel: u16) void {
    asm volatile (
        \\ltr %[sel]
        :
        : [sel] "r" (sel),
    );
}

pub fn loadCs(comptime sel: u16) void {
    asm volatile (
        \\pushq %[cs]
        \\leaq 1f(%%rip), %%rax
        \\pushq %%rax
        \\lretq
        \\1:
        :
        : [cs] "i" (@as(u64, sel)),
        : .{ .rax = true, .memory = true });
}

pub fn loadDs(comptime sel: u16) void {
    asm volatile (
        \\movw %[ds], %%ax
        \\movw %%ax, %%ds
        \\movw %%ax, %%es
        \\movw %%ax, %%ss
        \\xorw %%ax, %%ax
        \\movw %%ax, %%fs
        \\movw %%ax, %%gs
        :
        : [ds] "i" (sel),
        : .{ .rax = true });
}
