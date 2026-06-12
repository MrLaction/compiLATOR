;parser.asm — stage 2: recursive-descent parser for LATOR
;
;LL(1) over the token stream from get_token, one token of lookahead.
;Builds the AST (ast.asm arena, %included here) for the declarative
;grammar: bindings via "is"/"let..be", filters via "where", aggregates,
;membership lists, "every element <= next" and the reserved "path"
;form. On a syntax error prints the offending line and exits 1.
;
;Exports: parse_program (rax = program AST root).
;Imports: get_token/lexeme (lexer.asm), intern_str (strpool.asm).

default abs

%include "ast.asm"

SYS_WRITE equ 1
SYS_EXIT  equ 60
STDERR    equ 2

;Token constants (must match symbol_table.asm from lexer)
TK_IS        equ 1
TK_WHERE     equ 2
TK_AND       equ 3
TK_OR        equ 4
TK_NOT       equ 5
TK_EVERY     equ 6
TK_IN        equ 7
TK_OF        equ 8
TK_LET       equ 9
TK_BE        equ 10
TK_FROM      equ 11
TK_TO        equ 12
TK_MIN       equ 13
TK_MAX       equ 14
TK_SUM       equ 15
TK_TRUE      equ 16
TK_FALSE     equ 17
TK_LIT_INT   equ 18
TK_LIT_FLOAT equ 19
TK_LIT_STR   equ 20
TK_ID        equ 21
TK_GREATER   equ 22
TK_LESS      equ 23
TK_GREATER_EQ equ 24
TK_LESS_EQ   equ 25
TK_EQUAL     equ 26
TK_NEQ       equ 27
TK_ASSIGN    equ 28
TK_PLUS      equ 29
TK_MINUS     equ 30
TK_STAR      equ 31
TK_SLASH     equ 32
TK_MOD       equ 33
TK_LPAREN    equ 34
TK_RPAREN    equ 35
TK_LBRACKET  equ 36
TK_RBRACKET  equ 37
TK_COMMA     equ 38
TK_DOT       equ 39
TK_NEWLINE   equ 40
TK_EOF       equ 41
TK_ERROR     equ 42

;Imports from lexer
extern get_token
extern lexeme
extern lexeme_len
extern tok_line                     ;B1: 1-based line of the current token (lexer.asm)

;Imports from strpool
extern intern_str

;Imports from ast
extern alloc_node

;Module state
section .bss
    cur_token   resq 1
    cur_lexeme  resq 1              ;pointer to interned string of current lexeme

section .data
    err_unexpected  db "parse error: unexpected token on line ", 0
    err_expected    db "parse error: expected token on line ", 0
    err_newline     db 10, 0
    str_syntax_ok   db "syntax OK", 10, 0

    ;keyword strings for context-sensitive checks
    kw_next     db "next", 0
    kw_path     db "path", 0
    kw_element  db "element", 0

section .text

global parse_program

;advance() — fetch next token, intern lexeme, update cur_token/cur_lexeme
;Internal use only, no arguments.
advance:
    push rbp
    mov  rbp, rsp
    push rbx

    call get_token                  ;rax = token type
    mov  [cur_token], rax

    ;intern the current lexeme string
    lea  rdi, [lexeme]
    call intern_str                 ;rax = pointer to interned copy
    mov  [cur_lexeme], rax

    pop  rbx
    pop  rbp
    ret

;expect(token_type) — verify cur_token matches type; call syntax_error if not.
;Does NOT call advance. Caller is responsible for advancing before and after.
;rdi = expected token type constant
expect:
    push rbp
    mov  rbp, rsp
    push rbx

    mov  rbx, rdi
    mov  rax, [cur_token]
    cmp  rax, rbx
    jne  .mismatch

    pop  rbx
    pop  rbp
    ret

.mismatch:
    mov  rdi, rbx
    call syntax_error               ;does not return
    pop  rbx
    pop  rbp
    ret

;syntax_error(expected_type) — print error and exit
;rdi = expected token type (informational, not printed by name here)
syntax_error:
    ;print "parse error: unexpected token on line "
    mov  rdi, STDERR
    lea  rsi, [err_unexpected]
    mov  rdx, 38
    mov  rax, SYS_WRITE
    syscall

    ;print line number (decimal)
    mov  rdi, [tok_line]
    call print_uint

    ;print newline
    mov  rdi, STDERR
    lea  rsi, [err_newline]
    mov  rdx, 1
    mov  rax, SYS_WRITE
    syscall

    mov  rax, SYS_EXIT
    mov  rdi, 1
    syscall

;print_uint(n) — print decimal integer to stderr
;rdi = unsigned 64-bit integer
print_uint:
    push rbp
    mov  rbp, rsp
    sub  rsp, 24                    ;local digit buffer

    mov  rax, rdi
    lea  r8, [rsp]
    add  r8, 20                     ;point past buffer
    mov  byte [r8], 10              ;newline sentinel (not printed)
    dec  r8
    mov  rcx, 0                     ;digit count

.digit_loop:
    xor  rdx, rdx
    mov  rbx, 10
    div  rbx                        ;rdx = rax % 10, rax = rax / 10
    add  dl, '0'
    mov  [r8], dl
    dec  r8
    inc  rcx
    test rax, rax
    jnz  .digit_loop

    inc  r8                         ;r8 now points to first digit
    mov  rdi, STDERR
    mov  rsi, r8
    mov  rdx, rcx
    mov  rax, SYS_WRITE
    syscall

    add  rsp, 24
    pop  rbp
    ret

;str_eq(a, b) -> CF=1 if equal, CF=0 if not
;rdi = pointer to string a
;rsi = pointer to string b
str_eq:
    push rcx
    push rdi
    push rsi
    xor  rcx, rcx
.loop:
    mov  al, [rdi + rcx]
    mov  bl, [rsi + rcx]
    cmp  al, bl
    jne  .no
    test al, al
    je   .yes
    inc  rcx
    jmp  .loop
.yes:
    pop  rsi
    pop  rdi
    pop  rcx
    stc
    ret
.no:
    pop  rsi
    pop  rdi
    pop  rcx
    clc
    ret

;Grammar procedures

;parse_program() -> rax = root node pointer
;program ::= statement* TK_EOF
parse_program:
    push rbp
    mov  rbp, rsp
    push r12
    push r13
    push r14

    ;Load the first token
    call advance

    ;Allocate the root node
    mov  rdi, NODE_PROGRAM
    mov  rsi, 1
    call alloc_node
    mov  r12, rax                   ;r12 = program root node

    xor  r13, r13                   ;r13 = puntero al último NODE_STMT_LIST

.stmt_loop:
    mov  rax, [cur_token]

    ;1. Blank-line filter: newline tokens are consumed here, centrally,
    ;and the loop re-evaluates.
    cmp  rax, TK_NEWLINE
    je   .skip_newline

    ;2. End of file: finish cleanly
    cmp  rax, TK_EOF
    je   .done

    ;3. Neither blank nor EOF: must be a real statement (ID or LET).
    call parse_statement            ;rax = parsed statement node
    mov  r14, rax

    ;Envolver el resultado en un NODE_STMT_LIST
    mov  rdi, NODE_STMT_LIST
    mov  rsi, [tok_line]
    call alloc_node
    mov  qword [rax + NODE_LEFT], r14   ;Miembro izquierdo = la sentencia

    ;Link into the program's statement list
    test r13, r13
    jz   .first_stmt

    mov  qword [r13 + NODE_RIGHT], rax  ;append to the end of the chain
    mov  r13, rax
    jmp  .stmt_loop

.first_stmt:
    mov  qword [r12 + NODE_LEFT], rax   ;first link of the program
    mov  r13, rax
    jmp  .stmt_loop

.skip_newline:
    call advance                    ;consume the blank newline safely
    jmp  .stmt_loop                 ;re-evaluate the next token

.done:
    mov  rax, r12                   ;return the complete AST root

    pop  r14
    pop  r13
    pop  r12
    pop  rbp
    ret

;parse_statement() -> rax = stmt node
parse_statement:
    push rbp
    mov  rbp, rsp
    push r12

    mov  rax, [cur_token]

    cmp  rax, TK_LET
    je   near .do_let

    cmp  rax, TK_ID
    je   near .do_assign

    mov  rdi, TK_ID
    call syntax_error

.do_let:
    call parse_let_binding
    mov  r12, rax
    jmp  near .expect_nl

.do_assign:
    call parse_assignment
    mov  r12, rax

.expect_nl:
    mov  rax, [cur_token]
    cmp  rax, TK_NEWLINE
    je   near .consume_nl
    cmp  rax, TK_EOF
    je   near .done

    mov  rdi, TK_NEWLINE
    call syntax_error

.consume_nl:
    call advance

.done:
    mov  rax, r12
    pop  r12
    pop  rbp
    ret

;parse_assignment() -> rax = NODE_ASSIGN
;assignment ::= TK_ID TK_IS expr
parse_assignment:
    push rbp
    mov  rbp, rsp
    push r12
    push r13

    ;REGLA DE ORO: cur_token YA ES TK_ID (verificado por el llamador).
    ;advance is not called on entry; the ID is processed immediately.
    mov  rdi, NODE_ID
    mov  rsi, [tok_line]
    call alloc_node
    mov  r12, rax                    ;r12 = id node

    mov  rax, [cur_lexeme]
    mov  qword [r12 + NODE_VALUE], rax  ;save the lexeme before advance clobbers it

    ;1. Advance explicitly toward what must be TK_IS
    call advance
    mov  rdi, TK_IS
    call expect                     ;Verifica si cur_token == TK_IS (no avanza)

    call advance
    call parse_expr                 ;parse the expression
    mov  r13, rax                   ;r13 = expr node

    ;Return contract: parse_expr leaves cur_token on the first
    ;token past the expression (normally TK_NEWLINE)

    mov  rdi, NODE_ASSIGN
    mov  rsi, [tok_line]
    call alloc_node
    mov  qword [rax + NODE_LEFT],  r12
    mov  qword [rax + NODE_RIGHT], r13

    pop  r13
    pop  r12
    pop  rbp
    ret

;parse_let_binding() -> rax = NODE_LET
;let_binding ::= TK_LET TK_ID TK_BE expr
parse_let_binding:
    push rbp
    mov  rbp, rsp
    push r12
    push r13

    ;cur_token is TK_LET
    call advance                    ;consume LET, move to TK_ID

    mov  rax, [cur_token]
    cmp  rax, TK_ID
    je   .got_id
    mov  rdi, TK_ID
    call syntax_error

.got_id:
    ;allocate ID node
    mov  rdi, NODE_ID
    mov  rsi, [tok_line]
    call alloc_node
    mov  r12, rax

    mov  rax, [cur_lexeme]
    mov  qword [r12 + NODE_VALUE], rax  ;save before advance overwrites cur_lexeme

    ;advance to BE, verify, then advance to expr
    call advance
    mov  rdi, TK_BE
    call expect
    call advance
    call parse_expr
    mov  r13, rax

    ;build NODE_LET
    mov  rdi, NODE_LET
    mov  rsi, [tok_line]
    call alloc_node
    mov  qword [rax + NODE_LEFT],  r12
    mov  qword [rax + NODE_RIGHT], r13

    pop  r13
    pop  r12
    pop  rbp
    ret

;parse_expr() -> rax = resulting AST node
;expr ::= aggregate_expr | range_expr | arith_expr (con WHERE opcional)
parse_expr:
    push rbp
    mov  rbp, rsp
    push r12
    push r13

    mov  rax, [cur_token]

    ;1. Aggregation expression?
    cmp  rax, TK_SUM
    je   near .do_aggregate
    cmp  rax, TK_MIN
    je   near .do_aggregate
    cmp  rax, TK_MAX
    je   near .do_aggregate

    ;2. ¿Es path from ... to ...?
    cmp  rax, TK_ID
    jne  near .do_arith
    mov  rdi, [cur_lexeme]
    lea  rsi, [kw_path]
    call str_eq
    jc   near .do_range

    jmp  near .do_arith

.do_aggregate:
    call parse_aggregate_expr
    jmp  near .exit

.do_range:
    call parse_range_expr
    jmp  near .exit

.do_arith:
    call parse_arith_expr
    mov  r12, rax                   ;r12 = base arith node

    ;strict WHERE absorption
    mov  rax, [cur_token]
    cmp  rax, TK_WHERE
    jne  near .no_filter

    call parse_filter_clause        ;rax = condition node
    mov  r13, rax                   ;r13 = condition

    mov  rdi, NODE_FILTER
    mov  rsi, [tok_line]
    call alloc_node
    mov  qword [rax + NODE_LEFT],  r12
    mov  qword [rax + NODE_RIGHT], r13
    jmp  near .exit

.no_filter:
    mov  rax, r12

.exit:
    pop  r13
    pop  r12
    pop  rbp
    ret

;parse_aggregate_expr() -> rax = NODE_AGGR
;aggregate_expr ::= agg_op TK_OF TK_ID filter_clause?
parse_aggregate_expr:
    push rbp
    mov  rbp, rsp
    push r12                    ;r12 = guardar token op original (SUM/MIN/MAX)
    push r13                    ;r13 = collection identifier node
    push r14                    ;r14 = filter node (if any)

    ;cur_token ya es agg_op (TK_SUM, TK_MIN o TK_MAX) verificado por expr
    mov  rax, [cur_token]
    mov  r12, rax               ;save the aggregation operator token
    call advance                ;Consumimos agg_op

    ;Forzar TK_OF
    mov  rdi, TK_OF
    call expect
    call advance                ;Consumimos TK_OF

    ;require TK_ID (collection name — may be dotted: orders.amount)
    call parse_access_expr          ;handles TK_ID and TK_ID.TK_ID chains
    mov  r13, rax                   ;r13 = access node

    ;REGRESO LL(1): cur_token ahora apunta al lookahead (puede ser TK_WHERE o TK_NEWLINE)
    xor  r14, r14               ;Por defecto, no hay filtro (r14 = 0)

    mov  rax, [cur_token]
    cmp  rax, TK_WHERE
    jne  .build_node            ;no WHERE: build the node directly

    ;WHERE present: parse the full filter clause
    ;note: filter_clause ::= TK_WHERE condition, so control passes straight through
    call parse_filter_clause    ;consumes the WHERE itself and parses the condition
    mov  r14, rax               ;r14 = NODE_FILTER retornado

.build_node:
    ;build the main NODE_AGGR aggregate node
    mov  rdi, NODE_AGGR
    mov  rsi, [tok_line]
    call alloc_node
    mov  qword [rax + NODE_VALUE], r12  ;aggregation operator token
    mov  qword [rax + NODE_LEFT],  r13  ;left member = collection ID
    mov  qword [rax + NODE_RIGHT], r14  ;Miembro derecho = filtro o 0

    pop  r14
    pop  r13
    pop  r12
    pop  rbp
    ret

.err_id:
    mov  rdi, TK_ID
    call syntax_error

;parse_range_expr() -> rax = NODE_RANGE
;range_expr ::= 'path' TK_FROM TK_ID TK_TO TK_ID filter_clause?
;cur_token is TK_ID with lexeme "path"
parse_range_expr:
    push rbp
    mov  rbp, rsp
    push r12
    push r13

    ;consume 'path'
    call advance

    ;expect FROM
    mov  rax, [cur_token]
    cmp  rax, TK_FROM
    je   .got_from
    mov  rdi, TK_FROM
    call syntax_error

.got_from:
    ;expect TK_ID (from node)
    call advance
    mov  rax, [cur_token]
    cmp  rax, TK_ID
    je   .got_from_id
    mov  rdi, TK_ID
    call syntax_error

.got_from_id:
    mov  rdi, NODE_ID
    mov  rsi, [tok_line]
    call alloc_node
    mov  r12, rax
    mov  rbx, [cur_lexeme]
    mov  qword [r12 + NODE_VALUE], rbx

    ;advance to TO, verify
    call advance
    mov  rdi, TK_TO
    call expect

    ;advance to to-ID
    call advance
    mov  rax, [cur_token]
    cmp  rax, TK_ID
    je   .got_to_id
    mov  rdi, TK_ID
    call syntax_error

.got_to_id:
    mov  rdi, NODE_ID
    mov  rsi, [tok_line]
    call alloc_node
    mov  r13, rax
    mov  rbx, [cur_lexeme]
    mov  qword [r13 + NODE_VALUE], rbx

    call advance                    ;move past to-ID

    ;optional WHERE
    xor  rbx, rbx
    mov  rax, [cur_token]
    cmp  rax, TK_WHERE
    jne  .no_filter
    call parse_filter_clause
    mov  rbx, rax

.no_filter:
    mov  rdi, NODE_RANGE
    mov  rsi, [tok_line]
    call alloc_node
    mov  qword [rax + NODE_LEFT],  r12
    mov  qword [rax + NODE_RIGHT], r13
    mov  qword [rax + NODE_VALUE], rbx  ;filter clause or 0

    pop  r13
    pop  r12
    pop  rbp
    ret

;parse_filter_clause() -> rax = condition node
;filter_clause ::= TK_WHERE condition
parse_filter_clause:
    push rbp
    mov  rbp, rsp

    ;cur_token es TK_WHERE. Lo consumimos obligatoriamente.
    call advance

    ;parse the condition (handles ORs, ANDs and comparisons)
    call parse_condition

    pop  rbp
    ret

;parse_condition() -> rax
;condition ::= cond_term (TK_OR cond_term)*
parse_condition:
    push rbp
    mov  rbp, rsp
    push r12
    push r13

    call parse_cond_term
    mov  r12, rax                   ;r12 = left

.or_loop:
    mov  rax, [cur_token]
    cmp  rax, TK_OR
    jne  .done

    call advance                    ;consume OR
    call parse_cond_term
    mov  r13, rax                   ;r13 = right

    mov  rdi, NODE_COND_OR
    mov  rsi, [tok_line]
    call alloc_node
    mov  qword [rax + NODE_LEFT],  r12
    mov  qword [rax + NODE_RIGHT], r13
    mov  r12, rax
    jmp  .or_loop

.done:
    mov  rax, r12
    pop  r13
    pop  r12
    pop  rbp
    ret

;parse_cond_term() -> rax
;cond_term ::= cond_factor (TK_AND cond_factor)*
parse_cond_term:
    push rbp
    mov  rbp, rsp
    push r12
    push r13

    call parse_cond_factor
    mov  r12, rax

.and_loop:
    mov  rax, [cur_token]
    cmp  rax, TK_AND
    jne  .done

    call advance
    call parse_cond_factor
    mov  r13, rax

    mov  rdi, NODE_COND_AND
    mov  rsi, [tok_line]
    call alloc_node
    mov  qword [rax + NODE_LEFT],  r12
    mov  qword [rax + NODE_RIGHT], r13
    mov  r12, rax
    jmp  .and_loop

.done:
    mov  rax, r12
    pop  r13
    pop  r12
    pop  rbp
    ret

;parse_cond_factor() -> rax
;cond_factor ::= TK_NOT cond_factor
;| TK_EVERY 'element' TK_LESS_EQ 'next'
;| access_expr TK_IN list_literal
;| access_expr TK_IS agg_op
;| comparison
parse_cond_factor:
    push rbp
    mov  rbp, rsp
    push r12
    push r13

    mov  rax, [cur_token]

    cmp  rax, TK_NOT
    jne  .not_not
    call advance
    call parse_cond_factor
    mov  r12, rax
    mov  rdi, NODE_COND_NOT
    mov  rsi, [tok_line]
    call alloc_node
    mov  qword [rax + NODE_LEFT], r12
    jmp  .done

.not_not:
    cmp  rax, TK_EVERY
    jne  .not_every
    call advance                    ;Consume 'every'

    mov  rax, [cur_token]
    cmp  rax, TK_ID
    jne  .syntax_error
    call advance                    ;Consume 'element'

    mov  rax, [cur_token]
    cmp  rax, TK_LESS_EQ
    jne  .syntax_error
    call advance                    ;Consume '<='

    mov  rax, [cur_token]
    cmp  rax, TK_ID
    jne  .syntax_error
    call advance                    ;consume 'next' (critical LL(1) compensation)

    mov  rdi, NODE_COND_EVERY
    mov  rsi, [tok_line]
    call alloc_node
    jmp  .done

.not_every:
    call parse_arith_expr
    mov  r12, rax                   ;r12 = LHS (arith_expr, covers access_expr as degenerate case)

    mov  rax, [cur_token]
    cmp  rax, TK_IN
    jne  .not_in
    call advance                    ;Consume 'in'
    call parse_list_literal
    mov  r13, rax                   ;r13 = list_literal node

    mov  rdi, NODE_IN_TEST
    mov  rsi, [tok_line]
    call alloc_node
    mov  qword [rax + NODE_LEFT],  r12
    mov  qword [rax + NODE_RIGHT], r13
    jmp  .done

.not_in:
    cmp  rax, TK_IS
    jne  .not_is_extreme
    call advance                    ;Consume 'is'

    mov  rax, [cur_token]
    cmp  rax, TK_MIN
    je   .is_extreme
    cmp  rax, TK_MAX
    je   .is_extreme

    mov  rdi, TK_MIN
    call syntax_error

.is_extreme:
    mov  r13, rax                   ;r13 = MIN/MAX token
    call advance                    ;Consume el extremo

    mov  rdi, NODE_IS_EXTREME
    mov  rsi, [tok_line]
    call alloc_node
    mov  qword [rax + NODE_LEFT],  r12
    mov  qword [rax + NODE_VALUE], r13
    jmp  .done

.not_is_extreme:
    mov  rdi, r12                   ;rdi = LHS handed to the comparison
    call parse_comparison_with_lhs
    jmp  .done

.syntax_error:
    mov  rdi, TK_ID
    call syntax_error

.done:
    pop  r13
    pop  r12
    pop  rbp
    ret

;parse_comparison_with_lhs(lhs) -> rax = NODE_CMP
;rdi = already-parsed lhs node pointer
;comparison ::= access_expr relop access_expr
parse_comparison_with_lhs:
    push rbp
    mov  rbp, rsp
    push r12
    push r13
    push r14

    mov  r12, rdi                   ;r12 = left-hand side node (LHS)

    ;Validar y guardar el operador relacional (relop)
    mov  rax, [cur_token]
    cmp  rax, TK_EQUAL
    je   .got_op
    cmp  rax, TK_NEQ
    je   .got_op
    cmp  rax, TK_LESS
    je   .got_op
    cmp  rax, TK_GREATER
    je   .got_op
    cmp  rax, TK_LESS_EQ
    je   .got_op
    cmp  rax, TK_GREATER_EQ
    je   .got_op

    mov  rdi, TK_EQUAL
    call syntax_error

.got_op:
    mov  r13, rax                   ;r13 = relational operator token
    call advance                    ;Consumimos el operador relacional

    ;Parse the right-hand side (RHS).
    ;parse_factor: the RHS may be an ID or a literal (e.g. 18 or "food")
    call parse_factor
    mov  r14, rax                   ;r14 = right-hand side node (RHS)

    ;Lookahead already compensated: parse_factor calls advance after reading
    ;the literal/ID, so cur_token already points at the following control
    ;token (TK_NEWLINE, TK_AND or TK_OR). Do NOT advance here.

    ;build the NODE_CMP comparison node
    mov  rdi, NODE_CMP
    mov  rsi, [tok_line]
    call alloc_node
    mov  qword [rax + NODE_LEFT],  r12  ;Miembro izquierdo (LHS)
    mov  qword [rax + NODE_RIGHT], r14  ;Miembro derecho (RHS)
    mov  qword [rax + NODE_VALUE], r13  ;operator token

    pop  r14
    pop  r13
    pop  r12
    pop  rbp
    ret

;parse_access_expr() -> rax = NODE_ACCESS or NODE_ID
;access_expr ::= TK_ID (TK_DOT TK_ID)*
parse_access_expr:
    push rbp
    mov  rbp, rsp
    push r12
    push r13

    mov  rax, [cur_token]
    cmp  rax, TK_ID
    jne  .err_not_id

    mov  rdi, NODE_ID
    mov  rsi, [tok_line]
    call alloc_node
    mov  r12, rax
    mov  rbx, [cur_lexeme]
    mov  qword [r12 + NODE_VALUE], rbx

    call advance

    mov  rax, [cur_token]
    cmp  rax, TK_DOT
    jne  .no_dots

    mov  rdi, NODE_ACCESS
    mov  rsi, [tok_line]
    call alloc_node
    mov  r13, rax
    mov  qword [r13 + NODE_LEFT], r12
    mov  rbx, r13

.dot_loop:
    mov  rax, [cur_token]
    cmp  rax, TK_DOT
    jne  .dot_done

    call advance                    ;Consume el punto '.'

    mov  rax, [cur_token]
    cmp  rax, TK_ID
    jne  .err_not_id

    mov  rdi, NODE_ID
    mov  rsi, [tok_line]
    call alloc_node
    mov  r12, rax
    mov  rcx, [cur_lexeme]
    mov  qword [r12 + NODE_VALUE], rcx

    mov  qword [rbx + NODE_RIGHT], r12
    mov  rbx, r12

    call advance                    ;Consume el ID secundario
    jmp  .dot_loop

.dot_done:
    mov  rax, r13
    jmp  .done

.no_dots:
    mov  rax, r12

.done:
    pop  r13
    pop  r12
    pop  rbp
    ret

.err_not_id:
    mov  rdi, TK_ID
    call syntax_error

;parse_list_literal() -> rax = first NODE_LIST of the chain
;list_literal ::= TK_LBRACKET list_items TK_RBRACKET
;list_items   ::= literal (TK_COMMA literal)*
parse_list_literal:
    push rbp
    mov  rbp, rsp
    push r12
    push r13
    push r14

    call advance                    ;Consume '['

    call parse_factor
    mov  rbx, rax

    mov  rdi, NODE_LIST
    mov  rsi, [tok_line]
    call alloc_node
    mov  r13, rax               ;Head
    mov  r12, rax               ;Tail
    mov  qword [r13 + NODE_LEFT],  rbx
    mov  qword [r13 + NODE_RIGHT], 0

.loop_elements:
    mov  rax, [cur_token]

    cmp  rax, TK_COMMA
    je   .process_comma

    cmp  rax, TK_RBRACKET
    je   .process_close

    mov  rdi, TK_RBRACKET
    call syntax_error

.process_comma:
    call advance                ;Consume ','
    call parse_factor
    mov  rbx, rax

    mov  rdi, NODE_LIST
    mov  rsi, [tok_line]
    call alloc_node
    mov  r14, rax
    mov  qword [r14 + NODE_LEFT],  rbx
    mov  qword [r14 + NODE_RIGHT], 0

    mov  qword [r12 + NODE_RIGHT], r14
    mov  r12, r14
    jmp  .loop_elements

.process_close:
    call advance                ;Consume formalmente el corchete de cierre ']'
    mov  rax, r13

    pop  r14
    pop  r13
    pop  r12
    pop  rbp
    ret

;parse_arith_expr() -> rax
;arith_expr ::= term ((TK_PLUS | TK_MINUS) term)*
parse_arith_expr:
    push rbp
    mov  rbp, rsp
    push r12
    push r13

    call parse_term
    mov  r12, rax

.loop:
    mov  rax, [cur_token]
    cmp  rax, TK_PLUS
    je   .do_op
    cmp  rax, TK_MINUS
    je   .do_op
    jmp  .done

.do_op:
    mov  r13, rax
    call advance
    call parse_term
    mov  rbx, rax

    mov  rdi, NODE_BINOP
    mov  rsi, [tok_line]
    call alloc_node
    mov  qword [rax + NODE_LEFT],  r12
    mov  qword [rax + NODE_RIGHT], rbx
    mov  qword [rax + NODE_VALUE], r13
    mov  r12, rax
    jmp  .loop

.done:
    mov  rax, r12
    pop  r13
    pop  r12
    pop  rbp
    ret

;parse_term() -> rax
;term ::= factor ((TK_STAR | TK_SLASH | TK_MOD) factor)*
parse_term:
    push rbp
    mov  rbp, rsp
    push r12
    push r13

    call parse_factor
    mov  r12, rax

.loop:
    mov  rax, [cur_token]
    cmp  rax, TK_STAR
    je   .do_op
    cmp  rax, TK_SLASH
    je   .do_op
    cmp  rax, TK_MOD
    je   .do_op
    jmp  .done

.do_op:
    mov  r13, rax
    call advance
    call parse_factor
    mov  rbx, rax

    mov  rdi, NODE_BINOP
    mov  rsi, [tok_line]
    call alloc_node
    mov  qword [rax + NODE_LEFT],  r12
    mov  qword [rax + NODE_RIGHT], rbx
    mov  qword [rax + NODE_VALUE], r13
    mov  r12, rax
    jmp  .loop

.done:
    mov  rax, r12
    pop  r13
    pop  r12
    pop  rbp
    ret

;parse_factor() -> rax
;factor ::= TK_LPAREN arith_expr TK_RPAREN
;| TK_MINUS factor
;| TK_LIT_INT | TK_LIT_FLOAT | TK_LIT_STR | TK_TRUE | TK_FALSE
;| access_expr
parse_factor:
    push rbp
    mov  rbp, rsp
    push r12

    mov  rax, [cur_token]

    ;parenthesized expression
    cmp  rax, TK_LPAREN
    jne  near .not_paren
    call advance
    call parse_expr
    mov  r12, rax
    ;expect RPAREN
    mov  rax, [cur_token]
    cmp  rax, TK_RPAREN
    je   near .close_paren
    mov  rdi, TK_RPAREN
    call syntax_error
.close_paren:
    call advance
    mov  rax, r12
    jmp  .done

.not_paren:
    ;unary minus
    cmp  rax, TK_MINUS
    jne  .not_unary
    call advance
    call parse_factor
    mov  r12, rax
    mov  rdi, NODE_UNOP
    mov  rsi, [tok_line]
    call alloc_node
    mov  qword [rax + NODE_LEFT], r12
    jmp  .done

.not_unary:
    ;integer literal
    cmp  rax, TK_LIT_INT
    jne  .not_int
    mov  rdi, NODE_LIT_INT
    mov  rsi, [tok_line]
    call alloc_node
    mov  r12, rax
    ;convert lexeme string to integer
    mov  rdi, [cur_lexeme]
    call parse_integer
    mov  qword [r12 + NODE_VALUE], rax
    call advance
    mov  rax, r12
    jmp  .done

.not_int:
    ;float literal
    cmp  rax, TK_LIT_FLOAT
    jne  .not_float
    mov  rdi, NODE_LIT_FLOAT
    mov  rsi, [tok_line]
    call alloc_node
    mov  r12, rax
    mov  rbx, [cur_lexeme]
    mov  qword [r12 + NODE_VALUE], rbx   ;store string pointer
    call advance
    mov  rax, r12
    jmp  .done

.not_float:
    ;string literal
    cmp  rax, TK_LIT_STR
    jne  .not_str
    mov  rdi, NODE_LIT_STR
    mov  rsi, [tok_line]
    call alloc_node
    mov  r12, rax
    mov  rbx, [cur_lexeme]
    mov  qword [r12 + NODE_VALUE], rbx
    call advance
    mov  rax, r12
    jmp  .done

.not_str:
    ;true
    cmp  rax, TK_TRUE
    jne  .not_true
    mov  rdi, NODE_LIT_BOOL
    mov  rsi, [tok_line]
    call alloc_node
    mov  qword [rax + NODE_VALUE], 1
    call advance
    jmp  .done

.not_true:
    ;false
    cmp  rax, TK_FALSE
    jne  .not_false
    mov  rdi, NODE_LIT_BOOL
    mov  rsi, [tok_line]
    call alloc_node
    mov  qword [rax + NODE_VALUE], 0
    call advance
    jmp  .done

.not_false:
    ;access_expr (ID or dotted path)
    call parse_access_expr

.done:
    pop  r12
    pop  rbp
    ret

;parse_integer(str) -> rax = integer value
;rdi = pointer to null-terminated decimal string
parse_integer:
    push rbx
    xor  rax, rax
.loop:
    movzx rbx, byte [rdi]
    test rbx, rbx
    jz   .done
    sub  rbx, '0'
    imul rax, rax, 10
    add  rax, rbx
    inc  rdi
    jmp  .loop
.done:
    pop  rbx
    ret
