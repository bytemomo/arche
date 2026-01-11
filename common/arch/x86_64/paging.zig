//! x86_64 4-level paging structures.
//! Each level has a distinct type for compile-time safety.
//!
//! Virtual Address (48-bit canonical):
//! ┌────────────┬────────────┬────────────┬────────────┬──────────────┐
//! │   PML4     │    PDPT    │     PD     │     PT     │    Offset    │
//! │  (9 bits)  │  (9 bits)  │  (9 bits)  │  (9 bits)  │   (12 bits)  │
//! │   47:39    │   38:30    │   29:21    │   20:12    │    11:0      │
//! └────────────┴────────────┴────────────┴────────────┴──────────────┘
//!
//! Page Table Hierarchy:
//!
//!     CR3
//!      │
//!      ▼
//!   ┌──────┐
//!   │ PML4 │ ────────────────────────────────────────┐
//!   └──┬───┘                                         │
//!      │ 512 entries                                 │
//!      ▼                                             │
//!   ┌──────┐                                         │
//!   │ PDPT │ ─────────────────────────┐              │
//!   └──┬───┘                          │              │
//!      │ 512 entries                  │              │
//!      ├────────────────┐             │              │
//!      ▼                ▼             ▼              │
//!   ┌──────┐      ┌──────────┐   ┌──────────┐        │
//!   │  PD  │      │ 1GB Page │   │ 512 × 1GB│        │
//!   └──┬───┘      └──────────┘   │ = 512GB  │        │
//!      │ 512 entries    ▲        └──────────┘        │
//!      ├─────────┐      │ PS=1                       │
//!      ▼         ▼      │                            │
//!   ┌──────┐  ┌──────────┐                           │
//!   │  PT  │  │ 2MB Page │                           │
//!   └──┬───┘  └──────────┘                           │
//!      │ 512 entries                                 │
//!      ▼                                             │
//!   ┌──────────┐                                     │
//!   │ 4KB Page │                                     │
//!   └──────────┘                                     │
//!                                                    │
//!                                                    │
//!         Entries x Size                             |
//!   PML4:     512 × 512GB = 256TB (full 48-bit) ◄────┘
//!   PDPT:     512 × 1GB   = 512GB
//!   PD:       512 × 2MB   = 1GB
//!   PT:       512 × 4KB   = 2MB

pub const PAGE_SIZE = 4096;
pub const PAGE_SHIFT = 12;
pub const LARGE_PAGE_SIZE = 2 * 1024 * 1024;
pub const LARGE_PAGE_SHIFT = 21;
pub const HUGE_PAGE_SIZE = 1024 * 1024 * 1024;
pub const HUGE_PAGE_SHIFT = 30;

pub const ENTRIES_PER_TABLE = 512;

/// Mapping flags for pages and tables.
pub const Flags = struct {
    writable: bool = true,
    user: bool = false,
    no_execute: bool = false,
    global: bool = false,
    write_through: bool = false,
    cache_disable: bool = false,
};

/// Raw page table entry - (PML4E, PDPTE, PDE, PTE)
pub const RawEntry = packed struct(u64) {
    present: bool = false,
    writable: bool = false,
    user: bool = false,
    write_through: bool = false,
    cache_disable: bool = false,
    accessed: bool = false,
    dirty: bool = false,
    huge_page: bool = false,
    global: bool = false,
    available: u3 = 0,
    phys_addr: u40 = 0,
    available2: u11 = 0,
    no_execute: bool = false,

    pub fn empty() RawEntry {
        return .{};
    }

    pub fn getPhysAddr(self: RawEntry) u64 {
        return @as(u64, self.phys_addr) << PAGE_SHIFT;
    }

    pub fn isPresent(self: RawEntry) bool {
        return self.present;
    }

    pub fn isHuge(self: RawEntry) bool {
        return self.huge_page;
    }
};

/// PML4 Entry - points to PDPT.
pub const PML4E = struct {
    raw: RawEntry,

    pub fn empty() PML4E {
        return .{ .raw = RawEntry.empty() };
    }

    pub fn table(pdpt: *PDPT, flags: Flags) PML4E {
        return .{ .raw = .{
            .present = true,
            .writable = flags.writable,
            .user = flags.user,
            .write_through = flags.write_through,
            .cache_disable = flags.cache_disable,
            .phys_addr = @truncate(@intFromPtr(pdpt) >> PAGE_SHIFT),
        } };
    }

    pub fn getPDPT(self: PML4E) ?*PDPT {
        if (!self.raw.isPresent()) return null;
        return @ptrFromInt(self.raw.getPhysAddr());
    }

    pub fn isPresent(self: PML4E) bool {
        return self.raw.isPresent();
    }
};

/// PML4 Table - 512 entries, each pointing to a PDPT.
pub const PML4 = struct {
    entries: [ENTRIES_PER_TABLE]PML4E,

    pub fn empty() PML4 {
        return .{ .entries = [_]PML4E{PML4E.empty()} ** ENTRIES_PER_TABLE };
    }

    pub fn setEntry(self: *PML4, index: u9, entry: PML4E) void {
        self.entries[index] = entry;
    }

    pub fn getEntry(self: *const PML4, index: u9) PML4E {
        return self.entries[index];
    }
};

/// PDPT Entry - points to PD or maps 1GB huge page.
pub const PDPTE = struct {
    raw: RawEntry,

    pub fn empty() PDPTE {
        return .{ .raw = RawEntry.empty() };
    }

    pub fn table(pd: *PD, flags: Flags) PDPTE {
        return .{ .raw = .{
            .present = true,
            .writable = flags.writable,
            .user = flags.user,
            .write_through = flags.write_through,
            .cache_disable = flags.cache_disable,
            .phys_addr = @truncate(@intFromPtr(pd) >> PAGE_SHIFT),
        } };
    }

    pub fn hugePage(phys: u64, flags: Flags) PDPTE {
        return .{ .raw = .{
            .present = true,
            .writable = flags.writable,
            .user = flags.user,
            .write_through = flags.write_through,
            .cache_disable = flags.cache_disable,
            .huge_page = true,
            .global = flags.global,
            .no_execute = flags.no_execute,
            .phys_addr = @truncate(phys >> PAGE_SHIFT),
        } };
    }

    pub fn getPD(self: PDPTE) ?*PD {
        if (!self.raw.isPresent() or self.raw.isHuge()) return null;
        return @ptrFromInt(self.raw.getPhysAddr());
    }

    pub fn isPresent(self: PDPTE) bool {
        return self.raw.isPresent();
    }

    pub fn isHugePage(self: PDPTE) bool {
        return self.raw.isHuge();
    }
};

/// PDPT Table - 512 entries.
pub const PDPT = struct {
    entries: [ENTRIES_PER_TABLE]PDPTE,

    pub fn empty() PDPT {
        return .{ .entries = [_]PDPTE{PDPTE.empty()} ** ENTRIES_PER_TABLE };
    }

    pub fn setEntry(self: *PDPT, index: u9, entry: PDPTE) void {
        self.entries[index] = entry;
    }

    pub fn getEntry(self: *const PDPT, index: u9) PDPTE {
        return self.entries[index];
    }
};

/// PD Entry - points to PT or maps 2MB large page.
pub const PDE = struct {
    raw: RawEntry,

    pub fn empty() PDE {
        return .{ .raw = RawEntry.empty() };
    }

    pub fn table(pt: *PT, flags: Flags) PDE {
        return .{ .raw = .{
            .present = true,
            .writable = flags.writable,
            .user = flags.user,
            .write_through = flags.write_through,
            .cache_disable = flags.cache_disable,
            .phys_addr = @truncate(@intFromPtr(pt) >> PAGE_SHIFT),
        } };
    }

    pub fn largePage(phys: u64, flags: Flags) PDE {
        return .{ .raw = .{
            .present = true,
            .writable = flags.writable,
            .user = flags.user,
            .write_through = flags.write_through,
            .cache_disable = flags.cache_disable,
            .huge_page = true,
            .global = flags.global,
            .no_execute = flags.no_execute,
            .phys_addr = @truncate(phys >> PAGE_SHIFT),
        } };
    }

    pub fn getPT(self: PDE) ?*PT {
        if (!self.raw.isPresent() or self.raw.isHuge()) return null;
        return @ptrFromInt(self.raw.getPhysAddr());
    }

    pub fn isPresent(self: PDE) bool {
        return self.raw.isPresent();
    }

    pub fn isLargePage(self: PDE) bool {
        return self.raw.isHuge();
    }
};

/// PD Table - 512 entries.
pub const PD = struct {
    entries: [ENTRIES_PER_TABLE]PDE,

    pub fn empty() PD {
        return .{ .entries = [_]PDE{PDE.empty()} ** ENTRIES_PER_TABLE };
    }

    pub fn setEntry(self: *PD, index: u9, entry: PDE) void {
        self.entries[index] = entry;
    }

    pub fn getEntry(self: *const PD, index: u9) PDE {
        return self.entries[index];
    }
};

/// PT Entry - maps 4KB page.
pub const PTE = struct {
    raw: RawEntry,

    pub fn empty() PTE {
        return .{ .raw = RawEntry.empty() };
    }

    pub fn page(phys: u64, flags: Flags) PTE {
        return .{ .raw = .{
            .present = true,
            .writable = flags.writable,
            .user = flags.user,
            .write_through = flags.write_through,
            .cache_disable = flags.cache_disable,
            .global = flags.global,
            .no_execute = flags.no_execute,
            .phys_addr = @truncate(phys >> PAGE_SHIFT),
        } };
    }

    pub fn getPhysAddr(self: PTE) u64 {
        return self.raw.getPhysAddr();
    }

    pub fn isPresent(self: PTE) bool {
        return self.raw.isPresent();
    }
};

/// PT Table - 512 entries.
pub const PT = struct {
    entries: [ENTRIES_PER_TABLE]PTE,

    pub fn empty() PT {
        return .{ .entries = [_]PTE{PTE.empty()} ** ENTRIES_PER_TABLE };
    }

    pub fn setEntry(self: *PT, index: u9, entry: PTE) void {
        self.entries[index] = entry;
    }

    pub fn getEntry(self: *const PT, index: u9) PTE {
        return self.entries[index];
    }
};

pub const VirtAddr = struct {
    value: u64,

    pub fn from(addr: u64) VirtAddr {
        return .{ .value = addr };
    }

    pub fn pml4Index(self: VirtAddr) u9 {
        return @truncate((self.value >> 39) & 0x1FF);
    }

    pub fn pdptIndex(self: VirtAddr) u9 {
        return @truncate((self.value >> 30) & 0x1FF);
    }

    pub fn pdIndex(self: VirtAddr) u9 {
        return @truncate((self.value >> 21) & 0x1FF);
    }

    pub fn ptIndex(self: VirtAddr) u9 {
        return @truncate((self.value >> 12) & 0x1FF);
    }

    pub fn pageOffset(self: VirtAddr) u12 {
        return @truncate(self.value & 0xFFF);
    }
};

pub fn alignDown(addr: u64, comptime alignment: u64) u64 {
    return addr & ~(alignment - 1);
}

pub fn alignUp(addr: u64, comptime alignment: u64) u64 {
    return alignDown(addr + alignment - 1, alignment);
}

pub fn pagesNeeded(size: u64, comptime page_size: u64) u64 {
    return alignUp(size, page_size) / page_size;
}
