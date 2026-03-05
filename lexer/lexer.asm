; ============================================================
;  LEXICAL ANALYZER — DFA Logic
;  Module: lexer.asm
;
;  Implements the Deterministic Finite Automaton (DFA) that
;  scans an input stream and produces tokens one at a time.
;
;  Exported symbols (global):
;    - get_token   : reads next token from stdin
;    - lexeme      : current token text (null-terminated)
;    - lexeme_len  : current token text length
;
;  Imported symbols (extern from symbol_table.asm):
;    - kw_*        : keyword strings for lookup
;
;  Convention:
;    get_token returns rax = token ID, lexeme[] = token text.
;    All helper functions are local (not exported).
; ============================================================

; ── Linux x86-64 Syscalls ──────────────────────────────────
SYS_READ  equ 0
STDIN     equ 0

; ── Token IDs ──────────────────────────────────────────────
; Duplicated here so lexer.asm compiles standalone.
; Single source of truth is symbol_table.asm — keep in sync.
TK_INT        equ 1
TK_FLOAT_KW   equ 2
TK_BOOL       equ 3
TK_STRING_KW  equ 4
TK_IF         equ 5
TK_ELSE       equ 6
TK_WHILE      equ 7
TK_FOR        equ 8
TK_RETURN     equ 9
TK_TRUE       equ 10
TK_FALSE      equ 11
TK_LIT_INT    equ 12
TK_LIT_FLOAT  equ 13
TK_LIT_STRING equ 14
TK_ID         equ 15
TK_ASSIGN     equ 16
TK_PLUS       equ 17
TK_MINUS      equ 18
TK_STAR       equ 19
TK_SLASH      equ 20
TK_EQ         equ 21
TK_NEQ        equ 22
TK_LT         equ 23
TK_GT         equ 24
TK_LTE        equ 25
TK_GTE        equ 26
TK_AND        equ 27
TK_OR         equ 28
TK_NOT        equ 29
TK_LPAREN     equ 30
TK_RPAREN     equ 31
TK_LBRACE     equ 32
TK_RBRACE     equ 33
TK_SEMICOLON  equ 34
TK_COMMA      equ 35
TK_EOF        equ 36
TK_ERROR      equ 37

; ── Buffer sizes ────────────────────────────────────────────
BUF_SIZE   equ 4096
LEXEME_MAX equ 256

; ── Imported data (symbol_table.asm) ────────────
extern kw_int, kw_float, kw_bool, kw_string
extern kw_if, kw_else, kw_while, kw_for, kw_return
extern kw_true, kw_false

; ── Exported symbols ────────────────────────────────────────
global get_token
global lexeme, lexeme_len   ; main.asm needs to read these

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
;  get_token — Read the next token from stdin
;
;  Returns:
;    rax = token ID  (one of the TK_* constants above)
;    lexeme[] is filled with the token text (null-terminated)
;    lexeme_len holds the byte count
;
;  Clobbers: rax, rcx, rsi, rdi, al, bl
; ============================================================
get_token:
    push rbp
    mov  rbp, rsp

    ; Clear lexeme
    mov qword [lexeme_len], 0
    mov byte  [lexeme], 0

; ── State S0: skip whitespace ──────────────────────────────
.s0_skip_ws:
    call next_char
    cmp al, 0
    je  .emit_eof

    cmp al, ' '
    je  .s0_skip_ws
    cmp al, 9               ; tab
    je  .s0_skip_ws
    cmp al, 10              ; newline
    je  .s0_skip_ws
    cmp al, 13              ; carriage return
    je  .s0_skip_ws

; ── Classify first character ───────────────────────────────

    ; [a-zA-Z_] → identifier or keyword (S1)
    call is_alpha_or_under
    jc   .state_id

    ; [0-9] → number (S2)
    call is_digit
    jc   .state_number

    ; '"' → string literal (S5)
    cmp al, '"'
    je  .state_string

    ; '=' → TK_ASSIGN or TK_EQ (S7)
    cmp al, '='
    je  .state_eq

    ; '!' → TK_NOT or TK_NEQ (S10)
    cmp al, '!'
    je  .state_not

    ; '<' → TK_LT or TK_LTE (S12)
    cmp al, '<'
    je  .state_lt

    ; '>' → TK_GT or TK_GTE (S15)
    cmp al, '>'
    je  .state_gt

    ; '&' → TK_AND (S18), single '&' is an error
    cmp al, '&'
    je  .state_amp

    ; '|' → TK_OR (S20), single '|' is an error
    cmp al, '|'
    je  .state_pipe

    ; '/' → TK_SLASH or block comment (S22)
    cmp al, '/'
    je  .state_slash

    ; Single-character symbols
    cmp al, '+'
    je  .single_plus
    cmp al, '-'
    je  .single_minus
    cmp al, '*'
    je  .single_star
    cmp al, '('
    je  .single_lparen
    cmp al, ')'
    je  .single_rparen
    cmp al, '{'
    je  .single_lbrace
    cmp al, '}'
    je  .single_rbrace
    cmp al, ';'
    je  .single_semi
    cmp al, ','
    je  .single_comma

    ; Unrecognized character → TK_ERROR
    call append_char
    mov rax, TK_ERROR
    jmp .done

; ── S1: Identifier / Reserved word ────────────────────────
.state_id:
    call append_char
.id_loop:
    call next_char
    cmp al, 0
    je  .id_end
    call is_alnum_or_under
    jc  .id_loop_continue
    call putback_char           ; not part of the identifier, push back
    jmp .id_end
.id_loop_continue:
    call append_char
    jmp .id_loop
.id_end:
    call lookup_keyword         ; rax = TK_* or TK_ID
    jmp .done

; ── S2/S3/S4: Integer or float literal ─────────────────────
.state_number:
    call append_char
.num_int_loop:
    call next_char
    cmp al, 0
    je  .num_is_int
    call is_digit
    jc  .num_int_digit
    cmp al, '.'
    je  .num_dot
    call putback_char
    jmp .num_is_int
.num_int_digit:
    call append_char
    jmp .num_int_loop
.num_dot:
    ; S3: consume dot and require at least one digit after it
    call append_char
    call next_char
    cmp al, 0
    je  .num_is_float           ; "5." at EOF → float
    call is_digit
    jc  .num_float_first_digit
    call putback_char           ; "5.x" → float with no fraction digits
    jmp .num_is_float
.num_float_first_digit:
    call append_char
.num_float_loop:
    call next_char
    cmp al, 0
    je  .num_is_float
    call is_digit
    jc  .num_float_digit
    call putback_char
    jmp .num_is_float
.num_float_digit:
    call append_char
    jmp .num_float_loop
.num_is_float:
    mov rax, TK_LIT_FLOAT
    jmp .done
.num_is_int:
    mov rax, TK_LIT_INT
    jmp .done

; ── S5/S6: String literal ──────────────────────────────────
.state_string:
    ; Opening '"' is not stored in lexeme
.str_loop:
    call next_char
    cmp al, 0
    je  .str_unterminated
    cmp al, '"'
    je  .str_closed
    cmp al, 10                  ; newline inside string → error
    je  .str_unterminated
    call append_char
    jmp .str_loop
.str_closed:
    mov rax, TK_LIT_STRING
    jmp .done
.str_unterminated:
    mov rax, TK_ERROR
    jmp .done

; ── S7/S8/S9: '=' or '==' ─────────────────────────────────
.state_eq:
    call next_char
    cmp al, '='
    jne .eq_is_assign
    mov byte [lexeme],   '='
    mov byte [lexeme+1], '='
    mov byte [lexeme+2], 0
    mov qword [lexeme_len], 2
    mov rax, TK_EQ
    jmp .done
.eq_is_assign:
    call putback_char
    mov byte [lexeme],   '='
    mov byte [lexeme+1], 0
    mov qword [lexeme_len], 1
    mov rax, TK_ASSIGN
    jmp .done

; ── S10/S11: '!' or '!=' ──────────────────────────────────
.state_not:
    call next_char
    cmp al, '='
    jne .not_is_bang
    mov byte [lexeme],   '!'
    mov byte [lexeme+1], '='
    mov byte [lexeme+2], 0
    mov qword [lexeme_len], 2
    mov rax, TK_NEQ
    jmp .done
.not_is_bang:
    call putback_char
    mov byte [lexeme],   '!'
    mov byte [lexeme+1], 0
    mov qword [lexeme_len], 1
    mov rax, TK_NOT
    jmp .done

; ── S12/S13/S14: '<' or '<=' ──────────────────────────────
.state_lt:
    call next_char
    cmp al, '='
    jne .lt_is_lt
    mov byte [lexeme],   '<'
    mov byte [lexeme+1], '='
    mov byte [lexeme+2], 0
    mov qword [lexeme_len], 2
    mov rax, TK_LTE
    jmp .done
.lt_is_lt:
    call putback_char
    mov byte [lexeme],   '<'
    mov byte [lexeme+1], 0
    mov qword [lexeme_len], 1
    mov rax, TK_LT
    jmp .done

; ── S15/S16/S17: '>' or '>=' ──────────────────────────────
.state_gt:
    call next_char
    cmp al, '='
    jne .gt_is_gt
    mov byte [lexeme],   '>'
    mov byte [lexeme+1], '='
    mov byte [lexeme+2], 0
    mov qword [lexeme_len], 2
    mov rax, TK_GTE
    jmp .done
.gt_is_gt:
    call putback_char
    mov byte [lexeme],   '>'
    mov byte [lexeme+1], 0
    mov qword [lexeme_len], 1
    mov rax, TK_GT
    jmp .done

; ── S18/S19: '&&' ─────────────────────────────────────────
.state_amp:
    call next_char
    cmp al, '&'
    jne .amp_error
    mov byte [lexeme],   '&'
    mov byte [lexeme+1], '&'
    mov byte [lexeme+2], 0
    mov qword [lexeme_len], 2
    mov rax, TK_AND
    jmp .done
.amp_error:
    call putback_char
    mov byte [lexeme],   '&'
    mov byte [lexeme+1], 0
    mov qword [lexeme_len], 1
    mov rax, TK_ERROR
    jmp .done

; ── S20/S21: '||' ─────────────────────────────────────────
.state_pipe:
    call next_char
    cmp al, '|'
    jne .pipe_error
    mov byte [lexeme],   '|'
    mov byte [lexeme+1], '|'
    mov byte [lexeme+2], 0
    mov qword [lexeme_len], 2
    mov rax, TK_OR
    jmp .done
.pipe_error:
    call putback_char
    mov byte [lexeme],   '|'
    mov byte [lexeme+1], 0
    mov qword [lexeme_len], 1
    mov rax, TK_ERROR
    jmp .done

; ── S22/S23/S24: '/' or block comment '/* ... */' ─────────
.state_slash:
    call next_char
    cmp al, '*'
    je  .comment_start
    call putback_char
    mov byte [lexeme],   '/'
    mov byte [lexeme+1], 0
    mov qword [lexeme_len], 1
    mov rax, TK_SLASH
    jmp .done

.comment_start:
.cmt_loop:
    call next_char
    cmp al, 0
    je  .cmt_eof_error
    cmp al, '*'
    jne .cmt_loop
.cmt_after_star:
    call next_char
    cmp al, 0
    je  .cmt_eof_error
    cmp al, '/'
    je  .cmt_closed
    cmp al, '*'
    je  .cmt_after_star     ; handle '***/' correctly
    jmp .cmt_loop
.cmt_closed:
    ; Discard comment — tail-call get_token for the next real token
    mov qword [lexeme_len], 0
    mov byte  [lexeme], 0
    pop rbp
    jmp get_token
.cmt_eof_error:
    mov rax, TK_ERROR
    jmp .done

; ── Single-character symbols ───────────────────────────────
%macro single_tok 2             ; %1 = ascii char, %2 = token ID
    mov byte [lexeme],   %1
    mov byte [lexeme+1], 0
    mov qword [lexeme_len], 1
    mov rax, %2
    jmp .done
%endmacro

.single_plus:   single_tok '+', TK_PLUS
.single_minus:  single_tok '-', TK_MINUS
.single_star:   single_tok '*', TK_STAR
.single_lparen: single_tok '(', TK_LPAREN
.single_rparen: single_tok ')', TK_RPAREN
.single_lbrace: single_tok '{', TK_LBRACE
.single_rbrace: single_tok '}', TK_RBRACE
.single_semi:   single_tok ';', TK_SEMICOLON
.single_comma:  single_tok ',', TK_COMMA

.emit_eof:
    mov byte  [lexeme], 0
    mov qword [lexeme_len], 0
    mov rax, TK_EOF

.done:
    pop rbp
    ret

; ============================================================
;  next_char — Read one character from stdin (buffered)
;  Returns: al = next character, or 0 on EOF
; ============================================================
next_char:
    cmp byte [has_putback], 1
    jne .from_buffer
    mov byte [has_putback], 0
    mov al, [putback]
    ret

.from_buffer:
    mov rcx, [buf_pos]
    cmp rcx, [buf_len]
    jl  .read_from_buf

    ; Buffer empty — refill from stdin
    mov rax, SYS_READ
    mov rdi, STDIN
    mov rsi, buf
    mov rdx, BUF_SIZE
    syscall
    cmp rax, 0
    jle .eof
    mov qword [buf_len], rax
    mov qword [buf_pos], 0

.read_from_buf:
    mov rcx, [buf_pos]
    mov al,  [buf + rcx]
    inc rcx
    mov [buf_pos], rcx
    ret

.eof:
    xor al, al
    ret

; ============================================================
;  putback_char — Push one character back into the stream
;  Input: al = character to push back
; ============================================================
putback_char:
    mov [putback], al
    mov byte [has_putback], 1
    ret

; ============================================================
;  append_char — Append al to lexeme[]
;  Input: al = character to append
; ============================================================
append_char:
    mov rcx, [lexeme_len]
    cmp rcx, LEXEME_MAX - 1
    jge .full
    mov [lexeme + rcx], al
    inc rcx
    mov [lexeme_len], rcx
    mov byte [lexeme + rcx], 0
.full:
    ret

; ============================================================
;  is_alpha_or_under — Test if al ∈ [a-zA-Z_]
;  Returns: CF=1 if true, CF=0 if false
; ============================================================
is_alpha_or_under:
    cmp al, '_'
    je  .yes
    cmp al, 'a'
    jl  .check_upper
    cmp al, 'z'
    jle .yes
.check_upper:
    cmp al, 'A'
    jl  .no
    cmp al, 'Z'
    jle .yes
.no:  clc
    ret
.yes: stc
    ret

; ============================================================
;  is_digit — Test if al ∈ [0-9]
;  Returns: CF=1 if true, CF=0 if false
; ============================================================
is_digit:
    cmp al, '0'
    jl  .no
    cmp al, '9'
    jle .yes
.no:  clc
    ret
.yes: stc
    ret

; ============================================================
;  is_alnum_or_under — Test if al ∈ [a-zA-Z0-9_]
;  Returns: CF=1 if true, CF=0 if false
; ============================================================
is_alnum_or_under:
    call is_alpha_or_under
    jc  .yes
    call is_digit
    jc  .yes
    clc
    ret
.yes: stc
    ret

; ============================================================
;  lookup_keyword — Match lexeme[] against all reserved words
;  Returns: rax = matching TK_* constant, or TK_ID
; ============================================================
lookup_keyword:
    mov rsi, kw_int    ; call compare_str
    call compare_str
    jc  .kw_int
    mov rsi, kw_float
    call compare_str
    jc  .kw_float
    mov rsi, kw_bool
    call compare_str
    jc  .kw_bool
    mov rsi, kw_string
    call compare_str
    jc  .kw_string
    mov rsi, kw_if
    call compare_str
    jc  .kw_if
    mov rsi, kw_else
    call compare_str
    jc  .kw_else
    mov rsi, kw_while
    call compare_str
    jc  .kw_while
    mov rsi, kw_for
    call compare_str
    jc  .kw_for
    mov rsi, kw_return
    call compare_str
    jc  .kw_return
    mov rsi, kw_true
    call compare_str
    jc  .kw_true
    mov rsi, kw_false
    call compare_str
    jc  .kw_false
    mov rax, TK_ID
    ret

.kw_int:    mov rax, TK_INT        ; ret
            ret
.kw_float:  mov rax, TK_FLOAT_KW   ; ret
            ret
.kw_bool:   mov rax, TK_BOOL       ; ret
            ret
.kw_string: mov rax, TK_STRING_KW  ; ret
            ret
.kw_if:     mov rax, TK_IF         ; ret
            ret
.kw_else:   mov rax, TK_ELSE       ; ret
            ret
.kw_while:  mov rax, TK_WHILE      ; ret
            ret
.kw_for:    mov rax, TK_FOR        ; ret
            ret
.kw_return: mov rax, TK_RETURN     ; ret
            ret
.kw_true:   mov rax, TK_TRUE       ; ret
            ret
.kw_false:  mov rax, TK_FALSE      ; ret
            ret

; ============================================================
;  compare_str — Compare lexeme[] byte-by-byte with [rsi]
;  Input:   rsi = pointer to null-terminated reference string
;  Returns: CF=1 if equal, CF=0 otherwise
; ============================================================
compare_str:
    push rdi
    push rsi
    push rcx
    mov  rdi, lexeme
    xor  rcx, rcx
.loop:
    mov al, [rdi + rcx]
    mov bl, [rsi + rcx]
    cmp al, bl
    jne .no
    cmp al, 0
    je  .yes
    inc rcx
    jmp .loop
.yes:
    pop rcx
    pop rsi
    pop rdi
    stc
    ret
.no:
    pop rcx
    pop rsi
    pop rdi
    clc
    ret
