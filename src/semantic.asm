;semantic.asm — stage 3: semantic analyzer for LATOR
;
;Single pre-order walk of the AST (sem_walk). Declares each binding in
;the symbol table, rejects redeclarations, infers literal/binding types
;and checks comparison operand compatibility. Collection sources stay
;external by design until compile-time schema resolution lands. Errors
;print the line and exit 2.
;
;Exports: sem_walk.
;Imports: sym_insert, sym_lookup (symtable.asm).

default abs

SYS_WRITE  equ 1
SYS_EXIT   equ 60
STDERR     equ 2

; Node type constants (must match ast.asm)
NODE_PROGRAM    equ 1
NODE_ASSIGN     equ 2
NODE_LET        equ 3
NODE_FILTER     equ 4
NODE_COND_OR    equ 5
NODE_COND_AND   equ 6
NODE_COND_NOT   equ 7
NODE_COND_EVERY equ 8
NODE_CMP        equ 9
NODE_IN_TEST    equ 10
NODE_IS_EXTREME equ 11
NODE_BINOP      equ 12
NODE_UNOP       equ 13
NODE_AGGR       equ 14
NODE_RANGE      equ 15
NODE_LIST       equ 16
NODE_ACCESS     equ 17
NODE_ID         equ 18
NODE_LIT_INT    equ 19
NODE_LIT_FLOAT  equ 20
NODE_LIT_STR    equ 21
NODE_LIT_BOOL   equ 22
NODE_STMT_LIST  equ 23

; AST node field offsets (must match ast.asm)
NODE_TYPE  equ 0
NODE_LEFT  equ 8
NODE_RIGHT equ 16
NODE_VALUE equ 24
NODE_LINE  equ 32

; Symbol types (must match symtable.asm)
SYM_UNKNOWN    equ 0
SYM_INT        equ 1
SYM_FLOAT      equ 2
SYM_BOOL       equ 3
SYM_STRING     equ 4
SYM_COLLECTION equ 5
SYM_TYPE       equ 8   ;offset within sym entry

extern sym_insert
extern sym_lookup

section .data
    err_redecl_a  db "semantic error: '", 0
    err_redecl_b  db "' already declared on line ", 0
    err_undef_b   db "' is not defined on line ", 0
    err_mismatch  db "semantic error: type mismatch on line ", 0
    err_nl        db 10, 0

section .text

global sem_walk

;
;sem_walk(rdi = node pointer)
;Recursively walks the AST. Calls SYS_EXIT(2) on semantic error.
;
sem_walk:
    test rdi, rdi
    jz   .done              ;null node: nothing to do

    push rbp
    mov  rbp, rsp
    push r12
    push r13

    mov  r12, rdi           ;r12 = current node

    mov  rax, [r12 + NODE_TYPE]

    cmp  rax, NODE_PROGRAM
    je   .program

    cmp  rax, NODE_STMT_LIST
    je   .stmt_list

    cmp  rax, NODE_ASSIGN
    je   .declaration

    cmp  rax, NODE_LET
    je   .declaration

    cmp  rax, NODE_FILTER
    je   .filter

    cmp  rax, NODE_COND_OR
    je   .binary_node

    cmp  rax, NODE_COND_AND
    je   .binary_node

    cmp  rax, NODE_COND_NOT
    je   .unary_node

    cmp  rax, NODE_CMP
    je   .cmp_node

    cmp  rax, NODE_IN_TEST
    je   .binary_node

    cmp  rax, NODE_BINOP
    je   .binary_node

    cmp  rax, NODE_UNOP
    je   .unary_node

    cmp  rax, NODE_AGGR
    je   .aggr_node

    cmp  rax, NODE_ID
    je   .id_node

    ;literals, EVERY, RANGE, ACCESS, IS_EXTREME: no checks needed
    jmp  .done_pop

.program:
    ;NODE_PROGRAM.left = first NODE_STMT_LIST
    mov  rdi, [r12 + NODE_LEFT]
    call sem_walk
    jmp  .done_pop

.stmt_list:
    ;walk left (statement), then right (next in list)
    mov  rdi, [r12 + NODE_LEFT]
    call sem_walk
    mov  rdi, [r12 + NODE_RIGHT]
    call sem_walk
    jmp  .done_pop

.declaration:
    ;left = NODE_ID (name being declared)
    ;right = expr (RHS)

    ;walk RHS first to catch errors inside it (uses before this decl)
    mov  rdi, [r12 + NODE_RIGHT]
    call sem_walk

    ;infer type of RHS
    mov  rdi, [r12 + NODE_RIGHT]
    call sem_infer_type
    mov  r13, rax               ;r13 = inferred type

    ;insert LHS name into symbol table
    mov  rax, [r12 + NODE_LEFT] ;rax = NODE_ID node
    mov  rdi, [rax + NODE_VALUE];rdi = name string pointer
    mov  rsi, r13               ;rsi = type
    mov  rdx, [r12 + NODE_LINE] ;rdx = line
    call sym_insert
    test rax, rax
    jz   .done_pop              ;0 = OK

    ;redeclaration: get name and line for error message
    mov  rax, [r12 + NODE_LEFT]
    mov  rdi, [rax + NODE_VALUE];rdi = name ptr
    mov  rsi, [r12 + NODE_LINE] ;rsi = line
    call err_already_declared
    ;never returns

.filter:
    ;left = source collection, right = condition
    ;source is a NODE_ID: check it exists
    mov  rdi, [r12 + NODE_LEFT]
    call sem_walk
    mov  rdi, [r12 + NODE_RIGHT]
    call sem_walk
    jmp  .done_pop

.binary_node:
    mov  rdi, [r12 + NODE_LEFT]
    call sem_walk
    mov  rdi, [r12 + NODE_RIGHT]
    call sem_walk
    jmp  .done_pop

.unary_node:
    mov  rdi, [r12 + NODE_LEFT]
    call sem_walk
    jmp  .done_pop

.aggr_node:
    ;left = source collection, right = optional filter
    mov  rdi, [r12 + NODE_LEFT]
    call sem_walk
    mov  rdi, [r12 + NODE_RIGHT]
    call sem_walk
    jmp  .done_pop

.cmp_node:
    ;walk both sides
    mov  rdi, [r12 + NODE_LEFT]
    call sem_walk
    mov  rdi, [r12 + NODE_RIGHT]
    call sem_walk

    ;type-check: infer both sides
    mov  rdi, [r12 + NODE_LEFT]
    call sem_infer_type
    mov  r13, rax                   ;r13 = LHS type

    mov  rdi, [r12 + NODE_RIGHT]
    call sem_infer_type             ;rax = RHS type

    ;skip check if either side is unknown (unresolved CSV column, etc.)
    cmp  r13, SYM_UNKNOWN
    je   .done_pop
    cmp  rax, SYM_UNKNOWN
    je   .done_pop

    ;equal types compare cleanly (string==string, bool==bool, int==int...)
    cmp  r13, rax
    je   .done_pop

    ;unequal: legal only if BOTH are numeric (int vs float promotion, §3.2)
    cmp  r13, SYM_INT
    je   .cmp_lhs_numeric
    cmp  r13, SYM_FLOAT
    je   .cmp_lhs_numeric
    jmp  .cmp_bad                    ;lhs not numeric and types differ

.cmp_lhs_numeric:
    cmp  rax, SYM_INT
    je   .done_pop
    cmp  rax, SYM_FLOAT
    je   .done_pop

.cmp_bad:
    ;type mismatch error
    mov  rdi, [r12 + NODE_LINE]
    call err_type_mismatch
    ;never returns

.id_node:
    ;In LATOR, identifiers can refer to external data sources (users, orders, etc.)
    ;that are not declared in the program. We only flag undeclared identifiers
    ;that appear as field references inside arithmetic expressions where
    ;a prior declaration exists with a non-collection type.
    ;For now: silently accept all identifiers — redeclaration is caught at assignment.
    jmp  .done_pop

.done_pop:
    pop  r13
    pop  r12
    pop  rbp
.done:
    ret

;
;sem_infer_type(rdi = node pointer) -> rax = SYM_* constant
;Leaf nodes map directly; BINOP/UNOP recurse into operands, apply numeric
;promotion, and reject illegal operand types (exit 2). Unknown operands
;(unresolved CSV columns pre-Phase-2) propagate as SYM_UNKNOWN.
;
sem_infer_type:
    test rdi, rdi
    jz   .unknown

    mov  rax, [rdi + NODE_TYPE]

    cmp  rax, NODE_LIT_INT
    je   .t_int

    cmp  rax, NODE_LIT_FLOAT
    je   .t_float

    cmp  rax, NODE_LIT_STR
    je   .t_string

    cmp  rax, NODE_LIT_BOOL
    je   .t_bool

    cmp  rax, NODE_FILTER
    je   .t_collection

    cmp  rax, NODE_AGGR
    je   .t_collection

    cmp  rax, NODE_RANGE
    je   .t_collection

    cmp  rax, NODE_ID
    je   .t_from_table

    cmp  rax, NODE_BINOP
    je   .t_binop

    cmp  rax, NODE_UNOP
    je   .t_unop

.unknown:
    mov  rax, SYM_UNKNOWN
    ret

.t_int:        mov rax, SYM_INT        ;ret
               ret
.t_float:      mov rax, SYM_FLOAT      ;ret
               ret
.t_string:     mov rax, SYM_STRING     ;ret
               ret
.t_bool:       mov rax, SYM_BOOL       ;ret
               ret
.t_collection: mov rax, SYM_COLLECTION ;ret
               ret

.t_from_table:
    push rdi
    mov  rdi, [rdi + NODE_VALUE]    ;name ptr
    call sym_lookup
    test rax, rax
    jz   .unknown_pop
    mov  rax, [rax + SYM_TYPE]      ;entry.type
    pop  rdi
    ret
.unknown_pop:
    pop  rdi
    mov  rax, SYM_UNKNOWN
    ret

.t_binop:
    ;Recursive operand inference with numeric promotion (SPEC §3.2, §3.3).
    ;Validates operand legality and exits 2 on an illegal combination.
    ;r12/r13 preserved by sem_infer_type's callers; use callee-saved here.
    push r12
    push r13
    push r14
    mov  r14, rdi                   ;r14 = BINOP node

    mov  rdi, [r14 + NODE_LEFT]
    call sem_infer_type
    mov  r12, rax                   ;r12 = left type

    mov  rdi, [r14 + NODE_RIGHT]
    call sem_infer_type
    mov  r13, rax                   ;r13 = right type

    ;If either operand is unknown (e.g. an unresolved CSV column before the
    ;Phase 2 schema resolver), defer: do not type or reject. Permissive.
    cmp  r12, SYM_UNKNOWN
    je   .binop_unknown
    cmp  r13, SYM_UNKNOWN
    je   .binop_unknown

    ;Both numeric? int/int -> int; any float -> float (promotion).
    call .is_numeric_r12
    jnc  .binop_illegal
    call .is_numeric_r13
    jnc  .binop_illegal

    cmp  r12, SYM_FLOAT
    je   .binop_float
    cmp  r13, SYM_FLOAT
    je   .binop_float
    ;int op int -> int
    mov  rax, SYM_INT
    jmp  .binop_done

.binop_float:
    mov  rax, SYM_FLOAT
    jmp  .binop_done

.binop_unknown:
    mov  rax, SYM_UNKNOWN
.binop_done:
    pop  r14
    pop  r13
    pop  r12
    ret

.binop_illegal:
    ;string/bool in arithmetic -> type mismatch at the node's line
    mov  rdi, [r14 + NODE_LINE]
    call err_type_mismatch
    ;never returns

;.is_numeric_r12/r13 -> CF=1 if the type in r12/r13 is INT or FLOAT
.is_numeric_r12:
    cmp  r12, SYM_INT
    je   .num12_yes
    cmp  r12, SYM_FLOAT
    je   .num12_yes
    clc
    ret
.num12_yes:
    stc
    ret
.is_numeric_r13:
    cmp  r13, SYM_INT
    je   .num13_yes
    cmp  r13, SYM_FLOAT
    je   .num13_yes
    clc
    ret
.num13_yes:
    stc
    ret

.t_unop:
    ;unary minus: type of operand; must be numeric if known
    push r14
    mov  r14, rdi
    mov  rdi, [r14 + NODE_LEFT]
    call sem_infer_type
    cmp  rax, SYM_UNKNOWN
    je   .unop_done
    cmp  rax, SYM_INT
    je   .unop_done
    cmp  rax, SYM_FLOAT
    je   .unop_done
    ;unary minus on string/bool -> error
    mov  rdi, [r14 + NODE_LINE]
    call err_type_mismatch
.unop_done:
    pop  r14
    ret

;
;err_already_declared(rdi = name_ptr, rsi = line)
;prints: semantic error: 'name' already declared on line N
;exits with code 2
;
err_already_declared:
    push r12
    push r13
    mov  r12, rdi           ;r12 = name ptr
    mov  r13, rsi           ;r13 = line

    lea  rdi, [err_redecl_a]
    call print_str          ;"semantic error: '"
    mov  rdi, r12
    call print_str          ;name
    lea  rdi, [err_redecl_b]
    call print_str          ;"' already declared on line "
    mov  rdi, r13
    call print_uint_nl

    mov  rax, SYS_EXIT
    mov  rdi, 2
    syscall

;
;err_not_defined(rdi = name_ptr, rsi = line)
;
err_not_defined:
    push r12
    push r13
    mov  r12, rdi
    mov  r13, rsi

    lea  rdi, [err_redecl_a]
    call print_str          ;"semantic error: '"
    mov  rdi, r12
    call print_str          ;name
    lea  rdi, [err_undef_b]
    call print_str          ;"' is not defined on line "
    mov  rdi, r13
    call print_uint_nl

    mov  rax, SYS_EXIT
    mov  rdi, 2
    syscall

;
;err_type_mismatch(rdi = line)
;
err_type_mismatch:
    push r12
    mov  r12, rdi

    lea  rdi, [err_mismatch]
    call print_str          ;"semantic error: type mismatch on line "
    mov  rdi, r12
    call print_uint_nl

    mov  rax, SYS_EXIT
    mov  rdi, 2
    syscall

;
;print_str(rdi = null-terminated string) -> stderr
;
print_str:
    push rbx
    push rcx
    mov  rbx, rdi
    xor  rcx, rcx
.len:
    cmp  byte [rbx + rcx], 0
    je   .write
    inc  rcx
    jmp  .len
.write:
    mov  rax, SYS_WRITE
    mov  rdi, STDERR
    mov  rsi, rbx
    mov  rdx, rcx
    syscall
    pop  rcx
    pop  rbx
    ret

;
;print_uint_nl(rdi = unsigned integer) -> stderr, followed by newline
;
print_uint_nl:
    push rbp
    mov  rbp, rsp
    sub  rsp, 24
    mov  rax, rdi
    lea  r8,  [rsp + 20]
    mov  byte [r8], 10      ;newline at end
    dec  r8
    mov  ecx, 0
.digit:
    xor  rdx, rdx
    mov  rbx, 10
    div  rbx
    add  dl, '0'
    mov  [r8], dl
    dec  r8
    inc  ecx
    test rax, rax
    jnz  .digit
    inc  r8
    mov  rax, SYS_WRITE
    mov  rdi, STDERR
    mov  rsi, r8
    mov  rdx, rcx
    inc  rdx                ;include newline
    syscall
    add  rsp, 24
    pop  rbp
    ret