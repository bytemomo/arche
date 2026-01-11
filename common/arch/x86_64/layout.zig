//! Arche Virtual Address Layout
//!
//! Addresses chosen to NOT overlap with Linux for debugging clarity.
//!
//! ┌──────────────────────────────────────────────────────────────────┐
//! │ 0xFFFF_FFFF_FFFF_FFFF                                            │
//! │                         ┌──────────────────┐                     │
//! │                         │  Per-CPU (8MB)   │                     │
//! │ 0xFFFF_FE00_0000_0000   ├──────────────────┤                     │
//! │                         │    (reserved)    │                     │
//! │ 0xFFFF_C080_0000_0000   ├──────────────────┤                     │
//! │                         │  Heap (grows up) │                     │
//! │ 0xFFFF_C001_0000_0000   ├──────────────────┤                     │
//! │                         │  Stack (1MB/CPU) │                     │
//! │ 0xFFFF_C000_8000_0000   ├──────────────────┤                     │
//! │                         │  Kyber image     │                     │
//! │ 0xFFFF_C000_0010_0000   ├──────────────────┤ ← KERNEL_TEXT       │
//! │                         │  (guard page)    │                     │
//! │ 0xFFFF_C000_0000_0000   ├──────────────────┤ ← KERNEL_BASE       │
//! │                         │    (unused)      │                     │
//! │ 0xFFFF_A000_0000_0000   ├──────────────────┤ ← PHYS_MAP_BASE     │
//! │                         │  Direct phys map │                     │
//! │                         │     (2TB)        │                     │
//! │ 0xFFFF_8000_0000_0000   ├──────────────────┤ ← Higher half start │
//! │                         │  Canonical hole  │                     │
//! │ 0x0000_8000_0000_0000   ├──────────────────┤                     │
//! │                         │  Guest space     │                     │
//! │ 0x0000_0000_0000_0000   └──────────────────┘                     │
//! └──────────────────────────────────────────────────────────────────┘

const common_types = @import("types");
const arch_types = @import("types.zig");

const Phys = common_types.Phys;
const Virt = arch_types.Virt;
const Size = common_types.Size;

pub const PHYS_MAP_BASE = Virt.from(0xFFFF_A000_0000_0000);
pub const PHYS_MAP_SIZE = Size.tib(2);
pub const KERNEL_BASE = Virt.from(0xFFFF_C000_0000_0000);
pub const KERNEL_TEXT = Virt.from(0xFFFF_C000_0010_0000);
pub const KERNEL_STACK_BASE = Virt.from(0xFFFF_C000_8000_0000);
pub const KERNEL_STACK_SIZE = Size.mib(1);
pub const KERNEL_HEAP_BASE = Virt.from(0xFFFF_C001_0000_0000);
pub const KERNEL_HEAP_SIZE = Size.gib(512);
pub const PERCPU_BASE = Virt.from(0xFFFF_FE00_0000_0000);
pub const PERCPU_SIZE = Size.mib(8);

pub fn physToVirt(phys: Phys) Virt {
    return Virt.from(PHYS_MAP_BASE.raw() + phys.raw());
}

pub fn virtToPhys(virt: Virt) ?Phys {
    const v = virt.raw();
    const base = PHYS_MAP_BASE.raw();
    if (v >= base and v < base + PHYS_MAP_SIZE.raw()) {
        return Phys.from(v - base);
    }
    return null;
}

pub fn isKernelAddr(virt: Virt) bool {
    return virt.raw() >= KERNEL_BASE.raw();
}

pub fn isPhysMapAddr(virt: Virt) bool {
    const v = virt.raw();
    return v >= PHYS_MAP_BASE.raw() and v < PHYS_MAP_BASE.raw() + PHYS_MAP_SIZE.raw();
}
