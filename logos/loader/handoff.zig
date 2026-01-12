const std = @import("std");
const uefi = std.os.uefi;
const arch = @import("arch");

const Services = @import("../uefi/services.zig").Services;
const srv = @import("../uefi/services.zig");
const paging = @import("../arch/x86_64/paging.zig");
const elf_loader = @import("elf.zig");
const boot_info = @import("boot_info");

const log = std.log.scoped(.handoff);

const PageTables = paging.PageTables;
const BootInfo = boot_info.BootInfo;
const MemoryRegion = boot_info.MemoryRegion;
const MemoryType = boot_info.MemoryType;
const PageCount = boot_info.PageCount;
const Phys = boot_info.Phys;
const Virt = boot_info.Virt;
const Size = boot_info.Size;
const LoadedKernel = elf_loader.LoadedKernel;
const layout = arch.layout;

pub const HandoffError = error{
    PageTableSetupFailed,
    MemoryMapFailed,
    ExitBootServicesFailed,
};

const KernelEntry = *const fn (*BootInfo) callconv(.c) noreturn;

pub fn execute(services: Services, kernel: LoadedKernel) HandoffError!noreturn {
    var page_tables = PageTables.init(services) catch return error.PageTableSetupFailed;

    page_tables.identityMap2M(Phys.from(0), Size.gib(4), .{ .writable = true }) catch
        return error.PageTableSetupFailed;

    mapKernelHigherHalf(&page_tables, kernel) catch return error.PageTableSetupFailed;
    log.info("Page tables ready, CR3=0x{x}", .{page_tables.getCr3().raw()});

    const boot_info_page = services.allocPages(1) catch return error.MemoryMapFailed;
    const info: *BootInfo = @ptrCast(@alignCast(boot_info_page.ptr));

    info.* = .{
        .entry_phys = Phys.from(kernel.phys_start + (kernel.entry_virt - kernel.virt_base)),
        .entry_virt = Virt.from(kernel.entry_virt),
        .kernel_phys_start = Phys.from(kernel.phys_start),
        .kernel_phys_end = Phys.from(kernel.phys_end),
        .cr3 = page_tables.getCr3(),
        .memory_map = undefined,
        .framebuffer = null, // TODO: Get from GOP
        .rsdp_phys = Phys.from(findRsdp()),
    };

    const map_info = services.getMemoryMapInfo() catch return error.MemoryMapFailed;
    const map_size = map_info.len * map_info.descriptor_size + 4096;
    const map_buffer = services.allocPool(map_size) catch return error.MemoryMapFailed;

    const max_regions = map_info.len + 16;
    const regions_pages = (max_regions * @sizeOf(MemoryRegion) + 4095) / 4096;
    const regions_mem = services.allocPages(regions_pages) catch return error.MemoryMapFailed;
    const regions: [*]MemoryRegion = @ptrCast(@alignCast(regions_mem.ptr));

    const map_slice = services.getMemoryMap(@alignCast(map_buffer)) catch return error.MemoryMapFailed;
    const image_handle = srv.getImageHandle();
    services.exitBootServices(image_handle, map_slice.info.key) catch return error.ExitBootServicesFailed;

    // === NO MORE UEFI CALLS AFTER THIS POINT ===

    var region_count: u32 = 0;
    var iter = map_slice.iterator();
    while (iter.next()) |desc| {
        regions[region_count] = .{
            .phys_start = Phys.from(desc.physical_start),
            .page_count = PageCount.from(desc.number_of_pages),
            .mem_type = convertMemoryType(desc.type),
        };
        region_count += 1;
    }

    info.memory_map = .{
        .entries = regions,
        .entry_count = region_count,
    };

    const cr3 = page_tables.getCr3().raw();
    const entry_addr = kernel.entry_virt;
    const info_ptr = @intFromPtr(info);

    asm volatile (
        // Load new page tables
        \\mov %[cr3], %%cr3
        // Set up argument
        \\mov %[info], %%rdi
        // Jump to kernel entry
        \\jmp *%[entry]
        :
        : [cr3] "r" (cr3),
          [entry] "r" (entry_addr),
          [info] "r" (info_ptr),
        : .{ .rdi = true, .memory = true }
    );
    unreachable;
}

fn mapKernelHigherHalf(pt: *PageTables, kernel: LoadedKernel) !void {
    const page_size = arch.paging.LARGE_PAGE_SIZE;
    const kernel_size = kernel.phys_end - kernel.phys_start;

    var offset: u64 = 0;
    while (offset < kernel_size) : (offset += page_size) {
        const phys = arch.paging.Phys.from(kernel.phys_start + offset);
        const virt = arch.paging.Virt.from(kernel.virt_base + offset);

        pt.mapLargePage(virt, phys, .{ .writable = true }) catch |err| {
            log.err("Failed to map kernel page virt=0x{x} phys=0x{x}: {}", .{
                virt.raw(),
                phys.raw(),
                err,
            });
            return err;
        };
    }

    log.info("Mapped kernel higher-half: 0x{x}-0x{x} -> 0x{x}-0x{x}", .{
        kernel.virt_base,
        kernel.virt_base + kernel_size,
        kernel.phys_start,
        kernel.phys_end,
    });
}

fn findRsdp() u64 {
    const num_entries = uefi.system_table.number_of_table_entries;
    const config_tables = uefi.system_table.configuration_table[0..num_entries];

    // ACPI 2.0 RSDP GUID: 8868e871-e4f1-11d3-bc22-0080c73c8881
    const acpi2_guid = uefi.Guid{
        .time_low = 0x8868e871,
        .time_mid = 0xe4f1,
        .time_high_and_version = 0x11d3,
        .clock_seq_high_and_reserved = 0xbc,
        .clock_seq_low = 0x22,
        .node = .{ 0x00, 0x80, 0xc7, 0x3c, 0x88, 0x81 },
    };
    // ACPI 1.0 RSDP GUID: eb9d2d30-2d88-11d3-9a16-0090273fc14d
    const acpi1_guid = uefi.Guid{
        .time_low = 0xeb9d2d30,
        .time_mid = 0x2d88,
        .time_high_and_version = 0x11d3,
        .clock_seq_high_and_reserved = 0x9a,
        .clock_seq_low = 0x16,
        .node = .{ 0x00, 0x90, 0x27, 0x3f, 0xc1, 0x4d },
    };

    // Prefer ACPI 2.0
    for (config_tables) |table| {
        if (table.vendor_guid.eql(acpi2_guid)) {
            return @intFromPtr(table.vendor_table);
        }
    }
    // Fall back to ACPI 1.0
    for (config_tables) |table| {
        if (table.vendor_guid.eql(acpi1_guid)) {
            return @intFromPtr(table.vendor_table);
        }
    }
    return 0;
}

fn convertMemoryType(uefi_type: uefi.tables.MemoryType) MemoryType {
    return switch (uefi_type) {
        .conventional_memory => .usable,
        .loader_code, .loader_data => .bootloader_reclaimable,
        .boot_services_code, .boot_services_data => .bootloader_reclaimable,
        .runtime_services_code, .runtime_services_data => .reserved,
        .acpi_reclaim_memory => .acpi_reclaimable,
        .acpi_memory_nvs => .acpi_nvs,
        .unusable_memory => .bad_memory,
        else => .reserved,
    };
}
