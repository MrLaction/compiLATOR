; strpool.asm
; Static string pool for persisting lexeme copies.
; The lexer reuses the lexeme[] buffer on every get_token call.
; AST nodes that store identifiers or literals need a stable copy.
;
; intern_str(src) -> rax = pointer to null-terminated copy in pool
;   rdi = pointer to source string (null-terminated)
; Does NOT deduplicate — every call allocates a new entry.
; Pool capacity: 65536 bytes total.

STRPOOL_CAP equ 65536

section .bss
    str_pool     resb STRPOOL_CAP
    str_pool_pos resq 1             ; next free byte offset

section .text

global intern_str
global str_pool

; ---------------------------------------------------------------------------
; intern_str(src) -> rax
; ---------------------------------------------------------------------------
intern_str:
    push rbp
    mov  rbp, rsp
    push rbx
    push r12
    push r13

    mov  r12, rdi                   ; src pointer
    mov  r13, [str_pool_pos]        ; current pool offset

    ; compute length of src
    xor  rbx, rbx
.len_loop:
    cmp  byte [r12 + rbx], 0
    je   .len_done
    inc  rbx
    jmp  .len_loop
.len_done:
    ; rbx = length (not including null)

    ; check capacity: pos + len + 1 <= STRPOOL_CAP
    mov  rax, r13
    add  rax, rbx
    inc  rax
    cmp  rax, STRPOOL_CAP
    jge  .pool_full

    ; compute destination pointer
    lea  rax, [str_pool]
    add  rax, r13                   ; rax = &str_pool[pos]
    push rax                        ; save return pointer

    ; copy bytes
    xor  rcx, rcx
.copy_loop:
    cmp  rcx, rbx
    je   .copy_done
    mov  dl, [r12 + rcx]
    lea  r8, [str_pool]
    add  r8, r13
    add  r8, rcx
    mov  [r8], dl
    inc  rcx
    jmp  .copy_loop
.copy_done:
    ; write null terminator
    lea  r8, [str_pool]
    add  r8, r13
    add  r8, rbx
    mov  byte [r8], 0

    ; advance pool position by len+1
    add  r13, rbx
    inc  r13
    mov  [str_pool_pos], r13

    pop  rax                        ; restore pointer to copied string
    pop  r13
    pop  r12
    pop  rbx
    pop  rbp
    ret

.pool_full:
    mov  rax, 60
    mov  rdi, 98                    ; exit code 98 = string pool exhausted
    syscall
