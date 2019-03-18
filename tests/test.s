.section .text
    li ra,-16 # one
    beq x0, x0, loc0 # two
    addi x0, x0, 5
    addi x1, x0, 1
    addi x2, x0, 4
    ebreak
loc0:
    jal x0, loc1 # three
    addi x1, x0, 2
    ebreak
loc1:
    addi x1, x0, 3 # four
    # csrrw x3, instret
    rdinstret x3
    ebreak
