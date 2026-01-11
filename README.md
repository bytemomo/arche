# ARCHE

**Arche** is a lightweight, bare-metal Type-1 Hypervisor written in **Zig**.
It is designed to be a minimal, safe, and performant foundation for virtualizing
hardware resources.

## Features

// TBD

- **Zig comptime**: Explore and leverage zig comptime.

## Build & Run

### Prerequisites

- **Zig.** `0.15.2`.
- **QEMU.** `10.1.2` for emulation.
- **OVMF.** Support for UEFI in Virtual Machine.

### Running in QEMU

To launch the **Logos** bootloader and hand off to **Arche**:

```sh
zig build run
```

## References

- [Initial Boot Sequence](https://alessandropellegrini.it/didattica/2017/aosv/1.Initial-Boot-Sequence.pdf)
- [hv in Zig](https://hv.smallkirby.com/en/)
