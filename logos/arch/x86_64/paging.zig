const std = @import("std");
const arch = @import("arch");
const Services = @import("../../uefi/services.zig").Services;

const log = std.log.scoped(.paging);

const paging = arch.paging;
const PML4 = paging.PML4;
const PML4E = paging.PML4E;
const PDPT = paging.PDPT;
const PDPTE = paging.PDPTE;
const PD = paging.PD;
const PDE = paging.PDE;

const Phys = paging.Phys;
const Virt = paging.Virt;
const Size = arch.types.Size;
const Flags = paging.Flags;

const PAGE_SIZE = paging.PAGE_SIZE;
const LARGE_PAGE_SIZE = paging.LARGE_PAGE_SIZE;

pub const PageTables = struct {
    pml4: *align(PAGE_SIZE) PML4,
    services: Services,

    const Self = @This();

    /// Initialize new page tables by allocating a fresh writable PML4.
    pub fn init(services: Services) !Self {
        const pml4 = try allocTable(PML4, services);
        pml4.* = PML4.empty();

        log.debug("Allocated new PML4 at 0x{x}", .{@intFromPtr(pml4)});

        return .{
            .pml4 = pml4,
            .services = services,
        };
    }

    /// Identity map a range using 2MB large pages.
    pub fn identityMap2M(self: *Self, start: Phys, size: Size, flags: Flags) !void {
        const aligned_start = start.alignDown(LARGE_PAGE_SIZE);
        const end = start.add(size.raw());
        const aligned_end = end.alignUp(LARGE_PAGE_SIZE);

        var addr = aligned_start;
        while (addr.raw() < aligned_end.raw()) : (addr = addr.add(LARGE_PAGE_SIZE)) {
            try self.mapLargePage(Virt.from(addr.raw()), addr, flags);
        }

        log.debug("Identity mapped 0x{x}-0x{x} ({} MB)", .{
            aligned_start.raw(),
            aligned_end.raw(),
            (aligned_end.raw() - aligned_start.raw()) / (1024 * 1024),
        });
    }

    /// Map a single 2MB large page.
    pub fn mapLargePage(self: *Self, virt: Virt, phys: Phys, flags: Flags) !void {
        if (!self.pml4.getEntry(virt.pml4Index()).isPresent()) {
            const pdpt = try allocTable(PDPT, self.services);
            pdpt.* = PDPT.empty();
            self.pml4.setEntry(virt.pml4Index(), PML4E.table(Phys.fromPtr(pdpt), .{ .writable = true }));
        }

        const pdpt_phys = self.pml4.getEntry(virt.pml4Index()).getPDPT().?;
        const pdpt: *PDPT = pdpt_phys.toPtr(*PDPT);

        if (!pdpt.getEntry(virt.pdptIndex()).isPresent()) {
            const pd = try allocTable(PD, self.services);
            pd.* = PD.empty();
            pdpt.setEntry(virt.pdptIndex(), PDPTE.table(Phys.fromPtr(pd), .{ .writable = true }));
        }

        const pd_phys = pdpt.getEntry(virt.pdptIndex()).getPD().?;
        const pd: *PD = pd_phys.toPtr(*PD);

        pd.setEntry(virt.pdIndex(), PDE.largePage(phys, flags));
    }

    /// Get CR3 value (physical address of PML4).
    pub fn getCr3(self: *const Self) Phys {
        return Phys.fromPtr(self.pml4);
    }

    /// Load these page tables into CR3 (flush the TLB).
    pub fn load(self: *const Self) void {
        const cr3 = self.getCr3().raw();
        asm volatile ("mov %[cr3], %%cr3"
            :
            : [cr3] "r" (cr3),
        );
        log.debug("Loaded CR3=0x{x}", .{cr3});
    }
};

/// Allocate a zeroed page-aligned table.
fn allocTable(comptime T: type, services: Services) !*align(PAGE_SIZE) T {
    const pages = try services.allocPages(1);
    const ptr: *align(PAGE_SIZE) T = @ptrCast(&pages[0]);
    return ptr;
}
