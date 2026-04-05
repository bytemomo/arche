var gdtr_base: u64 = 0;
var gdtr_limit: u16 = 0;
var idtr_base: u64 = 0;
var idtr_limit: u16 = 0;
var tr: u16 = 0;
var cs: u16 = 0;
var ds: u16 = 0;

pub fn lgdt(base: u64, limit: u16) void {
    gdtr_base = base;
    gdtr_limit = limit;
}

pub fn ltr(sel: u16) void {
    tr = sel;
}

pub fn lidt(base: u64, limit: u16) void {
    idtr_base = base;
    idtr_limit = limit;
}

pub fn loadCs(comptime sel: u16) void {
    cs = sel;
}

pub fn loadDs(comptime sel: u16) void {
    ds = sel;
}

pub fn halt() noreturn {
    while (true) {}
}

pub fn readCr3() u64 {
    return 0;
}

pub fn switchStackAndCall(_: u64, func: *const fn () noreturn) noreturn {
    func();
}

pub fn writeCr3(_: u64) void {}
