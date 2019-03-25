OUTPUT_FORMAT("elf32-littleriscv")

__stack = 0x10000;

SECTIONS
{
    .text 0x0000: 
    { 
        _text = . ; 
        *(.text.start) _estart = . ;
        *(.text) _etext = . ;
    }
    .rodata ALIGN(4): 
    {
        _rodata = . ; 
        *(.rodata) _erodata = . ; 
    }
    .data ALIGN(4): 
    { 
        PROVIDE( __global_pointer$ = . + (4K / 2) );
        _data = . ; 
        *(.data); _edata = . ; 
    }
    .bss ALIGN(4): { 
        _bss = . ; 
        *(.bss) *(COMMON); 
        _bend = ALIGN(4);
    }
}
