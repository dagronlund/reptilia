    .section .text.start
    .globl _start
_start:
    la      a0, _bss
    la      a1, _bend
    j       bss_loop_test
bss_loop:   
    sw      zero, (a0)
    addi    a0, a0, 4 # sizeof(word)
bss_loop_test:
    beq     a0, a1, bss_loop
    la      sp, __stack
    la      gp, __global_pointer$
    call    main
    ebreak
