const std = @import("std");
const arch = @import("arch");
const Services = @import("../../uefi/services.zig").Services;

const log = std.log.scoped(.logos);

const PML4 = arch.paging.PML4;
const PML4E = arch.paging.PML4E;
const PDPT = arch.paging.PDPT;
const PDPTE = arch.paging.PDPTE;
const PD = arch.paging.PD;
const PDE = arch.paging.PDE;
const VirtAddr = arch.paging.VirtAddr;
const Flags = arch.paging.Flags;

const PAGE_SIZE = arch.paging.PAGE_SIZE;
const LARGE_PAGE_SIZE = arch.paging.LARGE_PAGE_SIZE;

pub const PageTables = struct {
    pml4: *align(PAGE_SIZE) PML4,
    services: Services,

    const Self = @This();

    pub fn init(services: Services) !Self {
        const pml4 = try allocTable(PML4, services);
        pml4.* = PML4.empty();
        return .{
            .pml4 = pml4,
            .services = services,
        };
    }

    /// Identity map a range using 2MB large pages.
    pub fn identityMap2M(self: *Self, start: u64, size: u64, flags: Flags) !void {
        const aligned_start = arch.paging.alignDown(start, LARGE_PAGE_SIZE);
        const aligned_end = arch.paging.alignUp(start + size, LARGE_PAGE_SIZE);

        var addr = aligned_start;
        while (addr < aligned_end) : (addr += LARGE_PAGE_SIZE) {
            try self.mapLargePage(addr, addr, flags);
        }

        log.debug("Identity mapped 0x{x}-0x{x} ({} MB)", .{
            aligned_start,
            aligned_end,
            (aligned_end - aligned_start) / (1024 * 1024),
        });
    }

    /// Map a single 2MB large page.
    fn mapLargePage(self: *Self, virt: u64, phys: u64, flags: Flags) !void {
        const va = VirtAddr.from(virt);

        if (!self.pml4.getEntry(va.pml4Index()).isPresent()) {
            const pdpt = try allocTable(PDPT, self.services);
            pdpt.* = PDPT.empty();
            self.pml4.setEntry(va.pml4Index(), PML4E.table(pdpt, .{ .writable = true }));
        }

        const pdpt = self.pml4.getEntry(va.pml4Index()).getPDPT().?;

        if (!pdpt.getEntry(va.pdptIndex()).isPresent()) {
            const pd = try allocTable(PD, self.services);
            pd.* = PD.empty();
            pdpt.setEntry(va.pdptIndex(), PDPTE.table(pd, .{ .writable = true }));
        }

        const pd = pdpt.getEntry(va.pdptIndex()).getPD().?;

        pd.setEntry(va.pdIndex(), PDE.largePage(phys, flags));
    }

    /// Get CR3 value (physical address of PML4).
    pub fn getCr3(self: *const Self) u64 {
        return @intFromPtr(self.pml4);
    }
};

/// Allocate a zeroed page-aligned table.
fn allocTable(comptime T: type, services: Services) !*align(PAGE_SIZE) T {
    const pages = try services.allocPages(1);
    const ptr: *align(PAGE_SIZE) T = @ptrCast(&pages[0]);
    return ptr;
}
