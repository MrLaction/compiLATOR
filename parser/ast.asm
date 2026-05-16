; ast.asm
; Arena allocator for AST nodes.
; Node layout: 40 bytes fixed.
;
;   [+0]  type    dq  (node type constant)
;   [+8]  left    dq  (pointer to left child / primary operand)
;   [+16] right   dq  (pointer to right child / secondary operand)
;   [+24] value   dq  (literal value or token ID — context-dependent)
;   [+32] line    dq  (source line number for error reporting)
;
; All pointer fields are 0 when unused.

; ---------------------------------------------------------------------------
; Node type constants
; ---------------------------------------------------------------------------
NODE_PROGRAM    equ 1   ; root: left=first stmt, right=next stmt (linked list)
NODE_ASSIGN     equ 2   ; result IS expr  — left=NODE_ID(name), right=expr
NODE_LET        equ 3   ; LET id BE expr  — left=NODE_ID(name), right=expr
NODE_FILTER     equ 4   ; id WHERE cond   — left=NODE_ID(src),  right=condition
NODE_COND_OR    equ 5   ; OR  — left, right = operands
NODE_COND_AND   equ 6   ; AND — left, right = operands
NODE_COND_NOT   equ 7   ; NOT — left = operand
NODE_COND_EVERY equ 8   ; every element <= next — no children
NODE_CMP        equ 9   ; comparison — left=lhs, right=rhs, value=relop token
NODE_IN_TEST    equ 10  ; id IN list    — left=access_expr, right=list
NODE_IS_EXTREME equ 11  ; id IS min/max — left=access_expr, value=TK_MIN/TK_MAX
NODE_BINOP      equ 12  ; arith binop   — left, right = operands, value=op token
NODE_UNOP       equ 13  ; unary minus   — left = operand
NODE_AGGR       equ 14  ; agg_op OF id WHERE? — value=agg token, left=src, right=filter_clause (or 0)
NODE_RANGE      equ 15  ; PATH FROM a TO b WHERE? — left=from_id, right=to_id, value=filter_clause ptr
NODE_LIST       equ 16  ; list literal  — left=first item, right=next item (linked list)
NODE_ACCESS     equ 17  ; dotted access — left=first segment, right=next (linked list)
NODE_ID         equ 18  ; identifier    — value=pointer to null-terminated name in lexeme copy
NODE_LIT_INT    equ 19  ; int literal   — value=integer value (as qword)
NODE_LIT_FLOAT  equ 20  ; float literal — value=pointer to string copy (parse at codegen)
NODE_LIT_STR    equ 21  ; string literal — value=pointer to string copy
NODE_LIT_BOOL   equ 22  ; bool literal  — value=1 (true) or 0 (false)
NODE_STMT_LIST  equ 23  ; statement linked list — left=stmt, right=next NODE_STMT_LIST or 0

; ---------------------------------------------------------------------------
; Node field offsets
; ---------------------------------------------------------------------------
NODE_TYPE   equ 0
NODE_LEFT   equ 8
NODE_RIGHT  equ 16
NODE_VALUE  equ 24
NODE_LINE   equ 32
NODE_SIZE   equ 40

; ---------------------------------------------------------------------------
; Arena constants
; ---------------------------------------------------------------------------
AST_POOL_CAP equ 2048   ; maximum nodes

section .bss
    ast_pool    resb AST_POOL_CAP * NODE_SIZE
    ast_count   resq 1              ; next free node index (0-based)

section .text

global alloc_node
global ast_pool
global ast_count

; ---------------------------------------------------------------------------
; alloc_node(type, line) -> rax = pointer to zeroed node
;   rdi = node type constant
;   rsi = source line number
; Aborts with exit code 99 if pool is exhausted.
; ---------------------------------------------------------------------------
alloc_node:
    push rbp
    mov  rbp, rsp
    push rbx
    push r12

    mov  rbx, rdi                   ; save type
    mov  r12, rsi                   ; save line

    mov  rax, [ast_count]
    cmp  rax, AST_POOL_CAP
    jge  .pool_full

    ; compute pointer: ast_pool + rax * NODE_SIZE
    imul rax, rax, NODE_SIZE
    lea  rcx, [ast_pool]
    add  rax, rcx                   ; rax = node pointer

    ; zero the 40 bytes
    mov  qword [rax + NODE_TYPE],  0
    mov  qword [rax + NODE_LEFT],  0
    mov  qword [rax + NODE_RIGHT], 0
    mov  qword [rax + NODE_VALUE], 0
    mov  qword [rax + NODE_LINE],  0

    ; set type and line
    mov  qword [rax + NODE_TYPE], rbx
    mov  qword [rax + NODE_LINE], r12

    ; advance counter
    mov  rcx, [ast_count]
    inc  rcx
    mov  [ast_count], rcx

    pop  r12
    pop  rbx
    pop  rbp
    ret

.pool_full:
    ; fatal: AST pool exhausted
    mov  rax, 60                    ; SYS_EXIT
    mov  rdi, 99
    syscall
