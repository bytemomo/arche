const std = @import("std");
const uefi = std.os.uefi;
const elf = std.elf;

const Services = @import("../uefi/services.zig").Services;

const log = std.log.scoped(.elf_loader);

pub const LoadError = error{
    InvalidMagic,
    Not64Bit,
    NotExecutable,
    WrongMachine,
    NoLoadableSegments,
    AllocationFailed,
    ReadFailed,
};

pub const LoadedKernel = struct {
    entry_virt: u64,
    phys_start: u64,
    phys_end: u64,
    virt_base: u64,
};

/// Load an ELF64 kernel from file data.
pub fn load(services: Services, file_data: []const u8) LoadError!LoadedKernel {
    if (file_data.len < @sizeOf(elf.Elf64_Ehdr)) return error.InvalidMagic;
    if (!std.mem.eql(u8, file_data[0..4], elf.MAGIC)) return error.InvalidMagic;

    const raw_hdr: *const elf.Elf64_Ehdr = @ptrCast(@alignCast(file_data.ptr));

    if (file_data[elf.EI_CLASS] != elf.ELFCLASS64) return error.Not64Bit;
    if (raw_hdr.e_type != .EXEC) return error.NotExecutable;
    if (raw_hdr.e_machine != .X86_64) return error.WrongMachine;

    const entry = raw_hdr.e_entry;
    const phoff = raw_hdr.e_phoff;
    const phnum = raw_hdr.e_phnum;
    const phentsize = raw_hdr.e_phentsize;

    log.debug("ELF: entry=0x{x} phnum={}", .{ entry, phnum });

    var phys_start: u64 = std.math.maxInt(u64);
    var phys_end: u64 = 0;
    var virt_base: u64 = std.math.maxInt(u64);
    var has_load_segment = false;

    var i: u16 = 0;
    while (i < phnum) : (i += 1) {
        const phdr_offset = phoff + @as(u64, i) * @as(u64, phentsize);
        if (phdr_offset + @sizeOf(elf.Elf64_Phdr) > file_data.len) break;

        const phdr: *const elf.Elf64_Phdr = @ptrCast(@alignCast(file_data.ptr + phdr_offset));
        if (phdr.p_type != elf.PT_LOAD) continue;
        if (phdr.p_memsz == 0) continue;

        has_load_segment = true;

        const seg_phys_start = phdr.p_paddr;
        const seg_phys_end = seg_phys_start + phdr.p_memsz;

        if (seg_phys_start < phys_start) phys_start = seg_phys_start;
        if (seg_phys_end > phys_end) phys_end = seg_phys_end;
        if (phdr.p_vaddr < virt_base) virt_base = phdr.p_vaddr;

        log.debug("  LOAD: virt=0x{x} phys=0x{x} filesz=0x{x} memsz=0x{x}", .{
            phdr.p_vaddr,
            phdr.p_paddr,
            phdr.p_filesz,
            phdr.p_memsz,
        });
    }

    if (!has_load_segment) return error.NoLoadableSegments;

    const page_size: u64 = 4096;
    phys_start = phys_start & ~(page_size - 1);
    phys_end = (phys_end + page_size - 1) & ~(page_size - 1);

    const pages_needed = (phys_end - phys_start) / page_size;
    log.info("Allocating {} pages at 0x{x}-0x{x}", .{ pages_needed, phys_start, phys_end });

    const pages = services.allocPagesAt(phys_start, pages_needed) catch return error.AllocationFailed;
    const dest_base: [*]u8 = @ptrCast(pages.ptr);

    @memset(dest_base[0..(phys_end - phys_start)], 0);

    i = 0;
    while (i < phnum) : (i += 1) {
        const phdr_offset = phoff + @as(u64, i) * @as(u64, phentsize);
        if (phdr_offset + @sizeOf(elf.Elf64_Phdr) > file_data.len) break;

        const phdr: *const elf.Elf64_Phdr = @ptrCast(@alignCast(file_data.ptr + phdr_offset));
        if (phdr.p_type != elf.PT_LOAD) continue;
        if (phdr.p_memsz == 0) continue;

        const dest_offset = phdr.p_paddr - phys_start;
        const dest: [*]u8 = dest_base + dest_offset;

        if (phdr.p_filesz > 0) {
            const src = file_data[phdr.p_offset..][0..phdr.p_filesz];
            @memcpy(dest[0..phdr.p_filesz], src);
        }
    }

    log.info("Kernel loaded: entry=0x{x} phys=0x{x}-0x{x}", .{
        entry,
        phys_start,
        phys_end,
    });

    return .{
        .entry_virt = entry,
        .phys_start = phys_start,
        .phys_end = phys_end,
        .virt_base = virt_base,
    };
}
