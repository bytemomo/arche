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

const common_types = @import("types");
const arch_types = @import("types.zig");

pub const Size = common_types.Size;
pub const Phys = common_types.Phys;
pub const Virt = arch_types.Virt;

pub const PAGE_SIZE = 4096;
pub const PAGE_SHIFT = 12;
pub const LARGE_PAGE_SIZE = Size.mib(2).value;
pub const LARGE_PAGE_SHIFT = 21;
pub const HUGE_PAGE_SIZE = Size.gib(1).value;
pub const HUGE_PAGE_SHIFT = 30;

pub const ENTRIES_PER_TABLE = 512;

/// Mapping for pages and tables.
pub const Flags = struct {
    writable: bool = true,
    user: bool = false,
    no_execute: bool = false,
    global: bool = false,
    write_through: bool = false,
    cache_disable: bool = false,
};

/// Raw page table entry: PML4E, PDPTE, PDE, PTE
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

/// PML4 Entry: points to PDPT.
pub const PML4E = struct {
    raw: RawEntry,

    pub fn empty() PML4E {
        return .{ .raw = RawEntry.empty() };
    }

    pub fn table(pdpt_phys: Phys, flags: Flags) PML4E {
        return .{ .raw = .{
            .present = true,
            .writable = flags.writable,
            .user = flags.user,
            .write_through = flags.write_through,
            .cache_disable = flags.cache_disable,
            .phys_addr = @truncate(pdpt_phys.raw() >> PAGE_SHIFT),
        } };
    }

    pub fn getPDPT(self: PML4E) ?Phys {
        if (!self.raw.isPresent()) return null;
        return Phys.from(self.raw.getPhysAddr());
    }

    pub fn isPresent(self: PML4E) bool {
        return self.raw.isPresent();
    }
};

/// PML4 Table: 512 entries, each pointing to a PDPT.
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

/// PDPT Entry: points to PD _or_ maps 1GB huge page.
pub const PDPTE = struct {
    raw: RawEntry,

    pub fn empty() PDPTE {
        return .{ .raw = RawEntry.empty() };
    }

    pub fn table(pd_phys: Phys, flags: Flags) PDPTE {
        return .{ .raw = .{
            .present = true,
            .writable = flags.writable,
            .user = flags.user,
            .write_through = flags.write_through,
            .cache_disable = flags.cache_disable,
            .phys_addr = @truncate(pd_phys.raw() >> PAGE_SHIFT),
        } };
    }

    pub fn hugePage(phys: Phys, flags: Flags) PDPTE {
        const frame = phys.raw() >> HUGE_PAGE_SHIFT;
        return .{ .raw = .{
            .present = true,
            .writable = flags.writable,
            .user = flags.user,
            .write_through = flags.write_through,
            .cache_disable = flags.cache_disable,
            .huge_page = true,
            .global = flags.global,
            .no_execute = flags.no_execute,
            .phys_addr = @truncate(frame << (HUGE_PAGE_SHIFT - PAGE_SHIFT)),
        } };
    }

    pub fn getPD(self: PDPTE) ?Phys {
        if (!self.raw.isPresent() or self.raw.isHuge()) return null;
        return Phys.from(self.raw.getPhysAddr());
    }

    pub fn isPresent(self: PDPTE) bool {
        return self.raw.isPresent();
    }

    pub fn isHugePage(self: PDPTE) bool {
        return self.raw.isHuge();
    }
};

/// PDPT Table: 512 entries.
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

/// PD Entry: points to PT _or_ maps 2MB large page.
pub const PDE = struct {
    raw: RawEntry,

    pub fn empty() PDE {
        return .{ .raw = RawEntry.empty() };
    }

    pub fn table(pt_phys: Phys, flags: Flags) PDE {
        return .{ .raw = .{
            .present = true,
            .writable = flags.writable,
            .user = flags.user,
            .write_through = flags.write_through,
            .cache_disable = flags.cache_disable,
            .phys_addr = @truncate(pt_phys.raw() >> PAGE_SHIFT),
        } };
    }

    pub fn largePage(phys: Phys, flags: Flags) PDE {
        const frame = phys.raw() >> LARGE_PAGE_SHIFT;
        return .{ .raw = .{
            .present = true,
            .writable = flags.writable,
            .user = flags.user,
            .write_through = flags.write_through,
            .cache_disable = flags.cache_disable,
            .huge_page = true,
            .global = flags.global,
            .no_execute = flags.no_execute,
            .phys_addr = @truncate(frame << (LARGE_PAGE_SHIFT - PAGE_SHIFT)),
        } };
    }

    pub fn getPT(self: PDE) ?Phys {
        if (!self.raw.isPresent() or self.raw.isHuge()) return null;
        return Phys.from(self.raw.getPhysAddr());
    }

    pub fn isPresent(self: PDE) bool {
        return self.raw.isPresent();
    }

    pub fn isLargePage(self: PDE) bool {
        return self.raw.isHuge();
    }
};

/// PD Table: 512 entries.
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

/// PT Entry: maps 4KB page.
pub const PTE = struct {
    raw: RawEntry,

    pub fn empty() PTE {
        return .{ .raw = RawEntry.empty() };
    }

    pub fn page(phys: Phys, flags: Flags) PTE {
        return .{ .raw = .{
            .present = true,
            .writable = flags.writable,
            .user = flags.user,
            .write_through = flags.write_through,
            .cache_disable = flags.cache_disable,
            .global = flags.global,
            .no_execute = flags.no_execute,
            .phys_addr = @truncate(phys.raw() >> PAGE_SHIFT),
        } };
    }

    pub fn getPhys(self: PTE) Phys {
        return Phys.from(self.raw.getPhysAddr());
    }

    pub fn isPresent(self: PTE) bool {
        return self.raw.isPresent();
    }
};

/// PT Table: 512 entries.
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

const testing = @import("std").testing;

test "RawEntry encode/decode phys_addr roundtrip" {
    const addr: u64 = 0x0000_0000_1234_5000;
    const entry: RawEntry = .{
        .present = true,
        .phys_addr = @truncate(addr >> PAGE_SHIFT),
    };
    try testing.expectEqual(addr, entry.getPhysAddr());
}

test "PML4E table/getPDPT roundtrip" {
    const pdpt_phys = Phys.from(0x0010_0000);
    const entry = PML4E.table(pdpt_phys, .{});
    try testing.expect(entry.isPresent());
    const got = entry.getPDPT() orelse return error.TestUnexpectedResult;
    try testing.expectEqual(pdpt_phys.raw(), got.raw());
}

test "PML4E empty is not present" {
    const entry = PML4E.empty();
    try testing.expect(!entry.isPresent());
    try testing.expectEqual(@as(?Phys, null), entry.getPDPT());
}

test "PDPTE table/getPD roundtrip" {
    const pd_phys = Phys.from(0x0020_0000);
    const entry = PDPTE.table(pd_phys, .{});
    try testing.expect(entry.isPresent());
    try testing.expect(!entry.isHugePage());
    const got = entry.getPD() orelse return error.TestUnexpectedResult;
    try testing.expectEqual(pd_phys.raw(), got.raw());
}

test "PDPTE hugePage sets huge flag and address" {
    const phys = Phys.from(0x4000_0000); // 1GB aligned
    const entry = PDPTE.hugePage(phys, .{});
    try testing.expect(entry.isPresent());
    try testing.expect(entry.isHugePage());
    try testing.expectEqual(@as(?Phys, null), entry.getPD());
    try testing.expectEqual(phys.raw(), entry.raw.getPhysAddr());
}

test "PDE table/getPT roundtrip" {
    const pt_phys = Phys.from(0x0030_0000);
    const entry = PDE.table(pt_phys, .{});
    try testing.expect(entry.isPresent());
    try testing.expect(!entry.isLargePage());
    const got = entry.getPT() orelse return error.TestUnexpectedResult;
    try testing.expectEqual(pt_phys.raw(), got.raw());
}

test "PDE largePage sets huge flag and address" {
    const phys = Phys.from(0x0020_0000); // 2MB aligned
    const entry = PDE.largePage(phys, .{});
    try testing.expect(entry.isPresent());
    try testing.expect(entry.isLargePage());
    try testing.expectEqual(@as(?Phys, null), entry.getPT());
    try testing.expectEqual(phys.raw(), entry.raw.getPhysAddr());
}

test "PTE page/getPhys roundtrip" {
    const phys = Phys.from(0x0040_0000);
    const entry = PTE.page(phys, .{});
    try testing.expect(entry.isPresent());
    try testing.expectEqual(phys.raw(), entry.getPhys().raw());
}

test "PTE empty is not present" {
    const entry = PTE.empty();
    try testing.expect(!entry.isPresent());
}

test "flag propagation: writable, user, no_execute" {
    const flags: Flags = .{
        .writable = true,
        .user = true,
        .no_execute = true,
    };
    const pte = PTE.page(Phys.from(0x1000), flags);
    try testing.expect(pte.raw.writable);
    try testing.expect(pte.raw.user);
    try testing.expect(pte.raw.no_execute);
}
