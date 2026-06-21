;nodes.inc — AST node-type tags and field offsets, shared by the parser
;(via ast.asm) and the semantic stage. Single source of truth so the IR
;and any later stage include the same definitions instead of carrying a
;private copy that can drift. Include-guarded for safe double inclusion.

%ifndef NODES_INC
%define NODES_INC

NODE_PROGRAM    equ 1   ;root: left=first STMT_LIST, right=0
NODE_ASSIGN     equ 2   ;result IS expr  — left=NODE_ID(name), right=expr
NODE_LET        equ 3   ;LET id BE expr  — left=NODE_ID(name), right=expr
NODE_FILTER     equ 4   ;id WHERE cond   — left=NODE_ID(src),  right=condition
NODE_COND_OR    equ 5   ;OR  — left, right = operands
NODE_COND_AND   equ 6   ;AND — left, right = operands
NODE_COND_NOT   equ 7   ;NOT — left = operand
NODE_COND_EVERY equ 8   ;every element <= next — no children
NODE_CMP        equ 9   ;comparison — left=lhs, right=rhs, value=relop token
NODE_IN_TEST    equ 10  ;id IN list    — left=access_expr, right=list
NODE_IS_EXTREME equ 11  ;id IS min/max — left=access_expr, value=TK_MIN/TK_MAX
NODE_BINOP      equ 12  ;arith binop   — left, right = operands, value=op token
NODE_UNOP       equ 13  ;unary minus   — left = operand
NODE_AGGR       equ 14  ;agg_op OF id WHERE? — value=agg token, left=src, right=filter_clause (or 0)
NODE_RANGE      equ 15  ;PATH FROM a TO b WHERE? — left=from_id, right=to_id, value=filter_clause ptr
NODE_LIST       equ 16  ;list literal  — left=first item, right=next item (linked list)
NODE_ACCESS     equ 17  ;dotted access — left=first segment, right=next (linked list)
NODE_ID         equ 18  ;identifier    — value=pointer to null-terminated name in lexeme copy
NODE_LIT_INT    equ 19  ;int literal   — value=integer value (as qword)
NODE_LIT_FLOAT  equ 20  ;float literal — value=pointer to string copy (parse at codegen)
NODE_LIT_STR    equ 21  ;string literal — value=pointer to string copy
NODE_LIT_BOOL   equ 22  ;bool literal  — value=1 (true) or 0 (false)
NODE_STMT_LIST  equ 23  ;statement linked list — left=stmt, right=next NODE_STMT_LIST or 0

;Node field offsets
NODE_TYPE   equ 0
NODE_LEFT   equ 8
NODE_RIGHT  equ 16
NODE_VALUE  equ 24
NODE_LINE   equ 32
NODE_SIZE   equ 40

%endif ; NODES_INC
