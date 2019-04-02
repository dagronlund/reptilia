.section .text
    lw ra, 0(x0)
    li ra,-16 # one
loc_start:
    beq x0, x0, loc0 # two
    addi x0, x0, 5
    addi x1, x0, 1
    addi x2, x0, 4
    li a0, 0
    ebreak
loc0:
    # jal x0, loc1 # three
    li a0, 1
    ebreak
loc1:
    addi x1, x0, 3 # four
    # csrrw x3, instret
    # rdinstret x3
    ebreak
