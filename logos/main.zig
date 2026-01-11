const std = @import("std");
const option = @import("option");

const Log = @import("log.zig");
const services = @import("uefi/services.zig");
const fs = @import("uefi/fs.zig");
const paging = @import("arch/x86_64/paging.zig");
const arch = @import("arch");

const uefi = std.os.uefi;

const Services = services.Services;
const FileSystem = fs.FileSystem;
const PageTables = paging.PageTables;

pub const std_options = std.Options{
    .log_level = switch (option.log_level) {
        .debug => .debug,
        .info => .info,
        .warn => .warn,
        .err => .err,
    },
    .logFn = Log.logFn,
};

const log = std.log.scoped(.logos);

pub fn main() uefi.Status {
    Log.init() catch return .aborted;
    log.info("Logos bootloader starting", .{});

    const svc = Services.init() catch return .aborted;
    log.info("Boot services initialized", .{});

    const filesystem = FileSystem.init(svc) catch return .aborted;

    {   // TODO: Move into loader
        const kernel_file = filesystem.open("kyber.elf") catch |err| {
            log.err("Failed to open kyber.elf: {}", .{err});
            return .aborted;
        };
        defer kernel_file.close();

        const kernel_size = kernel_file.size() catch return .aborted;
        log.info("Kernel file size: {} bytes", .{kernel_size});

        const kernel_data = kernel_file.readAlloc(svc) catch return .aborted;
        log.info("Kernel loaded at 0x{x}", .{@intFromPtr(kernel_data.ptr)});

        var reader = std.Io.Reader.fixed(kernel_data);
        const elf_header = std.elf.Header.read(&reader) catch |err| {
            log.err("Failed to parse ELF header: {}", .{err});
            return .aborted;
        };

        log.info(
            \\ELF: 64-bit={} endian={s} type={s} machine={s}
            \\     entry=0x{x} phnum={} shnum={}
            ,
            .{
                elf_header.is_64,
                @tagName(elf_header.endian),
                @tagName(elf_header.type),
                @tagName(elf_header.machine),
                elf_header.entry,
                elf_header.phnum,
                elf_header.shnum,
            },
        );
    }

    var page_tables = PageTables.init(svc) catch |err| {
        log.err("Failed to init page tables: {}", .{err});
        return .aborted;
    };

    page_tables.identityMap2M(arch.paging.Phys.from(0), 4 * 1024 * 1024 * 1024, .{ .writable = true }) catch |err| {
        log.err("Failed to identity map: {}", .{err});
        return .aborted;
    };
    log.info("Page tables ready, CR3=0x{x}", .{page_tables.getCr3().raw()});

    svc.stallSec(5);

    return .success;
}
