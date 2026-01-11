const std = @import("std");
const uefi = std.os.uefi;

const log = std.log.scoped(.logos);

pub const SFileSystem = struct {
    fs: *uefi.protocol.SimpleFileSystem = undefined,
    root_dir: *uefi.protocol.File = undefined,

    const Self = @This();

    pub fn init(boot_service: *uefi.tables.BootServices) !Self {
        var fs = SFileSystem{
            .fs = undefined,
            .root_dir = undefined,
        };

        fs.fs = boot_service.locateProtocol(
            uefi.protocol.SimpleFileSystem, null
        ) catch |err| {
            log.err("Failed to locate siple file system protocol!", .{});
            return err;
        } orelse {
            return error.NotFound;
        };

        fs.root_dir = fs.fs.openVolume() catch |err| {
            log.err("Failed to open volume.", .{});
            return err;
        };
        log.info("Opened filesystem volume.", .{});
        return fs;
    }

    // NOTE: I know that this can open only files inside the root,
    // a complete implementation would follow the path and open and
    // read each volume.
    pub fn openFile(self: *const Self, comptime name: [:0]const u8) !*uefi.protocol.File {
        return self.root_dir.open(
            &toUcs2(name), uefi.protocol.File.OpenMode.read, .{}
        ) catch |err| {
            log.err("Failed to open file '{s}'.", .{name});
            return err;
        };
    }

    inline fn toUcs2(comptime s: [:0]const u8) [s.len * 2:0]u16 {
        var ucs2: [s.len * 2:0]u16 = [_:0]u16{0} ** (s.len * 2);
        for (s, 0..) |c, i| {
            ucs2[i] = c;
            ucs2[i + 1] = 0;
        }
        return ucs2;
    }
};
