; ============================================================
;  MAIN — Entry point
;  Module: main.asm
;
;  Drives the lexical analyzer: calls get_token in a loop
;  and prints each token's type and lexeme to stdout.
;
;  Imported symbols:
;    From lexer.asm:
;      - get_token   : returns rax = token ID, fills lexeme[]
;      - lexeme      : current token text
;    From symbol_table.asm:
;      - tk_name_table  : pointer table indexed by token ID
;      - str_arrow      : " --> ["
;      - str_close      : "]\n"
;      - str_header     : output header string
;      - str_tk_eof     : "TK_EOF" name string
; ============================================================

; ── Linux x86-64 Syscalls ──────────────────────────────────
SYS_WRITE equ 1
SYS_EXIT  equ 60
STDOUT    equ 1

; ── Token IDs needed here ──────────────────────────────────
TK_EOF    equ 36

; ── Imported symbols ───────────────────────────────────────
extern get_token
extern lexeme
extern tk_name_table
extern str_arrow, str_close, str_header, str_tk_eof

section .text
global _start

; ============================================================
;  _start — Program entry point
;
;  Loop:
;    1. Call get_token
;    2. Print token name (from tk_name_table)
;    3. Print " --> ["
;    4. Print lexeme
;    5. Print "]\n"
;    6. Repeat until TK_EOF
; ============================================================
_start:
    ; Print header
    mov rdi, str_header
    call print_str

.token_loop:
    call get_token              ; rax = token ID, lexeme[] = text
    cmp  rax, TK_EOF
    je   .at_eof

    ; Print token name
    mov  rdi, rax
    call print_token_name

    ; Print " --> ["
    mov  rdi, str_arrow
    call print_str

    ; Print lexeme text
    mov  rdi, lexeme
    call print_str

    ; Print "]\n"
    mov  rdi, str_close
    call print_str

    jmp .token_loop

.at_eof:
    ; Print the EOF token line
    mov  rdi, str_tk_eof
    call print_str
    mov  rdi, str_arrow
    call print_str
    mov  rdi, str_close
    call print_str

    ; Exit with code 0
    mov  rax, SYS_EXIT
    xor  rdi, rdi
    syscall

; ============================================================
;  print_token_name — Look up and print the name of a token
;
;  Input:  rdi = token ID (1-based, TK_INT=1 ... TK_ERROR=37)
;  Effect: writes the padded token name string to stdout
; ============================================================
print_token_name:
    dec  rdi                    ; convert to 0-based index
    lea  rsi, [tk_name_table]
    mov  rdi, [rsi + rdi*8]    ; load pointer from table
    call print_str
    ret

; ============================================================
;  print_str — Write a null-terminated string to stdout
;
;  Input:  rdi = pointer to string
;  Effect: writes all bytes up to (not including) the null byte
; ============================================================
print_str:
    push rdi

    ; Compute length
    xor  rcx, rcx
.len_loop:
    cmp  byte [rdi + rcx], 0
    je   .write
    inc  rcx
    jmp  .len_loop

.write:
    mov  rdx, rcx               ; length
    mov  rsi, rdi               ; buffer pointer
    mov  rdi, STDOUT
    mov  rax, SYS_WRITE
    syscall

    pop  rdi
    ret
