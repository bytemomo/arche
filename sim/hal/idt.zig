const DispatchFn = *const fn (u8, u64) void;

pub fn install(
    _: *anyopaque,
    _: u16,
    comptime _: anytype,
    _: DispatchFn,
) void {}

pub fn inject(vector: u8, error_code: u64, dispatch: DispatchFn) void {
    dispatch(vector, error_code);
}
