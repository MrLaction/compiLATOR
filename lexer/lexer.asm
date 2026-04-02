; ============================================================
; LEXICAL ANALYZER — DFA Logic
; Module: lexer.asm
;
; Implements the Deterministic Finite Automaton (DFA) that
; scans an input stream and produces tokens one at a time.
;
; Adapted for the declarative language defined in the
; language design document.
;
; Exported symbols (global):
;   - get_token  : reads next token from stdin
;   - lexeme     : current token text (null-terminated)
;   - lexeme_len : current token text length
;
; Imported symbols (extern from symbol_table.asm):
;   - kw_*       : keyword strings for lookup
;
; Convention:
;   get_token returns rax = token ID, lexeme[] = token text.
;   All helper functions are local (not exported).
; ============================================================

; ── Linux x86-64 Syscalls ──────────────────────────────────
SYS_READ    equ 0
STDIN       equ 0

; ── Token IDs ──────────────────────────────────────────────
; Duplicated here so lexer.asm compiles standalone.
; Single source of truth is symbol_table.asm — keep in sync.

TK_IS           equ 1
TK_WHERE        equ 2
TK_AND          equ 3
TK_OR           equ 4
TK_NOT          equ 5
TK_EVERY        equ 6
TK_IN           equ 7
TK_OF           equ 8
TK_LET          equ 9
TK_BE           equ 10
TK_FROM         equ 11
TK_TO           equ 12
TK_MIN          equ 13
TK_MAX          equ 14
TK_SUM          equ 15
TK_TRUE         equ 16
TK_FALSE        equ 17

TK_LIT_INT      equ 18
TK_LIT_FLOAT    equ 19
TK_LIT_STRING   equ 20

TK_ID           equ 21

TK_GREATER      equ 22
TK_LESS         equ 23
TK_GREATER_EQ   equ 24
TK_LESS_EQ      equ 25
TK_EQUAL        equ 26
TK_NOT_EQUAL    equ 27
TK_ASSIGN       equ 28

TK_PLUS         equ 29
TK_MINUS        equ 30
TK_MULTIPLY     equ 31
TK_DIVIDE       equ 32
TK_MODULO       equ 33

TK_LPAREN       equ 34
TK_RPAREN       equ 35
TK_LBRACKET     equ 36
TK_RBRACKET     equ 37
TK_COMMA        equ 38
TK_DOT          equ 39
TK_NEWLINE      equ 40

TK_EOF          equ 41
TK_ERROR        equ 42

; ── Buffer sizes ────────────────────────────────────────────
BUF_SIZE    equ 4096
LEXEME_MAX  equ 256

; ── Imported data (symbol_table.asm) ────────────────────────
extern kw_is, kw_where, kw_and, kw_or, kw_not
extern kw_every, kw_in, kw_of, kw_let, kw_be
extern kw_from, kw_to, kw_min, kw_max, kw_sum
extern kw_true, kw_false

; ── Exported symbols ────────────────────────────────────────
global get_token
global lexeme, lexeme_len

section .bss

; Input buffer — private to this module
buf         resb BUF_SIZE
buf_pos     resq 1
buf_len     resq 1

; Putback register — 1-character lookahead
putback     resb 1
has_putback resb 1

; Current lexeme — exported so main.asm can print it
lexeme      resb LEXEME_MAX
lexeme_len  resq 1

section .text

; ============================================================
; get_token — Read the next token from stdin
;
; Returns:
;   rax = token ID (one of the TK_* constants above)
;   lexeme[] is filled with the token text (null-terminated)
;   lexeme_len holds the byte count
;
; Clobbers: rax, rcx, rsi, rdi, al, bl
; ============================================================
get_token:
    push rbp
    mov  rbp, rsp

    ; Clear lexeme
    mov  qword [lexeme_len], 0
    mov  byte  [lexeme], 0

; ── State S0: skip whitespace (spaces and tabs only) ───────
; Newlines are NOT skipped — they are tokens (TK_NEWLINE).
.s0_skip_ws:
    call next_char
    cmp  al, 0
    je   .emit_eof

    cmp  al, ' '
    je   .s0_skip_ws
    cmp  al, 9              ; tab
    je   .s0_skip_ws
    cmp  al, 13             ; carriage return — skip silently
    je   .s0_skip_ws

; ── Newline → TK_NEWLINE ───────────────────────────────────
    cmp  al, 10
    je   .emit_newline

; ── Classify first character ───────────────────────────────

    ; [a-zA-Z_] → identifier or keyword (S1)
    call is_alpha_or_under
    jc   .state_id

    ; [0-9] → number (S2)
    call is_digit
    jc   .state_number

    ; '"' → string literal (S5)
    cmp  al, '"'
    je   .state_string

    ; '=' → TK_ASSIGN or TK_EQUAL
    cmp  al, '='
    je   .state_eq

    ; '!' → TK_NOT_EQUAL (standalone '!' is not in this language)
    cmp  al, '!'
    je   .state_bang

    ; '<' → TK_LESS or TK_LESS_EQ
    cmp  al, '<'
    je   .state_lt

    ; '>' → TK_GREATER or TK_GREATER_EQ
    cmp  al, '>'
    je   .state_gt

    ; '-' → TK_MINUS or line comment '--'
    cmp  al, '-'
    je   .state_minus

    ; Single-character symbols
    cmp  al, '+'
    je   .single_plus
    cmp  al, '*'
    je   .single_multiply
    cmp  al, '/'
    je   .single_divide
    cmp  al, '%'
    je   .single_modulo
    cmp  al, '('
    je   .single_lparen
    cmp  al, ')'
    je   .single_rparen
    cmp  al, '['
    je   .single_lbracket
    cmp  al, ']'
    je   .single_rbracket
    cmp  al, ','
    je   .single_comma
    cmp  al, '.'
    je   .single_dot

    ; Unrecognized character → TK_ERROR
    call append_char
    mov  rax, TK_ERROR
    jmp  .done

; ── Emit newline token ─────────────────────────────────────
.emit_newline:
    mov  byte [lexeme], '\'
    mov  byte [lexeme+1], 'n'
    mov  byte [lexeme+2], 0
    mov  qword [lexeme_len], 2
    mov  rax, TK_NEWLINE
    jmp  .done

; ── S1: Identifier / Reserved word ─────────────────────────
.state_id:
    call append_char
.id_loop:
    call next_char
    cmp  al, 0
    je   .id_end
    call is_alnum_or_under
    jc   .id_loop_continue
    call putback_char
    jmp  .id_end
.id_loop_continue:
    call append_char
    jmp  .id_loop
.id_end:
    call lookup_keyword         ; rax = TK_* or TK_ID
    jmp  .done

; ── S2/S3/S4: Integer or float literal ─────────────────────
.state_number:
    call append_char
.num_int_loop:
    call next_char
    cmp  al, 0
    je   .num_is_int
    call is_digit
    jc   .num_int_digit
    cmp  al, '.'
    je   .num_dot
    call putback_char
    jmp  .num_is_int
.num_int_digit:
    call append_char
    jmp  .num_int_loop
.num_dot:
    ; Consume dot and require at least one digit after it
    call append_char
    call next_char
    cmp  al, 0
    je   .num_is_float
    call is_digit
    jc   .num_float_first_digit
    call putback_char
    jmp  .num_is_float
.num_float_first_digit:
    call append_char
.num_float_loop:
    call next_char
    cmp  al, 0
    je   .num_is_float
    call is_digit
    jc   .num_float_digit
    call putback_char
    jmp  .num_is_float
.num_float_digit:
    call append_char
    jmp  .num_float_loop
.num_is_float:
    mov  rax, TK_LIT_FLOAT
    jmp  .done
.num_is_int:
    mov  rax, TK_LIT_INT
    jmp  .done

; ── S5/S6: String literal ──────────────────────────────────
.state_string:
    ; Opening '"' is not stored in lexeme
.str_loop:
    call next_char
    cmp  al, 0
    je   .str_unterminated
    cmp  al, '"'
    je   .str_closed
    cmp  al, 10             ; newline inside string → error
    je   .str_unterminated
    call append_char
    jmp  .str_loop
.str_closed:
    mov  rax, TK_LIT_STRING
    jmp  .done
.str_unterminated:
    mov  rax, TK_ERROR
    jmp  .done

; ── '=' or '==' ────────────────────────────────────────────
.state_eq:
    call next_char
    cmp  al, '='
    jne  .eq_is_assign
    mov  byte [lexeme], '='
    mov  byte [lexeme+1], '='
    mov  byte [lexeme+2], 0
    mov  qword [lexeme_len], 2
    mov  rax, TK_EQUAL
    jmp  .done
.eq_is_assign:
    call putback_char
    mov  byte [lexeme], '='
    mov  byte [lexeme+1], 0
    mov  qword [lexeme_len], 1
    mov  rax, TK_ASSIGN
    jmp  .done

; ── '!=' ───────────────────────────────────────────────────
.state_bang:
    call next_char
    cmp  al, '='
    jne  .bang_error
    mov  byte [lexeme], '!'
    mov  byte [lexeme+1], '='
    mov  byte [lexeme+2], 0
    mov  qword [lexeme_len], 2
    mov  rax, TK_NOT_EQUAL
    jmp  .done
.bang_error:
    ; Standalone '!' is not a valid token in this language
    call putback_char
    mov  byte [lexeme], '!'
    mov  byte [lexeme+1], 0
    mov  qword [lexeme_len], 1
    mov  rax, TK_ERROR
    jmp  .done

; ── '<' or '<=' ────────────────────────────────────────────
.state_lt:
    call next_char
    cmp  al, '='
    jne  .lt_is_lt
    mov  byte [lexeme], '<'
    mov  byte [lexeme+1], '='
    mov  byte [lexeme+2], 0
    mov  qword [lexeme_len], 2
    mov  rax, TK_LESS_EQ
    jmp  .done
.lt_is_lt:
    call putback_char
    mov  byte [lexeme], '<'
    mov  byte [lexeme+1], 0
    mov  qword [lexeme_len], 1
    mov  rax, TK_LESS
    jmp  .done

; ── '>' or '>=' ────────────────────────────────────────────
.state_gt:
    call next_char
    cmp  al, '='
    jne  .gt_is_gt
    mov  byte [lexeme], '>'
    mov  byte [lexeme+1], '='
    mov  byte [lexeme+2], 0
    mov  qword [lexeme_len], 2
    mov  rax, TK_GREATER_EQ
    jmp  .done
.gt_is_gt:
    call putback_char
    mov  byte [lexeme], '>'
    mov  byte [lexeme+1], 0
    mov  qword [lexeme_len], 1
    mov  rax, TK_GREATER
    jmp  .done

; ── '-' or '--' (line comment) ─────────────────────────────
.state_minus:
    call next_char
    cmp  al, '-'
    je   .comment_line
    ; It's just a minus
    call putback_char
    mov  byte [lexeme], '-'
    mov  byte [lexeme+1], 0
    mov  qword [lexeme_len], 1
    mov  rax, TK_MINUS
    jmp  .done

.comment_line:
    ; Consume everything until end of line or EOF
.cmt_loop:
    call next_char
    cmp  al, 0
    je   .cmt_eof
    cmp  al, 10             ; newline ends the comment
    je   .cmt_newline
    jmp  .cmt_loop
.cmt_newline:
    ; The newline after a comment is still a statement terminator.
    ; Push it back so the next get_token call emits TK_NEWLINE.
    call putback_char
    ; Tail-call: discard comment, get next real token
    mov  qword [lexeme_len], 0
    mov  byte  [lexeme], 0
    pop  rbp
    jmp  get_token
.cmt_eof:
    mov  qword [lexeme_len], 0
    mov  byte  [lexeme], 0
    pop  rbp
    jmp  get_token

; ── Single-character symbols ───────────────────────────────
%macro single_tok 2         ; %1 = ascii char, %2 = token ID
    mov  byte [lexeme], %1
    mov  byte [lexeme+1], 0
    mov  qword [lexeme_len], 1
    mov  rax, %2
    jmp  .done
%endmacro

.single_plus:       single_tok '+', TK_PLUS
.single_multiply:   single_tok '*', TK_MULTIPLY
.single_divide:     single_tok '/', TK_DIVIDE
.single_modulo:     single_tok '%', TK_MODULO
.single_lparen:     single_tok '(', TK_LPAREN
.single_rparen:     single_tok ')', TK_RPAREN
.single_lbracket:   single_tok '[', TK_LBRACKET
.single_rbracket:   single_tok ']', TK_RBRACKET
.single_comma:      single_tok ',', TK_COMMA
.single_dot:        single_tok '.', TK_DOT

.emit_eof:
    mov  byte [lexeme], 0
    mov  qword [lexeme_len], 0
    mov  rax, TK_EOF

.done:
    pop  rbp
    ret

; ============================================================
; next_char — Read one character from stdin (buffered)
; Returns: al = next character, or 0 on EOF
; ============================================================
next_char:
    cmp  byte [has_putback], 1
    jne  .from_buffer
    mov  byte [has_putback], 0
    mov  al, [putback]
    ret

.from_buffer:
    mov  rcx, [buf_pos]
    cmp  rcx, [buf_len]
    jl   .read_from_buf

    ; Buffer empty — refill from stdin
    mov  rax, SYS_READ
    mov  rdi, STDIN
    mov  rsi, buf
    mov  rdx, BUF_SIZE
    syscall
    cmp  rax, 0
    jle  .eof
    mov  qword [buf_len], rax
    mov  qword [buf_pos], 0

.read_from_buf:
    mov  rcx, [buf_pos]
    mov  al, [buf + rcx]
    inc  rcx
    mov  [buf_pos], rcx
    ret

.eof:
    xor  al, al
    ret

; ============================================================
; putback_char — Push one character back into the stream
; Input: al = character to push back
; ============================================================
putback_char:
    mov  [putback], al
    mov  byte [has_putback], 1
    ret

; ============================================================
; append_char — Append al to lexeme[]
; Input: al = character to append
; ============================================================
append_char:
    mov  rcx, [lexeme_len]
    cmp  rcx, LEXEME_MAX - 1
    jge  .full
    mov  [lexeme + rcx], al
    inc  rcx
    mov  [lexeme_len], rcx
    mov  byte [lexeme + rcx], 0
.full:
    ret

; ============================================================
; is_alpha_or_under — Test if al ∈ [a-zA-Z_]
; Returns: CF=1 if true, CF=0 if false
; ============================================================
is_alpha_or_under:
    cmp  al, '_'
    je   .yes
    cmp  al, 'a'
    jl   .check_upper
    cmp  al, 'z'
    jle  .yes
.check_upper:
    cmp  al, 'A'
    jl   .no
    cmp  al, 'Z'
    jle  .yes
.no: clc
    ret
.yes: stc
    ret

; ============================================================
; is_digit — Test if al ∈ [0-9]
; Returns: CF=1 if true, CF=0 if false
; ============================================================
is_digit:
    cmp  al, '0'
    jl   .no
    cmp  al, '9'
    jle  .yes
.no: clc
    ret
.yes: stc
    ret

; ============================================================
; is_alnum_or_under — Test if al ∈ [a-zA-Z0-9_]
; Returns: CF=1 if true, CF=0 if false
; ============================================================
is_alnum_or_under:
    call is_alpha_or_under
    jc   .yes
    call is_digit
    jc   .yes
    clc
    ret
.yes: stc
    ret

; ============================================================
; lookup_keyword — Match lexeme[] against all reserved words
; Returns: rax = matching TK_* constant, or TK_ID
; ============================================================
lookup_keyword:
    mov  rsi, kw_is
    call compare_str
    jc   .kw_is

    mov  rsi, kw_where
    call compare_str
    jc   .kw_where

    mov  rsi, kw_and
    call compare_str
    jc   .kw_and

    mov  rsi, kw_or
    call compare_str
    jc   .kw_or

    mov  rsi, kw_not
    call compare_str
    jc   .kw_not

    mov  rsi, kw_every
    call compare_str
    jc   .kw_every

    mov  rsi, kw_in
    call compare_str
    jc   .kw_in

    mov  rsi, kw_of
    call compare_str
    jc   .kw_of

    mov  rsi, kw_let
    call compare_str
    jc   .kw_let

    mov  rsi, kw_be
    call compare_str
    jc   .kw_be

    mov  rsi, kw_from
    call compare_str
    jc   .kw_from

    mov  rsi, kw_to
    call compare_str
    jc   .kw_to

    mov  rsi, kw_min
    call compare_str
    jc   .kw_min

    mov  rsi, kw_max
    call compare_str
    jc   .kw_max

    mov  rsi, kw_sum
    call compare_str
    jc   .kw_sum

    mov  rsi, kw_true
    call compare_str
    jc   .kw_true

    mov  rsi, kw_false
    call compare_str
    jc   .kw_false

    mov  rax, TK_ID
    ret

.kw_is:     mov rax, TK_IS
            ret
.kw_where:  mov rax, TK_WHERE
            ret
.kw_and:    mov rax, TK_AND
            ret
.kw_or:     mov rax, TK_OR
            ret
.kw_not:    mov rax, TK_NOT
            ret
.kw_every:  mov rax, TK_EVERY
            ret
.kw_in:     mov rax, TK_IN
            ret
.kw_of:     mov rax, TK_OF
            ret
.kw_let:    mov rax, TK_LET
            ret
.kw_be:     mov rax, TK_BE
            ret
.kw_from:   mov rax, TK_FROM
            ret
.kw_to:     mov rax, TK_TO
            ret
.kw_min:    mov rax, TK_MIN
            ret
.kw_max:    mov rax, TK_MAX
            ret
.kw_sum:    mov rax, TK_SUM
            ret
.kw_true:   mov rax, TK_TRUE
            ret
.kw_false:  mov rax, TK_FALSE
            ret

; ============================================================
; compare_str — Compare lexeme[] byte-by-byte with [rsi]
; Input:  rsi = pointer to null-terminated reference string
; Returns: CF=1 if equal, CF=0 otherwise
; ============================================================
compare_str:
    push rdi
    push rsi
    push rcx
    mov  rdi, lexeme
    xor  rcx, rcx
.loop:
    mov  al, [rdi + rcx]
    mov  bl, [rsi + rcx]
    cmp  al, bl
    jne  .no
    cmp  al, 0
    je   .yes
    inc  rcx
    jmp  .loop
.yes:
    pop  rcx
    pop  rsi
    pop  rdi
    stc
    ret
.no:
    pop  rcx
    pop  rsi
    pop  rdi
    clc
    ret