; ============================================================
;  SYMBOL TABLE — BASE Language v0.1
;  Module: symbol_table.asm
;
;  Contains all static data shared across the compiler:
;    - Token ID constants
;    - Keyword strings (for lookup)
;    - Token name strings (for output)
;    - Token name pointer table (indexed by token ID)
;
;  Exported symbols (global):
;    - kw_*          : keyword strings used by lexer.asm
;    - tk_name_table : pointer table used by main.asm
;    - str_tk_*      : token name strings used by main.asm
;    - str_arrow, str_close, str_header : output strings
; ============================================================

; ── Token ID constants ─────────────────────────────────────
; Exported so every module can use them via %include "tokens.inc"
; (defined here as equates — no section needed)

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

section .data

; ── Keyword strings ────────────────────────────────────────
; Used by lexer.asm → lookup_keyword to classify identifiers.
; Each string is null-terminated.

global kw_int, kw_float, kw_bool, kw_string
global kw_if, kw_else, kw_while, kw_for, kw_return
global kw_true, kw_false

kw_int    db 'int', 0
kw_float  db 'float', 0
kw_bool   db 'bool', 0
kw_string db 'string', 0
kw_if     db 'if', 0
kw_else   db 'else', 0
kw_while  db 'while', 0
kw_for    db 'for', 0
kw_return db 'return', 0
kw_true   db 'true', 0
kw_false  db 'false', 0

; ── Token name strings ─────────────────────────────────────
; Used by main.asm → print_token_name to display token type.
; Padded to fixed width for aligned output.

global str_tk_int, str_tk_float_kw, str_tk_bool, str_tk_string_kw
global str_tk_if, str_tk_else, str_tk_while, str_tk_for, str_tk_return
global str_tk_true, str_tk_false
global str_tk_lit_int, str_tk_lit_float, str_tk_lit_string
global str_tk_id
global str_tk_assign, str_tk_plus, str_tk_minus, str_tk_star, str_tk_slash
global str_tk_eq, str_tk_neq, str_tk_lt, str_tk_gt, str_tk_lte, str_tk_gte
global str_tk_and, str_tk_or, str_tk_not
global str_tk_lparen, str_tk_rparen, str_tk_lbrace, str_tk_rbrace
global str_tk_semicolon, str_tk_comma
global str_tk_eof, str_tk_error

str_tk_int        db 'TK_INT         ', 0
str_tk_float_kw   db 'TK_FLOAT       ', 0
str_tk_bool       db 'TK_BOOL        ', 0
str_tk_string_kw  db 'TK_STRING      ', 0
str_tk_if         db 'TK_IF          ', 0
str_tk_else       db 'TK_ELSE        ', 0
str_tk_while      db 'TK_WHILE       ', 0
str_tk_for        db 'TK_FOR         ', 0
str_tk_return     db 'TK_RETURN      ', 0
str_tk_true       db 'TK_TRUE        ', 0
str_tk_false      db 'TK_FALSE       ', 0
str_tk_lit_int    db 'TK_LIT_INT     ', 0
str_tk_lit_float  db 'TK_LIT_FLOAT   ', 0
str_tk_lit_string db 'TK_LIT_STRING  ', 0
str_tk_id         db 'TK_ID          ', 0
str_tk_assign     db 'TK_ASSIGN      ', 0
str_tk_plus       db 'TK_PLUS        ', 0
str_tk_minus      db 'TK_MINUS       ', 0
str_tk_star       db 'TK_STAR        ', 0
str_tk_slash      db 'TK_SLASH       ', 0
str_tk_eq         db 'TK_EQ          ', 0
str_tk_neq        db 'TK_NEQ         ', 0
str_tk_lt         db 'TK_LT          ', 0
str_tk_gt         db 'TK_GT          ', 0
str_tk_lte        db 'TK_LTE         ', 0
str_tk_gte        db 'TK_GTE         ', 0
str_tk_and        db 'TK_AND         ', 0
str_tk_or         db 'TK_OR          ', 0
str_tk_not        db 'TK_NOT         ', 0
str_tk_lparen     db 'TK_LPAREN      ', 0
str_tk_rparen     db 'TK_RPAREN      ', 0
str_tk_lbrace     db 'TK_LBRACE      ', 0
str_tk_rbrace     db 'TK_RBRACE      ', 0
str_tk_semicolon  db 'TK_SEMICOLON   ', 0
str_tk_comma      db 'TK_COMMA       ', 0
str_tk_eof        db 'TK_EOF         ', 0
str_tk_error      db 'TK_ERROR       ', 0

; ── Output formatting strings ──────────────────────────────
global str_arrow, str_close, str_header

str_arrow  db ' --> [', 0
str_close  db ']', 10, 0
str_header db '=== LEXICAL ANALYZER ===', 10
           db 'TOKEN            LEXEME', 10
           db '─────────────────────────────', 10, 0

; ── Token name pointer table ───────────────────────────────
; Indexed by token ID (1-based). Used by print_token_name.
; Entry at index i (0-based) points to the name of token i+1.

global tk_name_table

tk_name_table:
    dq str_tk_int           ; TK_INT         = 1
    dq str_tk_float_kw      ; TK_FLOAT_KW    = 2
    dq str_tk_bool          ; TK_BOOL        = 3
    dq str_tk_string_kw     ; TK_STRING_KW   = 4
    dq str_tk_if            ; TK_IF          = 5
    dq str_tk_else          ; TK_ELSE        = 6
    dq str_tk_while         ; TK_WHILE       = 7
    dq str_tk_for           ; TK_FOR         = 8
    dq str_tk_return        ; TK_RETURN      = 9
    dq str_tk_true          ; TK_TRUE        = 10
    dq str_tk_false         ; TK_FALSE       = 11
    dq str_tk_lit_int       ; TK_LIT_INT     = 12
    dq str_tk_lit_float     ; TK_LIT_FLOAT   = 13
    dq str_tk_lit_string    ; TK_LIT_STRING  = 14
    dq str_tk_id            ; TK_ID          = 15
    dq str_tk_assign        ; TK_ASSIGN      = 16
    dq str_tk_plus          ; TK_PLUS        = 17
    dq str_tk_minus         ; TK_MINUS       = 18
    dq str_tk_star          ; TK_STAR        = 19
    dq str_tk_slash         ; TK_SLASH       = 20
    dq str_tk_eq            ; TK_EQ          = 21
    dq str_tk_neq           ; TK_NEQ         = 22
    dq str_tk_lt            ; TK_LT          = 23
    dq str_tk_gt            ; TK_GT          = 24
    dq str_tk_lte           ; TK_LTE         = 25
    dq str_tk_gte           ; TK_GTE         = 26
    dq str_tk_and           ; TK_AND         = 27
    dq str_tk_or            ; TK_OR          = 28
    dq str_tk_not           ; TK_NOT         = 29
    dq str_tk_lparen        ; TK_LPAREN      = 30
    dq str_tk_rparen        ; TK_RPAREN      = 31
    dq str_tk_lbrace        ; TK_LBRACE      = 32
    dq str_tk_rbrace        ; TK_RBRACE      = 33
    dq str_tk_semicolon     ; TK_SEMICOLON   = 34
    dq str_tk_comma         ; TK_COMMA       = 35
    dq str_tk_eof           ; TK_EOF         = 36
    dq str_tk_error         ; TK_ERROR       = 37