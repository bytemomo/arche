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

pub fn lidt(base: u64, limit: u16) void {
    const idtr: packed struct(u80) {
        limit: u16,
        base: u64,
    } = .{ .limit = limit, .base = base };

    asm volatile ("lidt (%[idtr])"
        :
        : [idtr] "r" (&idtr),
        : .{ .memory = true });
}

pub fn halt() noreturn {
    asm volatile ("cli");
    while (true) {
        asm volatile ("hlt");
    }
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

pub fn readCr3() u64 {
    return asm volatile ("mov %%cr3, %[ret]"
        : [ret] "=r" (-> u64),
        :
        : .{ .memory = true });
}

pub fn readCr2() u64 {
    return asm volatile("mov %%cr2, %[ret]"
        : [ret] "=r" (-> u64),
        :
        : .{ .memory = true }
    );
}

pub fn switchStackAndCall(
    stack_top: u64,
    func: *const fn () noreturn,
) noreturn {
    asm volatile (
        \\mov %[sp], %%rsp
        \\xor %%rbp, %%rbp
        \\jmp *%[entry]
        :
        : [sp] "r" (stack_top),
          [entry] "r" (func),
        : .{ .memory = true }
    );
    unreachable;
}

pub fn writeCr3(addr: u64) void {
    asm volatile ("mov %[cr3], %%cr3"
        :
        : [cr3] "r" (addr),
        : .{ .memory = true });
}
