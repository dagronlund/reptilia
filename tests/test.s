.section .text
    li ra,-16
    beq x0, x0, loc0
    addi x1, x0, 1
    ebreak
loc0:
    addi x1, x0, 2
    ebreak
