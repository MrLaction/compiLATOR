# compiLATOR — Formal Grammar (BNF)

## Design decisions

1. `where` always applies to the collection immediately to its left, never to the
   aggregate operator. `sum of prices where ...` filters `prices` before summing.

2. `is min` / `is max` inside a `where` clause is a selection-by-extreme construct,
   disambiguated from the assignment `is` by its position inside a condition.

3. `path` and `next` and `element` are context-sensitive identifiers, not reserved
   keywords. The parser recognizes them by lexeme string comparison where needed.

4. Statements are terminated by `\n` (TK_NEWLINE). No semicolons.

5. The grammar is LL(1) — one token of lookahead suffices for all dispatch decisions.

---

## Grammar

```
program        ::= statement* TK_EOF

statement      ::= assignment TK_NEWLINE
                 | let_binding TK_NEWLINE

assignment     ::= TK_ID TK_IS expr

let_binding    ::= TK_LET TK_ID TK_BE expr

expr           ::= aggregate_expr
                 | range_expr
                 | filter_expr
                 | arith_expr

aggregate_expr ::= agg_op TK_OF TK_ID filter_clause?
agg_op         ::= TK_SUM | TK_MIN | TK_MAX

range_expr     ::= 'path' TK_FROM TK_ID TK_TO TK_ID filter_clause?

filter_expr    ::= TK_ID filter_clause
                 (absorbed into arith_expr + optional WHERE clause)

filter_clause  ::= TK_WHERE condition

condition      ::= cond_term (TK_OR cond_term)*

cond_term      ::= cond_factor (TK_AND cond_factor)*

cond_factor    ::= TK_NOT cond_factor
                 | TK_EVERY 'element' TK_LESS_EQ 'next'
                 | access_expr TK_IN list_literal
                 | access_expr TK_IS agg_op
                 | comparison

comparison     ::= access_expr relop access_expr

access_expr    ::= TK_ID (TK_DOT TK_ID)*

relop          ::= TK_EQUAL | TK_NEQ | TK_LESS | TK_GREATER
                 | TK_LESS_EQ | TK_GREATER_EQ

arith_expr     ::= term ((TK_PLUS | TK_MINUS) term)*

term           ::= factor ((TK_STAR | TK_SLASH | TK_MOD) factor)*

factor         ::= TK_LPAREN arith_expr TK_RPAREN
                 | TK_MINUS factor
                 | TK_LIT_INT
                 | TK_LIT_FLOAT
                 | TK_LIT_STR
                 | TK_TRUE
                 | TK_FALSE
                 | access_expr

list_literal   ::= TK_LBRACKET list_items TK_RBRACKET

list_items     ::= literal (TK_COMMA literal)*

literal        ::= TK_LIT_INT | TK_LIT_FLOAT | TK_LIT_STR
                 | TK_TRUE | TK_FALSE
```

---

## AST node types

| Constant      | Value | Fields used                                      |
|---------------|-------|--------------------------------------------------|
| NODE_PROGRAM  | 1     | left = first NODE_STMT_LIST                      |
| NODE_ASSIGN   | 2     | left = NODE_ID, right = expr                     |
| NODE_LET      | 3     | left = NODE_ID, right = expr                     |
| NODE_FILTER   | 4     | left = src expr, right = condition               |
| NODE_COND_OR  | 5     | left, right = operands                           |
| NODE_COND_AND | 6     | left, right = operands                           |
| NODE_COND_NOT | 7     | left = operand                                   |
| NODE_COND_EVERY | 8   | (no children)                                    |
| NODE_CMP      | 9     | left = lhs, right = rhs, value = relop token     |
| NODE_IN_TEST  | 10    | left = access, right = list                      |
| NODE_IS_EXTREME | 11  | left = access, value = TK_MIN / TK_MAX           |
| NODE_BINOP    | 12    | left, right = operands, value = op token         |
| NODE_UNOP     | 13    | left = operand (always unary minus)              |
| NODE_AGGR     | 14    | value = agg token, left = src ID, right = filter |
| NODE_RANGE    | 15    | left = from ID, right = to ID, value = filter    |
| NODE_LIST     | 16    | left = item, right = next NODE_LIST              |
| NODE_ACCESS   | 17    | left = first ID, right = next ID (chain)         |
| NODE_ID       | 18    | value = pointer to interned name string          |
| NODE_LIT_INT  | 19    | value = integer value (qword)                    |
| NODE_LIT_FLOAT| 20    | value = pointer to interned string               |
| NODE_LIT_STR  | 21    | value = pointer to interned string               |
| NODE_LIT_BOOL | 22    | value = 1 (true) or 0 (false)                    |
| NODE_STMT_LIST| 23    | left = stmt, right = next NODE_STMT_LIST or 0    |
