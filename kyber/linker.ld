/* Kyber Hypervisor Linker Script
 *
 * Virtual addresses start at KERNEL_TEXT (0xFFFF_C000_0020_0000)
 *
 */

OUTPUT_FORMAT(elf64-x86-64)
OUTPUT_ARCH(i386:x86-64)
ENTRY(_start)

KERNEL_VIRT_BASE = 0xFFFFC00000200000;
KERNEL_PHYS_BASE = 0x200000;

SECTIONS
{
    . = KERNEL_VIRT_BASE;
    __kernel_start = .;

    .text ALIGN(4K) : AT(KERNEL_PHYS_BASE)
    {
        __text_start = .;
        *(.text._entry)
        *(.text .text.*)
        *(.ltext .ltext.*)
        __text_end = .;
    }

    .rodata ALIGN(4K) : AT(KERNEL_PHYS_BASE + (__rodata_start - __kernel_start))
    {
        __rodata_start = .;
        *(.rodata .rodata.*)
        __rodata_end = .;
    }

    .data ALIGN(4K) : AT(KERNEL_PHYS_BASE + (__data_start - __kernel_start))
    {
        __data_start = .;
        *(.data .data.*)
        __data_end = .;
    }

    .bss ALIGN(4K) : AT(KERNEL_PHYS_BASE + (__bss_start - __kernel_start))
    {
        __bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        __bss_end = .;
    }

    . = ALIGN(4K);
    __kernel_end = .;

    __kernel_size = __kernel_end - __kernel_start;
    __kernel_phys_end = KERNEL_PHYS_BASE + __kernel_size;

    /* Discard unnecessary sections */
    /DISCARD/ :
    {
        *(.comment)
        *(.note*)
        *(.eh_frame*)
        *(.debug*)
    }
}
