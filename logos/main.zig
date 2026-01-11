const std = @import("std");
const option = @import("option");

const Log = @import("log.zig");

const sfs = @import("fs/sfs.zig");
const file = @import("fs/file.zig");

const boot_srv = @import("protocol/boot_srv.zig");

const uefi = std.os.uefi;

const File = file.File;
const Console = Log.UefiConsole;
const BootServices = boot_srv.BootServices;

pub const std_options = std.Options{
    .log_level = switch (option.log_level) {
        .debug => .debug,
        .info => .info,
        .warn => .warn,
        .err => .err,
    },
    .logFn = Log.myLogFn,
};
const log = std.log.scoped(.logos);

pub fn main() uefi.Status {
    {
        const con_out = uefi.system_table.con_out orelse return .aborted;

        Console.init(con_out);
        Console.clear_screen();
        log.info("Hello world from Zig UEFI!", .{});
    }


    const bs = BootServices.init() catch return .aborted;
    log.info("Got boot services.", .{});

    {
        const simplefs = sfs.SFileSystem.init(bs.raw()) catch return .aborted;
        const kernel_handle = simplefs.openFile("kyber.elf") catch |err| {
            log.err("Failed to open kyber.elf: {}", .{err});
            return .aborted;
        };
        const kernel_file = File.wrap(kernel_handle);
        defer kernel_file.close();

        const kernel_size = kernel_file.size() catch return .aborted;
        log.info("Opened kernel file, size: {} bytes", .{kernel_size});

        const kernel_data = file.readFileAlloc(bs.raw(), kernel_file) catch return .aborted;
        log.info("Loaded kernel into memory at 0x{x}", .{@intFromPtr(kernel_data.ptr)});

        { // Parse header
            var reader = std.Io.Reader.fixed(kernel_data);
            const kernel_elf_header = std.elf.Header.read(&reader) catch |err| {
                log.err("Failed to read ELF header: {}", .{err});
                return .aborted;
            };
            log.info(
                \\ELF: 64-bit={} endian={s} type={s} machine={s}
                \\     entry=0x{x} phnum={} shnum={}
            ,
                .{
                    kernel_elf_header.is_64,
                    @tagName(kernel_elf_header.endian),
                    @tagName(kernel_elf_header.type),
                    @tagName(kernel_elf_header.machine),
                    kernel_elf_header.entry,
                    kernel_elf_header.phnum,
                    kernel_elf_header.shnum,
                },
            );
        }
    }

    bs.stallSec(5);

    return .success;
}
