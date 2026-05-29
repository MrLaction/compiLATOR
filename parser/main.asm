; main.asm — compi entry point
; Usage: compi <file.lator> [-o output] [-v] [-s]

SYS_READ   equ 0
SYS_WRITE  equ 1
SYS_OPEN   equ 2
SYS_CLOSE  equ 3
SYS_DUP2   equ 33
SYS_EXIT   equ 60
O_RDONLY   equ 0
STDOUT     equ 1
STDERR     equ 2
STDIN      equ 0

extern parse_program
extern sem_walk

section .data
    str_ok        db "syntax OK", 10, 0
    str_ok_len    equ 10
    str_semok     db "semantic OK", 10, 0
    str_semok_len equ 12

    err_usage     db "usage: compi <file.lator> [-o name] [-v] [-s]", 10, 0
    err_usage_len equ 47
    err_ext       db "error: file must have .lator extension", 10, 0
    err_ext_len   equ 39
    err_open      db "error: cannot open file", 10, 0
    err_open_len  equ 24

    ext           db ".lator", 0

section .bss
    flag_verbose  resb 1
    flag_synonly  resb 1

section .text
global _start

_start:
    mov  r12, [rsp]
    lea  r13, [rsp+8]

    cmp  r12, 2
    jl   .err_usage

    mov  r14, [r13 + 8]     ; r14 = argv[1] = file path

    mov  byte [flag_verbose], 0
    mov  byte [flag_synonly], 0

    mov  rcx, 2
.flag_loop:
    cmp  rcx, r12
    jge  .flags_done
    mov  rdi, [r13 + rcx*8]
    call parse_flag
    inc  rcx
    jmp  .flag_loop

.flags_done:
    mov  rdi, r14
    call check_ext
    test rax, rax
    jz   .err_ext

    mov  rax, SYS_OPEN
    mov  rdi, r14
    mov  rsi, O_RDONLY
    xor  rdx, rdx
    syscall
    cmp  rax, 0
    jl   .err_open

    mov  r15, rax           ; r15 = file fd

    mov  rax, SYS_DUP2
    mov  rdi, r15
    mov  rsi, STDIN
    syscall

    mov  rax, SYS_CLOSE
    mov  rdi, r15
    syscall

    ; ── Stage 2: syntax analysis ──────────────────────────────
    call parse_program      ; rax = root AST node
    mov  r15, rax           ; r15 = root (preserved across syscalls)

    mov  rax, SYS_WRITE
    mov  rdi, STDOUT
    lea  rsi, [str_ok]
    mov  rdx, str_ok_len
    syscall

    ; skip semantic if -s flag
    cmp  byte [flag_synonly], 1
    je   .exit_ok

    ; ── Stage 3: semantic analysis ────────────────────────────
    mov  rdi, r15           ; root AST node
    call sem_walk           ; errors call SYS_EXIT(2) internally

    mov  rax, SYS_WRITE
    mov  rdi, STDOUT
    lea  rsi, [str_semok]
    mov  rdx, str_semok_len
    syscall

.exit_ok:
    mov  rax, SYS_EXIT
    xor  rdi, rdi
    syscall

.err_usage:
    mov  rax, SYS_WRITE
    mov  rdi, STDERR
    lea  rsi, [err_usage]
    mov  rdx, err_usage_len
    syscall
    jmp  .exit1

.err_ext:
    mov  rax, SYS_WRITE
    mov  rdi, STDERR
    lea  rsi, [err_ext]
    mov  rdx, err_ext_len
    syscall
    jmp  .exit1

.err_open:
    mov  rax, SYS_WRITE
    mov  rdi, STDERR
    lea  rsi, [err_open]
    mov  rdx, err_open_len
    syscall

.exit1:
    mov  rax, SYS_EXIT
    mov  rdi, 1
    syscall

; ─────────────────────────────────────────────────────────────
parse_flag:
    cmp  byte [rdi],   '-'
    jne  .done
    cmp  byte [rdi+1], 'v'
    jne  .check_s
    cmp  byte [rdi+2], 0
    jne  .check_s
    mov  byte [flag_verbose], 1
    ret
.check_s:
    cmp  byte [rdi+1], 's'
    jne  .done
    cmp  byte [rdi+2], 0
    jne  .done
    mov  byte [flag_synonly], 1
.done:
    ret

; ─────────────────────────────────────────────────────────────
check_ext:
    push rbx
    push rcx
    mov  rbx, rdi
    xor  rcx, rcx
.len_loop:
    cmp  byte [rbx + rcx], 0
    je   .len_done
    inc  rcx
    jmp  .len_loop
.len_done:
    cmp  rcx, 7
    jl   .fail
    lea  rbx, [rdi + rcx - 6]
    lea  rsi, [ext]
    xor  rcx, rcx
.cmp_loop:
    mov  al, [rbx + rcx]
    mov  ah, [rsi + rcx]
    cmp  al, ah
    jne  .fail
    inc  rcx
    cmp  rcx, 6
    jl   .cmp_loop
    mov  rax, 1
    jmp  .ret
.fail:
    xor  rax, rax
.ret:
    pop  rcx
    pop  rbx
    ret