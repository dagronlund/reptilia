OUTPUT_FORMAT("elf32-littleriscv")

MEMORY {
    RAM (rwx) : ORIGIN = 0, LENGTH = 64K
}

SECTIONS {
    .text 0x0000: {
        _text = . ; 
        *(.text.start) _estart = . ;
        *(.text) _etext = . ;
    } > RAM
    .rodata ALIGN(4): {
        _rodata = . ; 
        *(.rodata) _erodata = . ; 
    } > RAM
    .data ALIGN(4): {
        PROVIDE( __global_pointer$ = . + (4K / 2) );
        _data = . ; 
        *(.data); _edata = . ; 
    } > RAM
    .bss ALIGN(4): {
        _bss = . ; 
        *(.bss) *(COMMON); 
        _bend = ALIGN(4);
    } > RAM
    PROVIDE(__stack = ORIGIN(RAM) + LENGTH(RAM));
}
