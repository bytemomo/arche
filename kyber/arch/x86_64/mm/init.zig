const hal = @import("hal");
const log = @import("../../../core/log.zig");
const boot_info = @import("../../../core/boot_info.zig");
const paging = @import("paging.zig");
const layout = @import("layout.zig");
const PageAllocator = @import("../../../mem/PageAllocator.zig");

const Phys = boot_info.Phys;
const Size = boot_info.Size;

const PML4 = paging.PML4;
const PML4E = paging.PML4E;
const PDPT = paging.PDPT;
const PDPTE = paging.PDPTE;

/// Global — bitmap is 128 KiB, too large for the stack.
var page_alloc: PageAllocator = undefined;

pub fn init(info: *boot_info.BootInfo) void {
    page_alloc.initInPlace(info.memory_map);
    log.debug(@src(), "page allocator ready", .{});

    const pml4 = allocTable(PML4);
    mapDirectPhysRegion(pml4);
    log.debug(@src(), "direct phys map done", .{});

    cloneEntries(pml4, info.cr3);
    log.debug(@src(), "PML4 entries cloned", .{});

    hal.cpu.writeCr3(Phys.fromPtr(pml4).raw());
    log.info(@src(), "paging initialized", .{});
}

fn mapDirectPhysRegion(pml4: *PML4) void {
    const base = layout.PHYS_MAP_BASE.raw();
    const size = layout.PHYS_MAP_SIZE.raw();
    const gib = Size.gib(1).raw();
    const total_gib = size / gib;

    const start_pml4: u9 = @truncate((base >> 39) & 0x1FF);
    const pdpts_needed = (total_gib + 511) / 512;

    var phys_offset: u64 = 0;
    var remaining = total_gib;

    for (0..pdpts_needed) |i| {
        const pdpt = allocTable(PDPT);
        const entries = if (remaining > 512) 512 else remaining;

        for (0..entries) |j| {
            pdpt.setEntry(@intCast(j), PDPTE.hugePage(
                Phys.from(phys_offset),
                .{ .writable = true },
            ));
            phys_offset += gib;
        }

        pml4.setEntry(@intCast(start_pml4 + i), PML4E.table(
            Phys.fromPtr(pdpt),
            .{ .writable = true },
        ));
        remaining -= entries;
    }
}

fn cloneEntries(new: *PML4, old_cr3: Phys) void {
    const old: *const PML4 = old_cr3.toPtr(*const PML4);

    const phys_map_start: u9 = @truncate(
        (layout.PHYS_MAP_BASE.raw() >> 39) & 0x1FF,
    );
    const pdpts_in_phys_map: u9 = @intCast(
        layout.PHYS_MAP_SIZE.raw() / Size.gib(512).raw(),
    );
    const phys_map_end: u9 = phys_map_start + pdpts_in_phys_map;

    // Clone all present entries, skipping the PHYS_MAP range we
    // set up ourselves. Lower-half entries preserve UEFI's
    // identity mapping so the stack remains accessible.
    for (0..512) |i| {
        const idx: u9 = @intCast(i);
        if (idx >= phys_map_start and idx < phys_map_end)
            continue;

        const entry = old.getEntry(idx);
        if (entry.isPresent()) {
            new.setEntry(idx, entry);
        }
    }
}

fn allocTable(comptime T: type) *T {
    const phys = page_alloc.allocPages(1) orelse
        @panic("mm/init: out of memory for page table");
    const addr = phys.raw();
    const ptr: [*]volatile u8 = @ptrFromInt(addr);
    for (0..4096) |i| {
        ptr[i] = 0;
    }
    return @ptrFromInt(addr);
}
