const cpu = @import("cpu.zig");

const DispatchFn = *const fn (u8, u64) void;
const Gate = packed struct(u128) { low: u64, high: u64 };
const Exception = struct {
    vector: u8,
    has_error_code: bool,
    gate_type: u4,
    ist: u3,
};

var dispatch_fn: ?DispatchFn = null;

export fn isrCommon() callconv(.naked) void {
    asm volatile (
        \\pushq %%rax
        \\pushq %%rbx
        \\pushq %%rcx
        \\pushq %%rdx
        \\pushq %%rsi
        \\pushq %%rdi
        \\pushq %%rbp
        \\pushq %%r8
        \\pushq %%r9
        \\pushq %%r10
        \\pushq %%r11
        \\pushq %%r12
        \\pushq %%r13
        \\pushq %%r14
        \\pushq %%r15
        \\movq %%rsp, %%rdi
        \\movabsq %[handler], %%rax
        \\callq *%%rax
        \\popq %%r15
        \\popq %%r14
        \\popq %%r13
        \\popq %%r12
        \\popq %%r11
        \\popq %%r10
        \\popq %%r9
        \\popq %%r8
        \\popq %%rbp
        \\popq %%rdi
        \\popq %%rsi
        \\popq %%rdx
        \\popq %%rcx
        \\popq %%rbx
        \\popq %%rax
        \\addq $16, %%rsp
        \\iretq
        :
        : [handler] "i" (&trampoline),
    );
}

var last_fault_rip: u64 = 0;
var last_fault_cs: u64 = 0;
var last_fault_rflags: u64 = 0;

pub fn lastRip() u64 { return last_fault_rip; }
pub fn lastCs() u64 { return last_fault_cs; }
pub fn lastRflags() u64 { return last_fault_rflags; }

/// Index into the interrupt frame
const Slot = enum(usize) {
    r15 = 0,
    r14 = 1,
    r13 = 2,
    r12 = 3,
    r11 = 4,
    r10 = 5,
    r9 = 6,
    r8 = 7,
    rbp = 8,
    rdi = 9,
    rsi = 10,
    rdx = 11,
    rcx = 12,
    rbx = 13,
    rax = 14,
    vector = 15,
    error_code = 16,
    rip = 17,
    cs = 18,
    rflags = 19,
    rsp = 20,
    ss = 21,
};

fn trampoline(frame: *anyopaque) callconv(.c) void {
    if (dispatch_fn) |f| {
        const stack: [*]const u64 = @ptrCast(@alignCast(frame));

        last_fault_rip = stack[@intFromEnum(Slot.rip)];
        last_fault_cs = stack[@intFromEnum(Slot.cs)];
        last_fault_rflags = stack[@intFromEnum(Slot.rflags)];
        f(
            @truncate(stack[@intFromEnum(Slot.vector)]),
            stack[@intFromEnum(Slot.error_code)],
        );
    }
}

fn makeStub(
    comptime vector: u8,
    comptime has_error_code: bool,
) u64 {
    const S = struct {
        fn stub() callconv(.naked) void {
            if (!has_error_code) {
                asm volatile ("pushq $0");
            }
            asm volatile ("pushq %[vec]"
                :
                : [vec] "i" (@as(u8, vector)),
            );
            asm volatile ("jmp isrCommon");
        }
    };
    return @intFromPtr(&S.stub);
}

pub fn install(
    table_ptr: *anyopaque,
    cs: u16,
    comptime exceptions: anytype,
    dispatch: DispatchFn,
) void {
    dispatch_fn = dispatch;
    const table: *[256][2]u64 = @ptrCast(@alignCast(table_ptr));
    inline for (exceptions) |exc| {
        const vec: u8 = @intFromEnum(exc.vector);
        const addr = makeStub(vec, exc.vector.hasErrorCode());
        const gate = encodeGate(addr, cs, exc.ist, @intFromEnum(exc.gate_type), 0);
        table[vec] = .{ gate.low, gate.high };
    }
    cpu.lidt(@intFromPtr(table_ptr), 256 * 16 - 1);
}

pub fn inject(_: u8, _: u64, _: DispatchFn) void {
    @panic("inject not available on real hardware");
}

fn encodeGate(addr: u64, sel: u16, ist: u3, gate_type: u4, dpl: u2) Gate {
    const low: u64 = @as(u64, @as(u16, @truncate(addr))) |
        (@as(u64, sel) << 16) |
        (@as(u64, ist) << 32) |
        (@as(u64, gate_type) << 40) |
        (@as(u64, dpl) << 45) |
        (1 << 47) | // present
        (@as(u64, @as(u16, @truncate(addr >> 16))) << 48);
    const high: u64 = @as(u64, @as(u32, @truncate(addr >> 32)));
    return .{ .low = low, .high = high };
}
