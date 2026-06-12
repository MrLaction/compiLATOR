;lexer_main.asm — standalone token-dump driver (stage 1 binary)
;
;Entry point for bin/lexer. Reads LATOR source from stdin, calls
;get_token until TK_EOF and prints one "TOKEN --> [lexeme]" line per
;token. Exists for inspection and for the lexer golden test.
;
;Imports:
;  get_token, lexeme                       (lexer.asm)
;  tk_name_table, str_* output strings     (symbol_table.asm)

default abs

SYS_WRITE   equ 1
SYS_EXIT    equ 60
STDOUT      equ 1

; Token IDs needed here
TK_EOF      equ 41

; Imported symbols
extern get_token
extern lexeme
extern tk_name_table
extern str_arrow, str_close, str_header, str_tk_eof

section .text
global _start

;_start — Program entry point
_start:
    ;Print header
    mov  rdi, str_header
    call print_str

.token_loop:
    call get_token              ;rax = token ID, lexeme[] = text

    cmp  rax, TK_EOF
    je   .at_eof

    ;Print token name
    mov  rdi, rax
    call print_token_name

    ;Print " --> ["
    mov  rdi, str_arrow
    call print_str

    ;Print lexeme text
    mov  rdi, lexeme
    call print_str

    ;Print "]\n"
    mov  rdi, str_close
    call print_str

    jmp  .token_loop

.at_eof:
    ;Print the EOF token line
    mov  rdi, str_tk_eof
    call print_str

    mov  rdi, str_arrow
    call print_str

    mov  rdi, str_close
    call print_str

    ;Exit with code 0
    mov  rax, SYS_EXIT
    xor  rdi, rdi
    syscall

;print_token_name — Look up and print the name of a token
;
;Input: rdi = token ID (1-based)
print_token_name:
    dec  rdi
    lea  rsi, [tk_name_table]
    mov  rdi, [rsi + rdi*8]
    call print_str
    ret

;print_str — Write a null-terminated string to stdout
;
;Input: rdi = pointer to string
print_str:
    push rdi
    xor  rcx, rcx
.len_loop:
    cmp  byte [rdi + rcx], 0
    je   .write
    inc  rcx
    jmp  .len_loop
.write:
    mov  rdx, rcx
    mov  rsi, rdi
    mov  rdi, STDOUT
    mov  rax, SYS_WRITE
    syscall
    pop  rdi
    ret
