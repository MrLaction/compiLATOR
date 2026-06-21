;astdump.asm — AST pretty-printer for the -v flag (%included by parser.asm)
;
;dump_ast walks the tree built by parse_program and writes an indented,
;human-readable form to stdout. It is the debugging instrument for the IR
;work: NODE_PROGRAM flattens its STMT_LIST chain so top-level statements
;print as siblings; every other node prints left then right one level
;deeper. Leaf payloads (identifiers, literals, operator tokens) print
;inline. No allocation; reads NODE_*/TK_* defined earlier in parser.asm.
;
;Exports: dump_ast.

global dump_ast

section .text

;dump_ast(rdi = node, rsi = depth) -> void
;Recursively prints the subtree rooted at node, indented by depth.
dump_ast:
    test rdi, rdi
    jz   .ret_now           ;null child: print nothing
    push rbp
    mov  rbp, rsp
    push rbx
    push r12
    push r13

    mov  rbx, rdi           ;rbx = node (preserved across recursion)
    mov  r12, rsi           ;r12 = depth

    ;indentation
    mov  rdi, r12
    call dump_indent

    ;node-type name
    mov  rax, [rbx + NODE_TYPE]
    lea  rcx, [nodename_table]
    mov  rdi, [rcx + rax*8]
    call dump_cstr

    ;inline payload, dispatched by type
    mov  rax, [rbx + NODE_TYPE]
    cmp  rax, NODE_ID
    je   .info_quoted
    cmp  rax, NODE_LIT_STR
    je   .info_quoted
    cmp  rax, NODE_LIT_FLOAT
    je   .info_barestr
    cmp  rax, NODE_LIT_INT
    je   .info_int
    cmp  rax, NODE_LIT_BOOL
    je   .info_bool
    cmp  rax, NODE_CMP
    je   .info_op
    cmp  rax, NODE_BINOP
    je   .info_op
    cmp  rax, NODE_IS_EXTREME
    je   .info_op
    cmp  rax, NODE_AGGR
    je   .info_op
    jmp  .info_done

.info_quoted:
    ;value = pointer to name/string; print  "<text>"
    lea  rdi, [str_sp_quote]
    call dump_cstr
    mov  rdi, [rbx + NODE_VALUE]
    call dump_cstr
    lea  rdi, [str_quote]
    call dump_cstr
    jmp  .info_done
.info_barestr:
    ;value = pointer to (float) string copy; print  <text>
    lea  rdi, [str_space]
    call dump_cstr
    mov  rdi, [rbx + NODE_VALUE]
    call dump_cstr
    jmp  .info_done
.info_int:
    lea  rdi, [str_space]
    call dump_cstr
    mov  rdi, [rbx + NODE_VALUE]
    call dump_uint
    jmp  .info_done
.info_bool:
    mov  rax, [rbx + NODE_VALUE]
    test rax, rax
    jz   .bool_false
    lea  rdi, [str_sp_true]
    call dump_cstr
    jmp  .info_done
.bool_false:
    lea  rdi, [str_sp_false]
    call dump_cstr
    jmp  .info_done
.info_op:
    ;value = a TK_* token; translate to its symbol if known
    mov  rax, [rbx + NODE_VALUE]
    cmp  rax, 33                    ;optok_table covers tokens 0..33
    ja   .info_done
    lea  rcx, [optok_table]
    mov  rdi, [rcx + rax*8]
    test rdi, rdi
    jz   .info_done                 ;unmapped token: omit
    lea  rax, [str_space]
    push rdi
    mov  rdi, rax
    call dump_cstr
    pop  rdi
    call dump_cstr

.info_done:
    call dump_nl

    ;children
    mov  rax, [rbx + NODE_TYPE]
    cmp  rax, NODE_PROGRAM
    je   .recurse_program

    ;generic: left then right, one level deeper
    mov  rdi, [rbx + NODE_LEFT]
    lea  rsi, [r12 + 1]
    call dump_ast
    mov  rdi, [rbx + NODE_RIGHT]
    lea  rsi, [r12 + 1]
    call dump_ast
    jmp  .done

.recurse_program:
    ;flatten the STMT_LIST chain: each statement is a sibling at depth+1
    mov  r13, [rbx + NODE_LEFT]     ;first STMT_LIST
.prog_loop:
    test r13, r13
    jz   .done
    mov  rdi, [r13 + NODE_LEFT]     ;the statement node
    lea  rsi, [r12 + 1]
    call dump_ast
    mov  r13, [r13 + NODE_RIGHT]    ;next STMT_LIST
    jmp  .prog_loop

.done:
    pop  r13
    pop  r12
    pop  rbx
    pop  rbp
.ret_now:
    ret

;dump_cstr(rdi = ptr) — write a NUL-terminated string to stdout
dump_cstr:
    push rbx
    mov  rbx, rdi
    xor  rdx, rdx
.len:
    cmp  byte [rbx + rdx], 0
    je   .write
    inc  rdx
    jmp  .len
.write:
    test rdx, rdx
    jz   .skip
    mov  rax, 1             ;SYS_WRITE
    mov  rdi, 1             ;STDOUT
    mov  rsi, rbx
    syscall                ;rdx already = length
.skip:
    pop  rbx
    ret

;dump_uint(rdi = value) — write an unsigned decimal to stdout (no newline)
dump_uint:
    push rbp
    mov  rbp, rsp
    sub  rsp, 32
    mov  rax, rdi
    lea  r8, [rsp + 24]    ;one past buffer end
    mov  r9, 10
    xor  rcx, rcx          ;digit count
.digit:
    xor  rdx, rdx
    div  r9                ;rax /= 10, rdx = remainder
    add  dl, '0'
    dec  r8
    mov  [r8], dl
    inc  rcx
    test rax, rax
    jnz  .digit
    mov  rax, 1            ;SYS_WRITE
    mov  rdi, 1            ;STDOUT
    mov  rsi, r8
    mov  rdx, rcx
    syscall
    add  rsp, 32
    pop  rbp
    ret

;dump_indent(rdi = depth) — write depth*2 spaces
dump_indent:
    test rdi, rdi
    jz   .done
    mov  rcx, rdi
.loop:
    push rcx
    lea  rdi, [str_indent]
    call dump_cstr
    pop  rcx
    dec  rcx
    jnz  .loop
.done:
    ret

;dump_nl — write a newline
dump_nl:
    lea  rdi, [str_nl]
    call dump_cstr
    ret

section .data
    str_indent   db "  ", 0
    str_nl       db 10, 0
    str_space    db " ", 0
    str_quote    db '"', 0
    str_sp_quote db ' "', 0
    str_sp_true  db " true", 0
    str_sp_false db " false", 0

    nn_program    db "PROGRAM", 0
    nn_assign     db "ASSIGN", 0
    nn_let        db "LET", 0
    nn_filter     db "FILTER", 0
    nn_or         db "OR", 0
    nn_and        db "AND", 0
    nn_not        db "NOT", 0
    nn_every      db "EVERY_SORTED", 0
    nn_cmp        db "CMP", 0
    nn_in         db "IN", 0
    nn_isextreme  db "IS_EXTREME", 0
    nn_binop      db "BINOP", 0
    nn_neg        db "NEG", 0
    nn_aggr       db "AGGR", 0
    nn_path       db "PATH", 0
    nn_list       db "LIST", 0
    nn_access     db "ACCESS", 0
    nn_id         db "ID", 0
    nn_int        db "INT", 0
    nn_float      db "FLOAT", 0
    nn_str        db "STR", 0
    nn_bool       db "BOOL", 0
    nn_stmtlist   db "STMT_LIST", 0
    nn_unknown    db "UNKNOWN", 0

    op_min   db "min", 0
    op_max   db "max", 0
    op_sum   db "sum", 0
    op_gt    db ">", 0
    op_lt    db "<", 0
    op_ge    db ">=", 0
    op_le    db "<=", 0
    op_eq    db "==", 0
    op_ne    db "!=", 0
    op_plus  db "+", 0
    op_minus db "-", 0
    op_star  db "*", 0
    op_slash db "/", 0
    op_mod   db "%", 0

    ;indexed by NODE_* (1..23); slot 0 and out-of-range map to UNKNOWN
    nodename_table:
        dq nn_unknown                       ;0
        dq nn_program, nn_assign, nn_let, nn_filter      ;1-4
        dq nn_or, nn_and, nn_not, nn_every               ;5-8
        dq nn_cmp, nn_in, nn_isextreme, nn_binop         ;9-12
        dq nn_neg, nn_aggr, nn_path, nn_list             ;13-16
        dq nn_access, nn_id, nn_int, nn_float            ;17-20
        dq nn_str, nn_bool, nn_stmtlist                  ;21-23

    ;indexed by TK_* token (0..33); 0 = no symbol for this token
    optok_table:
        dq 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0         ;0-12
        dq op_min, op_max, op_sum                        ;13-15 (MIN,MAX,SUM)
        dq 0, 0, 0, 0, 0, 0                              ;16-21
        dq op_gt, op_lt, op_ge, op_le, op_eq, op_ne      ;22-27 (relops)
        dq 0                                             ;28 (ASSIGN)
        dq op_plus, op_minus, op_star, op_slash, op_mod  ;29-33 (arith)
