const std = @import("std");
const uefi = std.os.uefi;

const log = std.log.scoped(.logos);

pub const Services = struct {
    bs: *uefi.tables.BootServices,

    const Self = @This();

    pub fn init() !Self {
        const bs = uefi.system_table.boot_services orelse {
            log.err("Boot services not available", .{});
            return error.BootServicesUnavailable;
        };
        return .{ .bs = bs };
    }

    pub fn stall(self: Self, microseconds: usize) void {
        self.bs.stall(microseconds) catch {};
    }

    pub fn stallMs(self: Self, milliseconds: usize) void {
        self.stall(milliseconds * 1000);
    }

    pub fn stallSec(self: Self, seconds: usize) void {
        self.stall(seconds * 1000 * 1000);
    }

    pub fn allocPool(self: Self, size: usize) ![]align(8) u8 {
        return self.bs.allocatePool(.loader_data, size) catch |err| {
            log.err("Failed to allocate {} bytes", .{size});
            return err;
        };
    }

    pub fn freePool(self: Self, buffer: []align(8) u8) void {
        self.bs.freePool(buffer.ptr) catch |err| {
            log.warn("Failed to free pool: {}", .{err});
        };
    }

    pub fn allocPages(self: Self, count: usize) ![]align(4096) uefi.Page {
        return self.bs.allocatePages(.any, .loader_data, count) catch |err| {
            log.err("Failed to allocate {} pages", .{count});
            return err;
        };
    }

    pub fn freePages(self: Self, pages: []align(4096) uefi.Page) void {
        self.bs.freePages(pages.ptr, pages.len) catch |err| {
            log.warn("Failed to free pages: {}", .{err});
        };
    }

    pub fn getMemoryMapInfo(self: Self) !uefi.tables.MemoryMapInfo {
        return self.bs.getMemoryMapInfo() catch |err| {
            log.err("Failed to get memory map info: {}", .{err});
            return err;
        };
    }

    pub fn getMemoryMap(
        self: Self,
        buffer: []align(@alignOf(uefi.tables.MemoryDescriptor)) u8,
    ) !uefi.tables.MemoryMapSlice {
        return self.bs.getMemoryMap(buffer) catch |err| {
            log.err("Failed to get memory map: {}", .{err});
            return err;
        };
    }

    pub fn exitBootServices(
        self: Self,
        image_handle: uefi.Handle,
        map_key: uefi.tables.MemoryMapKey,
    ) !void {
        self.bs.exitBootServices(image_handle, map_key) catch |err| {
            log.err("Failed to exit boot services: {}", .{err});
            return err;
        };
    }

    pub fn raw(self: Self) *uefi.tables.BootServices {
        return self.bs;
    }
};

pub fn getImageHandle() !uefi.Handle {
    return uefi.system_table.handle orelse {
        log.err("Image handle not available", .{});
        return error.ImageHandleUnavailable;
    };
}
