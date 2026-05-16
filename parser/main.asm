; main.asm  (Stage 2 — replaces Stage 1 main.asm)
; Entry point: runs the parser and prints "syntax OK" or exits with error.

SYS_WRITE equ 1
SYS_EXIT  equ 60
STDOUT    equ 1

extern parse_program

section .data
    str_ok   db "syntax OK", 10, 0
    str_ok_len equ 10

section .text

global _start

_start:
    call parse_program              ; rax = root AST node or 0 on error
    ; If parse_program returned, syntax is valid (errors call SYS_EXIT internally)

    mov  rax, SYS_WRITE
    mov  rdi, STDOUT
    lea  rsi, [str_ok]
    mov  rdx, str_ok_len
    syscall

    mov  rax, SYS_EXIT
    xor  rdi, rdi
    syscall
