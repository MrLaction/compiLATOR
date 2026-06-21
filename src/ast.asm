;ast.asm — AST node arena for the LATOR parser (%included by parser.asm)
;
;Fixed pool of 2048 nodes, bump-allocated by alloc_node; exhaustion
;exits with code 99. Node layout: type, line, value, left, right,
;extra (NODE_* offsets). No dynamic allocation anywhere, by design.
;
;Exports: alloc_node, ast_pool, ast_count.

default abs

;Node-type tags and field offsets (shared with the semantic stage)
%include "nodes.inc"

;Arena constants
AST_POOL_CAP equ 2048   ;maximum nodes

section .bss
    ast_pool    resb AST_POOL_CAP * NODE_SIZE
    ast_count   resq 1              ;next free node index (0-based)

section .text

global alloc_node
global ast_pool
global ast_count

;alloc_node(type, line) -> rax = pointer to zeroed node
;rdi = node type constant
;rsi = source line number
;Aborts with exit code 99 if pool is exhausted.
alloc_node:
    push rbp
    mov  rbp, rsp
    push rbx
    push r12

    mov  rbx, rdi                   ;save type
    mov  r12, rsi                   ;save line

    mov  rax, [ast_count]
    cmp  rax, AST_POOL_CAP
    jge  .pool_full

    ;compute pointer: ast_pool + rax * NODE_SIZE
    imul rax, rax, NODE_SIZE
    lea  rcx, [ast_pool]
    add  rax, rcx                   ;rax = node pointer

    ;zero the 40 bytes
    mov  qword [rax + NODE_TYPE],  0
    mov  qword [rax + NODE_LEFT],  0
    mov  qword [rax + NODE_RIGHT], 0
    mov  qword [rax + NODE_VALUE], 0
    mov  qword [rax + NODE_LINE],  0

    ;set type and line
    mov  qword [rax + NODE_TYPE], rbx
    mov  qword [rax + NODE_LINE], r12

    ;advance counter
    mov  rcx, [ast_count]
    inc  rcx
    mov  [ast_count], rcx

    pop  r12
    pop  rbx
    pop  rbp
    ret

.pool_full:
    ;fatal: AST pool exhausted
    mov  rax, 60                    ;SYS_EXIT
    mov  rdi, 99
    syscall

