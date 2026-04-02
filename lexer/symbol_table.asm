; ============================================================
; SYMBOL TABLE — Declarative Language v1.0
; Module: symbol_table.asm
;
; Contains all static data shared across the compiler:
;   - Token ID constants
;   - Keyword strings (for lookup)
;   - Token name strings (for output)
;   - Token name pointer table (indexed by token ID)
;
; Exported symbols (global):
;   - kw_*       : keyword strings used by lexer.asm
;   - tk_name_table : pointer table used by main.asm
;   - str_tk_*   : token name strings used by main.asm
;   - str_arrow, str_close, str_header : output strings
; ============================================================

; ── Token ID constants ─────────────────────────────────────
; Keywords
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

; Literals
TK_LIT_INT      equ 18
TK_LIT_FLOAT    equ 19
TK_LIT_STRING   equ 20

; Identifier
TK_ID           equ 21

; Operators — comparison
TK_GREATER      equ 22
TK_LESS         equ 23
TK_GREATER_EQ   equ 24
TK_LESS_EQ      equ 25
TK_EQUAL        equ 26
TK_NOT_EQUAL    equ 27

; Operators — assignment
TK_ASSIGN       equ 28

; Operators — arithmetic
TK_PLUS         equ 29
TK_MINUS        equ 30
TK_MULTIPLY     equ 31
TK_DIVIDE       equ 32
TK_MODULO       equ 33

; Delimiters
TK_LPAREN       equ 34
TK_RPAREN       equ 35
TK_LBRACKET     equ 36
TK_RBRACKET     equ 37
TK_COMMA        equ 38
TK_DOT          equ 39
TK_NEWLINE      equ 40

; Special
TK_EOF          equ 41
TK_ERROR        equ 42

section .data

; ── Keyword strings ────────────────────────────────────────
; Used by lexer.asm → lookup_keyword to classify identifiers.
; Each string is null-terminated.

global kw_is, kw_where, kw_and, kw_or, kw_not
global kw_every, kw_in, kw_of, kw_let, kw_be
global kw_from, kw_to, kw_min, kw_max, kw_sum
global kw_true, kw_false

kw_is       db 'is', 0
kw_where    db 'where', 0
kw_and      db 'and', 0
kw_or       db 'or', 0
kw_not      db 'not', 0
kw_every    db 'every', 0
kw_in       db 'in', 0
kw_of       db 'of', 0
kw_let      db 'let', 0
kw_be       db 'be', 0
kw_from     db 'from', 0
kw_to       db 'to', 0
kw_min      db 'min', 0
kw_max      db 'max', 0
kw_sum      db 'sum', 0
kw_true     db 'true', 0
kw_false    db 'false', 0

; ── Token name strings ─────────────────────────────────────
; Padded to fixed width for aligned output.

global str_tk_is, str_tk_where, str_tk_and, str_tk_or, str_tk_not
global str_tk_every, str_tk_in, str_tk_of, str_tk_let, str_tk_be
global str_tk_from, str_tk_to, str_tk_min, str_tk_max, str_tk_sum
global str_tk_true, str_tk_false
global str_tk_lit_int, str_tk_lit_float, str_tk_lit_string
global str_tk_id
global str_tk_greater, str_tk_less, str_tk_greater_eq, str_tk_less_eq
global str_tk_equal, str_tk_not_equal, str_tk_assign
global str_tk_plus, str_tk_minus, str_tk_multiply, str_tk_divide, str_tk_modulo
global str_tk_lparen, str_tk_rparen, str_tk_lbracket, str_tk_rbracket
global str_tk_comma, str_tk_dot, str_tk_newline
global str_tk_eof, str_tk_error

str_tk_is           db 'TK_IS           ', 0
str_tk_where        db 'TK_WHERE        ', 0
str_tk_and          db 'TK_AND          ', 0
str_tk_or           db 'TK_OR           ', 0
str_tk_not          db 'TK_NOT          ', 0
str_tk_every        db 'TK_EVERY        ', 0
str_tk_in           db 'TK_IN           ', 0
str_tk_of           db 'TK_OF           ', 0
str_tk_let          db 'TK_LET          ', 0
str_tk_be           db 'TK_BE           ', 0
str_tk_from         db 'TK_FROM         ', 0
str_tk_to           db 'TK_TO           ', 0
str_tk_min          db 'TK_MIN          ', 0
str_tk_max          db 'TK_MAX          ', 0
str_tk_sum          db 'TK_SUM          ', 0
str_tk_true         db 'TK_TRUE         ', 0
str_tk_false        db 'TK_FALSE        ', 0
str_tk_lit_int      db 'TK_LIT_INT      ', 0
str_tk_lit_float    db 'TK_LIT_FLOAT    ', 0
str_tk_lit_string   db 'TK_LIT_STRING   ', 0
str_tk_id           db 'TK_ID           ', 0
str_tk_greater      db 'TK_GREATER      ', 0
str_tk_less         db 'TK_LESS         ', 0
str_tk_greater_eq   db 'TK_GREATER_EQ   ', 0
str_tk_less_eq      db 'TK_LESS_EQ      ', 0
str_tk_equal        db 'TK_EQUAL        ', 0
str_tk_not_equal    db 'TK_NOT_EQUAL    ', 0
str_tk_assign       db 'TK_ASSIGN       ', 0
str_tk_plus         db 'TK_PLUS         ', 0
str_tk_minus        db 'TK_MINUS        ', 0
str_tk_multiply     db 'TK_MULTIPLY     ', 0
str_tk_divide       db 'TK_DIVIDE       ', 0
str_tk_modulo       db 'TK_MODULO       ', 0
str_tk_lparen       db 'TK_LPAREN       ', 0
str_tk_rparen       db 'TK_RPAREN       ', 0
str_tk_lbracket     db 'TK_LBRACKET     ', 0
str_tk_rbracket     db 'TK_RBRACKET     ', 0
str_tk_comma        db 'TK_COMMA        ', 0
str_tk_dot          db 'TK_DOT          ', 0
str_tk_newline      db 'TK_NEWLINE      ', 0
str_tk_eof          db 'TK_EOF          ', 0
str_tk_error        db 'TK_ERROR        ', 0

; ── Output formatting strings ──────────────────────────────
global str_arrow, str_close, str_header

str_arrow   db ' --> [', 0
str_close   db ']', 10, 0
str_header  db '=== LEXICAL ANALYZER — Declarative Language ===', 10
            db 'TOKEN            LEXEME', 10
            db 10, 0

; ── Token name pointer table ───────────────────────────────
; Indexed by token ID (1-based).
global tk_name_table

tk_name_table:
    dq str_tk_is            ; 1
    dq str_tk_where         ; 2
    dq str_tk_and           ; 3
    dq str_tk_or            ; 4
    dq str_tk_not           ; 5
    dq str_tk_every         ; 6
    dq str_tk_in            ; 7
    dq str_tk_of            ; 8
    dq str_tk_let           ; 9
    dq str_tk_be            ; 10
    dq str_tk_from          ; 11
    dq str_tk_to            ; 12
    dq str_tk_min           ; 13
    dq str_tk_max           ; 14
    dq str_tk_sum           ; 15
    dq str_tk_true          ; 16
    dq str_tk_false         ; 17
    dq str_tk_lit_int       ; 18
    dq str_tk_lit_float     ; 19
    dq str_tk_lit_string    ; 20
    dq str_tk_id            ; 21
    dq str_tk_greater       ; 22
    dq str_tk_less          ; 23
    dq str_tk_greater_eq    ; 24
    dq str_tk_less_eq       ; 25
    dq str_tk_equal         ; 26
    dq str_tk_not_equal     ; 27
    dq str_tk_assign        ; 28
    dq str_tk_plus          ; 29
    dq str_tk_minus         ; 30
    dq str_tk_multiply      ; 31
    dq str_tk_divide        ; 32
    dq str_tk_modulo        ; 33
    dq str_tk_lparen        ; 34
    dq str_tk_rparen        ; 35
    dq str_tk_lbracket      ; 36
    dq str_tk_rbracket      ; 37
    dq str_tk_comma         ; 38
    dq str_tk_dot           ; 39
    dq str_tk_newline       ; 40
    dq str_tk_eof           ; 41
    dq str_tk_error         ; 42