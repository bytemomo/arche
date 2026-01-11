const std = @import("std");
const uefi = std.os.uefi;
const Services = @import("services.zig").Services;

const log = std.log.scoped(.logos);

pub const FileSystem = struct {
    proto: *uefi.protocol.SimpleFileSystem,
    root: *uefi.protocol.File,

    const Self = @This();

    pub fn init(services: Services) !Self {
        const proto = services.raw().locateProtocol(
            uefi.protocol.SimpleFileSystem,
            null,
        ) catch |err| {
            log.err("Failed to locate simple file system protocol", .{});
            return err;
        } orelse {
            return error.NotFound;
        };

        const root = proto.openVolume() catch |err| {
            log.err("Failed to open volume", .{});
            return err;
        };

        log.info("Opened filesystem volume", .{});
        return .{ .proto = proto, .root = root };
    }

    pub fn open(self: *const Self, path: []const u8) !File {
        var current = self.root;
        var iter = std.mem.splitScalar(u8, path, '/');

        while (iter.next()) |component| {
            if (component.len == 0) continue;

            var buf: [255:0]u16 = undefined;
            const ucs2 = toUcs2(component, &buf) orelse {
                log.err("Path component too long: {s}", .{component});
                return error.PathTooLong;
            };

            const next = current.open(ucs2, .read, .{}) catch |err| {
                log.err("Failed to open '{s}': {}", .{ component, err });
                if (current != self.root) current.close() catch {};
                return err;
            };

            if (current != self.root) current.close() catch {};
            current = next;
        }

        return File{ .handle = current };
    }

    fn toUcs2(s: []const u8, buf: *[255:0]u16) ?[:0]const u16 {
        if (s.len > buf.len) return null;
        for (s, 0..) |c, i| buf[i] = c;
        buf[s.len] = 0;
        return buf[0..s.len :0];
    }
};

pub const File = struct {
    handle: *uefi.protocol.File,

    const Self = @This();

    pub fn size(self: Self) !u64 {
        var info_buf: [256]u8 align(@alignOf(uefi.protocol.File.Info.File)) = undefined;
        const info = self.handle.getInfo(.file, &info_buf) catch |err| {
            log.err("Failed to get file info: {}", .{err});
            return error.GetInfoFailed;
        };
        return info.file_size;
    }

    pub fn read(self: Self, buffer: []u8) ![]u8 {
        const bytes_read = self.handle.read(buffer) catch |err| {
            log.err("Failed to read file: {}", .{err});
            return error.ReadFailed;
        };
        return buffer[0..bytes_read];
    }

    pub fn readAt(self: Self, offset: u64, buffer: []u8) ![]u8 {
        self.handle.seekAbsolute(offset) catch |err| {
            log.err("Failed to seek to offset {}: {}", .{ offset, err });
            return error.SeekFailed;
        };
        return self.read(buffer);
    }

    pub fn rewind(self: Self) !void {
        self.handle.seekAbsolute(0) catch |err| {
            log.err("Failed to rewind file: {}", .{err});
            return error.SeekFailed;
        };
    }

    pub fn close(self: Self) void {
        self.handle.close() catch |err| {
            log.warn("Failed to close file: {}", .{err});
        };
    }

    pub fn readAlloc(self: Self, services: Services) ![]align(8) u8 {
        const file_size = try self.size();

        if (file_size > std.math.maxInt(usize)) {
            return error.FileTooLarge;
        }

        const size_usize: usize = @intCast(file_size);
        const buffer = try services.allocPool(size_usize);

        _ = self.read(buffer) catch |err| {
            services.freePool(buffer);
            return err;
        };

        return buffer;
    }
};
