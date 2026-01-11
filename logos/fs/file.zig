const std = @import("std");
const uefi = std.os.uefi;

const log = std.log.scoped(.logos);

pub const FileError = error{
    ReadFailed,
    SeekFailed,
    GetInfoFailed,
    FileTooLarge,
};

pub const File = struct {
    handle: *uefi.protocol.File,

    const Self = @This();

    pub fn wrap(handle: *uefi.protocol.File) Self {
        return .{ .handle = handle };
    }

    /// Returns file size in bytes.
    pub fn size(self: Self) !u64 {
        var info_buf: [256]u8 align(@alignOf(uefi.protocol.File.Info.File)) = undefined;
        const info = self.handle.getInfo(.file, &info_buf) catch |err| {
            log.err("Failed to get file info: {}", .{err});
            return FileError.GetInfoFailed;
        };
        return info.file_size;
    }

    /// Reads the entire file into a buffer. Returns slice of actual bytes read.
    pub fn readAll(self: Self, buffer: []u8) ![]u8 {
        const bytes_read = self.handle.read(buffer) catch |err| {
            log.err("Failed to read file: {}", .{err});
            return FileError.ReadFailed;
        };
        return buffer[0..bytes_read];
    }

    /// Reads file at specific offset.
    pub fn readAt(self: Self, offset: u64, buffer: []u8) ![]u8 {
        self.handle.seekAbsolute(offset) catch |err| {
            log.err("Failed to seek to offset {}: {}", .{ offset, err });
            return FileError.SeekFailed;
        };
        return self.readAll(buffer);
    }

    /// Resets file position to beginning.
    pub fn rewind(self: Self) !void {
        self.handle.seekAbsolute(0) catch |err| {
            log.err("Failed to rewind file: {}", .{err});
            return FileError.SeekFailed;
        };
    }

    pub fn close(self: Self) void {
        self.handle.close() catch |err| {
            log.warn("Failed to close file: {}", .{err});
        };
    }
};

/// Reads entire file contents using UEFI pool allocator.
pub fn readFileAlloc(
    boot_services: *uefi.tables.BootServices,
    file: File,
) ![]align(8) u8 {
    const file_size = try file.size();

    if (file_size > std.math.maxInt(usize)) {
        return FileError.FileTooLarge;
    }

    const size_usize: usize = @intCast(file_size);
    const buffer: []align(8) u8 = boot_services.allocatePool(.loader_data, size_usize) catch |err| {
        log.err("Failed to allocate {} bytes for file", .{size_usize});
        return err;
    };

    _ = file.readAll(buffer) catch |err| {
        boot_services.freePool(buffer.ptr) catch {};
        return err;
    };

    return buffer;
}
