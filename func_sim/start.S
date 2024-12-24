.section .text
.global _start

_start:
    # Set up stack pointer
    li sp, 0x80800000
    
    # Call main
    call main
    
    # Signal completion
    li t0, 1
    la t1, tohost
    sw t0, 0(t1)
    fence

1:  j 1b

.section .data
.align 8
.global tohost
.global fromhost
tohost: .word 0
fromhost: .word 0
