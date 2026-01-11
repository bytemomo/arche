const std = @import("std");
const uefi = std.os.uefi;

const log = std.log.scoped(.logos);

pub const SFileSystem = struct {
    fs: *uefi.protocol.SimpleFileSystem = undefined,
    root_dir: *uefi.protocol.File = undefined,

    const Self = @This();

    /// Initialize the filesystem.
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

    /// Open a file in the SimpleFS.
    pub fn openFile(self: *const Self, path: []const u8) !*uefi.protocol.File {
        var current = self.root_dir;
        var iter = std.mem.splitScalar(u8, path, '/');

        while (iter.next()) |component| {
            if (component.len == 0) continue;

            var buf: [255:0]u16 = undefined;
            const ucs2 = toUcs2Runtime(component, &buf) orelse {
                log.err("Path component too long: {s}", .{component});
                return error.PathTooLong;
            };

            const next = current.open(ucs2, .read, .{}) catch |err| {
                log.err("Failed to open '{s}': {}", .{ component, err });
                if (current != self.root_dir) current.close() catch {};
                return err;
            };

            if (current != self.root_dir) current.close() catch {};
            current = next;
        }
        return current;
    }

    /// Convert a UTF-8 string to a UCS-2 string.
    fn toUcs2Runtime(s: []const u8, buf: *[255:0]u16) ?[:0]const u16 {
        if (s.len > buf.len) return null;
        for (s, 0..) |c, i| buf[i] = c;
        buf[s.len] = 0;
        return buf[0..s.len :0];
    }
};
