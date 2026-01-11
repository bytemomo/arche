const std = @import("std");
const uefi = std.os.uefi;

const log = std.log.scoped(.logos);

pub const BootServices = struct {
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

    /// Allocates pool memory of specified size.
    pub fn allocPool(self: Self, size: usize) ![]align(8) u8 {
        return self.bs.allocatePool(.loader_data, size) catch |err| {
            log.err("Failed to allocate {} bytes", .{size});
            return err;
        };
    }

    /// Frees pool memory.
    pub fn freePool(self: Self, buffer: []align(8) u8) void {
        self.bs.freePool(buffer.ptr) catch |err| {
            log.warn("Failed to free pool: {}", .{err});
        };
    }

    /// Allocates contiguous physical pages.
    pub fn allocPages(self: Self, count: usize) ![]align(4096) u8 {
        const pages = self.bs.allocatePages(.any, .loader_data, count) catch |err| {
            log.err("Failed to allocate {} pages", .{count});
            return err;
        };
        return pages[0 .. count * 4096];
    }

    /// Frees allocated pages.
    pub fn freePages(self: Self, pages: []align(4096) u8) void {
        const count = (pages.len + 4095) / 4096;
        self.bs.freePages(@alignCast(@ptrCast(pages.ptr)), count) catch |err| {
            log.warn("Failed to free pages: {}", .{err});
        };
    }

    /// Returns info about memory map size needed.
    pub fn getMemoryMapInfo(self: Self) !uefi.tables.MemoryMapInfo {
        return self.bs.getMemoryMapInfo() catch |err| {
            log.err("Failed to get memory map info: {}", .{err});
            return err;
        };
    }

    /// Gets the current memory map. Buffer must be properly sized.
    pub fn getMemoryMap(
        self: Self,
        buffer: []align(@alignOf(uefi.tables.MemoryDescriptor)) u8,
    ) !uefi.tables.MemoryMapSlice {
        return self.bs.getMemoryMap(buffer) catch |err| {
            log.err("Failed to get memory map: {}", .{err});
            return err;
        };
    }

    /// Exits boot services. After this call, boot services are no longer available.
    /// Returns the final memory map key needed for kernel handoff.
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

    /// Returns the underlying UEFI boot services pointer.
    pub fn raw(self: Self) *uefi.tables.BootServices {
        return self.bs;
    }
};

/// Retrieves the UEFI image handle.
pub fn getImageHandle() !uefi.Handle {
    return uefi.system_table.handle orelse {
        log.err("Image handle not available", .{});
        return error.ImageHandleUnavailable;
    };
}
