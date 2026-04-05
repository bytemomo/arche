pub const MAX_VECTORS = 256;
pub const Handler = *const fn (vector: u8, error_code: u64) void;

var handlers: [MAX_VECTORS]Handler = [_]Handler{unhandled} ** MAX_VECTORS;

pub fn register(vector: u8, h: Handler) void {
    handlers[vector] = h;
}

pub fn dispatch(vector: u8, error_code: u64) void {
    handlers[vector](vector, error_code);
}

fn unhandled(_: u8, _: u64) void {}
