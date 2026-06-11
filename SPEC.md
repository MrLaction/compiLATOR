# LATOR v1.0 — Language Specification

Normative definition of the LATOR language as compiled by compiLATOR v1.0.
Where the current implementation diverges, the divergence is marked
`[gap: Bn]` and tracked in TODO.md. This document wins every dispute.

---

## 1. Source format and lexical structure

- Encoding: ASCII, byte-oriented. Statements are terminated by `\n`.
  Blank lines are permitted anywhere. `\r` and `\t` are whitespace.
- Comments: `--` to end of line, discarded by the lexer.
- Identifiers: `[A-Za-z_][A-Za-z0-9_]*`, max 255 bytes.
- Integer literals: `[0-9]+`. Value must fit signed 64-bit; overflow is
  currently undiagnosed `[gap: B9]`.
- Float literals: `[0-9]+ '.' [0-9]+`. A trailing dot (`1.`) is a lexical
  error `[gap: B9 — currently accepted]`.
- String literals: `"` ... `"`. No escape sequences. May not contain `"`
  or a newline. Max 255 bytes.
- Keywords (17): `is where and or not every in of let be from to min max
  sum true false`.
- Context-sensitive identifiers (not keywords): `path`, `element`, `next`.
- The token `=` (`TK_ASSIGN`) exists lexically but belongs to no
  production. Its use is a syntax error. Reserved for v1.1.

## 2. Grammar (v1.0 normative)

Unified precedence ladder. Boolean and arithmetic expressions share one
grammar; the type system (section 3) rejects ill-typed forms such as
`(a > b) + 1`. This supersedes the split condition/arith grammar of
`grammar.md` `[gap: B2 — parenthesized conditions currently rejected]`.

```
program     ::= NEWLINE* (statement NEWLINE+)* TK_EOF

statement   ::= TK_ID 'is' rhs
              | 'let' TK_ID 'be' rhs

rhs         ::= aggregate
              | expr ('where' expr)?          ; filter source must be a collection

aggregate   ::= ('sum'|'min'|'max') 'of' source_col ('where' expr)?
source_col  ::= TK_ID ('.' TK_ID)?            ; collection [. column]

expr        ::= or_expr
or_expr     ::= and_expr ('or' and_expr)*
and_expr    ::= not_expr ('and' not_expr)*
not_expr    ::= 'not' not_expr | rel_expr
rel_expr    ::= 'every' 'element' '<=' 'next'
              | add_expr ( relop add_expr
                         | 'in' list_literal
                         | 'is' ('min'|'max') )?
add_expr    ::= mul_expr (('+'|'-') mul_expr)*
mul_expr    ::= unary (('*'|'/'|'%') unary)*
unary       ::= '-' unary | primary
primary     ::= '(' expr ')'
              | TK_LIT_INT | TK_LIT_FLOAT | TK_LIT_STRING
              | 'true' | 'false'
              | access
access      ::= TK_ID ('.' TK_ID)*

list_literal::= '[' literal (',' literal)* ']'
literal     ::= TK_LIT_INT | TK_LIT_FLOAT | TK_LIT_STRING | 'true' | 'false'
relop       ::= '==' | '!=' | '<' | '>' | '<=' | '>='
```

Rules:

1. Comparison is **non-associative**: at most one relop per `rel_expr`.
   `a < b < c` is a syntax error.
2. `every element <= next` requires exactly the lexemes `element` and
   `next` `[gap: B5 — arbitrary identifiers currently accepted]`.
3. Aggregates are not sub-expressions: `x is sum of a.f + 1` is a syntax
   error. (v1.1 candidate.)
4. `is min` / `is max` and `in` atoms are legal only inside a `where`
   predicate (semantic rule 3.6).
5. `path from A to B ...` still parses as in the legacy grammar, but is
   rejected by the semantic stage: `error: 'path' expressions are not
   supported in v1.0` (exit 2). Reserved for v1.1.

## 3. Type system

Types: `int` (signed 64-bit), `float` (IEEE 754 binary64), `bool`,
`string`, `collection` (typed record table).

### 3.1 Compilation model — compile-time schema resolution

For every collection referenced by the program, `compi` opens
`./data/<name>.csv` **at compile time**, reads the header and the first
data row, and resolves the full column schema (names and types, per
section 4). Consequences:

- All expressions, including predicates over CSV columns, are fully and
  statically typed. The IR is typed; generated code is monomorphic.
- A referenced CSV missing at compile time is a semantic error (exit 2).
- The compiled binary embeds the schema and revalidates it when loading
  data at runtime (section 4.4); a mismatch is a runtime error (exit 3).
- Recompilation is required if a schema changes. This is by design.

### 3.2 Numeric promotion

In any mixed `int`/`float` arithmetic operation or comparison, the `int`
operand is promoted to `float` (`CVTIF` in the IR). Promotion applies
both to literals/bindings and to CSV columns
`[gap: B3 — int/float comparison is currently a hard error]`.

### 3.3 Operator typing

| Operator | Operands | Result |
|---|---|---|
| `+ - *` | int×int | int |
| `+ - *` | numeric×numeric, at least one float | float |
| `/` | int×int | int (truncates toward zero) |
| `/` | mixed/float | float (IEEE; ÷0 → ±inf/NaN) |
| `%` | int×int only | int |
| unary `-` | numeric | same type |
| `< <= > >=` | numeric×numeric (promote) | bool |
| `== !=` | numeric×numeric (promote), string×string, bool×bool | bool |
| `and or` | bool×bool | bool |
| `not` | bool | bool |
| `x in [..]` | x matches list element type (int promotes to float) | bool |

Anything not in the table is a semantic error (exit 2): string
concatenation, bool arithmetic, string ordering, heterogeneous lists.
Integer division by zero is a **runtime** error (exit 3).
`[gap: B3 — `"hi" + 5` currently passes]`

### 3.4 Bindings

`x is rhs` and `let x be rhs` are semantically identical. The bound name
takes the static type of its RHS. Rebinding a name is a semantic error
(exit 2). A scalar identifier used outside a predicate must be a prior
binding `[gap: B4 — currently unchecked]`.

### 3.5 Name resolution inside a `where` predicate

Over filter source S, an `access` chain `a.b.c` denotes, in order:

1. the column of S whose literal name is the dotted string (`"a.b.c"` —
   dots are legal in CSV header names); else
2. a prior scalar binding (single-segment names only); else
3. semantic error: `'x' is neither a column of S nor a binding`.

If both exist, the column wins, silently.

### 3.6 Predicate-only atoms

- `f is min` / `f is max`: per-row atom equivalent to
  `f == EXTREME(f over ALL rows of the source)`, where the extreme is
  computed over the unfiltered source. Compositional: combines freely
  with `and`/`or`/`not`. Column must be numeric.
- `every element <= next`: collection-level sortedness atom. The source
  must be a single-column numeric collection; otherwise semantic error.
  Evaluates true iff `col[i] <= col[i+1]` for all adjacent pairs
  (vacuously true for 0 or 1 rows). Because the atom is row-independent,
  a filter built on it yields all rows or zero rows.
- A bare boolean expression is a valid predicate (`where active`,
  `where not active`) provided it types as bool.
- The `where` expression must type as bool.

### 3.7 Aggregates

`sum|min|max of C[.f] [where p]`: filter p (if present) applies to C's
rows first; the aggregate then reduces column f. If C has exactly one
column, `.f` may be omitted; otherwise omission is a semantic error
(ambiguous column). Column must be numeric. Result type: `sum` over int
→ int, over float → float; `min`/`max` → the column type. Aggregating
zero rows: `sum` → 0 (typed), `min`/`max` → runtime error (exit 3).

## 4. Data model — CSV

### 4.1 File format

- Location: `./data/<collection>.csv`, resolved against the CWD of the
  invoking process (compiler and compiled binary alike).
- Line 1: header — comma-separated column names (identifier charset,
  dots permitted). Subsequent lines: one record each.
- Fields may optionally be wrapped in double quotes; a quoted field may
  contain commas but not `"` or newlines. Max field length 255 bytes.
- A header with no data rows is a compile-time error (types cannot be
  inferred).

### 4.2 Type inference (per column, from the FIRST data row)

| First-row cell matches | Column type |
|---|---|
| `-?[0-9]+` | int |
| `-?[0-9]+\.[0-9]+` | float |
| `true` / `false` (lowercase) | bool |
| anything else | string |

### 4.3 Validation

Every cell of every row must parse as its column's inferred type.
Violations: compile-time error if detected while resolving schema
(first row), runtime error (exit 3) with row/column in the message
during full load.

### 4.4 Runtime revalidation

The compiled binary's loader verifies column count, names, and
per-cell types against the embedded schema before evaluation begins.

## 5. Program semantics and output

A program is a sequence of bindings evaluated top to bottom. **Every**
binding prints to stdout immediately upon evaluation, in source order:

- Scalar: `name = value\n`. Ints in decimal; floats with up to 6
  decimal places, trailing zeros trimmed, at least one decimal digit
  (`3.14`, `2.0`); bools `true`/`false`; strings raw, unquoted.
- Collection: header `name (N rows):\n`, then the column-name row, then
  one line per record, fields joined with `" | "`. Cells format as
  scalars do. `N` of 0 prints the header lines and no records.

### 5.1 Worked example

`data/users.csv`:

```
id,name,age,active
1,ana,33,true
2,luis,17,false
3,sara,41,true
```

Program:

```
limit is 18
adults is users where age > limit
ids is sum of users.id
```

stdout, exactly:

```
limit = 18
adults (2 rows):
id | name | age | active
1 | ana | 33 | true
3 | sara | 41 | true
ids = 6
```

## 6. Diagnostics and exit codes

| Code | Meaning |
|---|---|
| 0 | success |
| 1 | lexical/syntax errors (one or more) |
| 2 | semantic errors (one or more) |
| 3 | runtime error in a compiled program |
| 97 / 98 / 99 | IR pool / string pool / AST pool exhausted |

The compiler reports multiple errors per run, synchronizing at
`TK_NEWLINE` after a syntax error; messages name the found token, the
expected set, and the 1-based source line `[gap: B1 lines off by one;
B8 single-error exit; B9 lexical errors unlabelled]`.

## 7. Fixed capacities (no dynamic allocation, by design)

| Pool | Capacity |
|---|---|
| Lexeme buffer | 256 B |
| AST node pool | 2048 nodes |
| Compiler string pool | 64 KB |
| Symbol table | 256 entries |
| IR instruction pool | 8192 instructions |
| Collections per program | 16 |
| Columns per collection | 16 |
| Runtime row arena (shared) | 4 MB (8-byte cells) |
| Runtime string pool | 256 KB |

Exhaustion is a hard, diagnosed exit — never silent corruption.

## 8. Reserved for v1.1

`path from A to B` (graph search) · `=` operator · string escapes ·
string ordering · aggregates as sub-expressions · `show` statement ·
typed CSV headers.
