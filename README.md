# compiLATOR

A compiler built from scratch in x86-64 assembly (NASM) for a custom declarative language, developed as a university project.

---

## Language

The language is a **declarative, query-oriented** language designed to express data transformations, filters, and aggregations in a readable, natural-language-like syntax. Statements are terminated by newlines (`\n`), and line comments use `--`.

### Philosophy

Instead of telling the machine *how* to compute something step by step, you describe *what* you want. The compiler figures out the rest.

### Data types

| Type    | Example          |
|---------|------------------|
| Integer | `42`, `0`, `100` |
| Float   | `3.14`, `0.5`    |
| Boolean | `true`, `false`  |
| String  | `"hello world"`  |

### Reserved words

```
is  where  and  or  not  every  in  of  let  be  from  to  min  max  sum  true  false
```

### Operators

| Category   | Symbols                          |
|------------|----------------------------------|
| Arithmetic | `+` `-` `*` `/` `%`             |
| Relational | `==` `!=` `<` `>` `<=` `>=`    |
| Logical    | `and` `or` `not` (keywords)     |
| Assignment | `is` / `be` (declarative style) |

### Delimiters

`(` `)` `[` `]` `.` `,`

### Comments

Line comments, discarded by the lexer:

```
-- this is a comment
```

### Statement terminator

Newline (`\n`) — no semicolons needed.

### Example program

```
-- Filter users older than 18
result is users where age > 18

-- Filter with multiple conditions
active_users is users where age > 18 and active == true

-- Check ordering
sorted is numbers where every element <= next

-- Aggregate with condition
total is sum of prices where category == "food"

-- Find shortest path
let shortest_route be path from A to B where distance is min

-- Membership test with list
filtered is orders where user.region in ["north", "south"]

-- Arithmetic in filter
tax_total is sum of orders.amount where price + tax > 100.0

-- Find maximum
let best_score be results where score is max
```

---

## Architecture

The compiler is written entirely in **NASM x86-64 assembly** targeting Linux. Modules are assembled separately and linked into a single binary.

```
compiLATOR/
├── lexer/
│   ├── symbol_table.asm  ← token constants, keyword strings, name table
│   ├── lexer.asm         ← DFA tokenizer
│   ├── main.asm          ← entry point (lexer standalone binary)
│   ├── Makefile
│   └── test.src
├── parser/
│   ├── ast.asm           ← arena allocator for AST nodes
│   ├── strpool.asm       ← string pool for lexeme persistence
│   ├── parser.asm        ← LL(1) recursive descent parser
│   ├── main.asm          ← entry point (parser standalone binary)
│   ├── grammar.md        ← formal BNF grammar
│   ├── Makefile
│   └── test.src
└── README.md
```

---

## Stage 1 — Lexical Analyzer

**Status: complete and working.**

The lexical analyzer reads source code from `stdin` character by character and emits a stream of tokens, each identified by a type ID and its lexeme text.

### How it works

The tokenizer is implemented as a **Deterministic Finite Automaton (DFA)**. The three modules divide responsibilities cleanly:

#### `symbol_table.asm`

Contains all static data for the compiler. It exports:

- Token ID constants (`TK_IS = 1`, `TK_WHERE = 2`, ... `TK_ERROR = 42`)
- Keyword strings (`kw_is`, `kw_where`, etc.) used for reserved word lookup
- Token name strings (`"TK_IS"`, padded for aligned output)
- A pointer table (`tk_name_table`) indexed by token ID, used to print token names

This module has no code — only `.data` section.

#### `lexer.asm`

Implements the DFA. Exports `get_token`, `lexeme`, and `lexeme_len`. Imports keyword strings from `symbol_table.asm` via `extern`.

`get_token` works as follows:

1. **S0** — Skip whitespace (space, tab, `\r`); emit `TK_NEWLINE` on `\n`
2. Inspect the first character to decide which DFA branch to follow
3. Follow the appropriate state sequence to consume the full token
4. Return the token ID in `rax` and the token text in `lexeme[]`

Key implementation details:

- **Buffered I/O** — reads up to 4096 bytes at a time from `stdin` via `SYS_READ`
- **1-character putback** — lets the DFA "un-read" one character when it has consumed one too many
- **Tail-call for comments** — when a `-- ...` comment is consumed, jumps back to `get_token`
- **Keyword lookup** — identifiers are fully read, then compared against the reserved word list; if no match, classified as `TK_ID`
- **Two-character operators** — `==`, `!=`, `<=`, `>=` handled by reading a second character and pushing it back if it does not complete the operator

#### `main.asm`

Entry point (`_start`). Calls `get_token` in a loop, prints each token's name and lexeme, exits on `TK_EOF`.

### Token table (42 tokens)

| ID | Token           | Description                  |
|----|-----------------|------------------------------|
| 1  | `TK_IS`         | keyword `is`                 |
| 2  | `TK_WHERE`      | keyword `where`              |
| 3  | `TK_AND`        | keyword `and`                |
| 4  | `TK_OR`         | keyword `or`                 |
| 5  | `TK_NOT`        | keyword `not`                |
| 6  | `TK_EVERY`      | keyword `every`              |
| 7  | `TK_IN`         | keyword `in`                 |
| 8  | `TK_OF`         | keyword `of`                 |
| 9  | `TK_LET`        | keyword `let`                |
| 10 | `TK_BE`         | keyword `be`                 |
| 11 | `TK_FROM`       | keyword `from`               |
| 12 | `TK_TO`         | keyword `to`                 |
| 13 | `TK_MIN`        | keyword `min`                |
| 14 | `TK_MAX`        | keyword `max`                |
| 15 | `TK_SUM`        | keyword `sum`                |
| 16 | `TK_TRUE`       | keyword `true`               |
| 17 | `TK_FALSE`      | keyword `false`              |
| 18 | `TK_LIT_INT`    | integer literal: `42`        |
| 19 | `TK_LIT_FLOAT`  | float literal: `3.14`        |
| 20 | `TK_LIT_STRING` | string literal: `"hello"`    |
| 21 | `TK_ID`         | identifier: `result`, `age`  |
| 22 | `TK_GREATER`    | `>`                          |
| 23 | `TK_LESS`       | `<`                          |
| 24 | `TK_GREATER_EQ` | `>=`                         |
| 25 | `TK_LESS_EQ`    | `<=`                         |
| 26 | `TK_EQUAL`      | `==`                         |
| 27 | `TK_NOT_EQUAL`  | `!=`                         |
| 28 | `TK_ASSIGN`     | `=`                          |
| 29 | `TK_PLUS`       | `+`                          |
| 30 | `TK_MINUS`      | `-`                          |
| 31 | `TK_MULTIPLY`   | `*`                          |
| 32 | `TK_DIVIDE`     | `/`                          |
| 33 | `TK_MODULO`     | `%`                          |
| 34 | `TK_LPAREN`     | `(`                          |
| 35 | `TK_RPAREN`     | `)`                          |
| 36 | `TK_LBRACKET`   | `[`                          |
| 37 | `TK_RBRACKET`   | `]`                          |
| 38 | `TK_COMMA`      | `,`                          |
| 39 | `TK_DOT`        | `.`                          |
| 40 | `TK_NEWLINE`    | `\n` (statement terminator)  |
| 41 | `TK_EOF`        | end of input                 |
| 42 | `TK_ERROR`      | unrecognized character       |

### Build and run

```bash
# Requirements
sudo apt install nasm

# Build and run
cd lexer/
make run < test.src
```

### Sample output

```
=== LEXICAL ANALYZER — Declarative Language ===
TOKEN            LEXEME

TK_ID            --> [result]
TK_IS            --> [is]
TK_ID            --> [users]
TK_WHERE         --> [where]
TK_ID            --> [age]
TK_GREATER       --> [>]
TK_LIT_INT       --> [18]
TK_NEWLINE       --> [\n]
...
TK_EOF           --> []
```

---

## Stage 2 — Syntax Analyzer

**Status: complete and working.**

The syntax analyzer consumes the token stream produced by the lexer and validates it against the formal grammar of the language, building an Abstract Syntax Tree (AST) in the process.

### How it works

The parser is a **hand-written LL(1) recursive descent parser** — one function per non-terminal, with a single token of lookahead sufficient to resolve every production unambiguously.

#### `ast.asm`

Arena allocator for AST nodes. Each node is 40 bytes with five fixed fields:

| Offset | Field   | Purpose                                      |
|--------|---------|----------------------------------------------|
| +0     | `type`  | Node type constant (e.g. `NODE_ASSIGN`)      |
| +8     | `left`  | Pointer to left child                        |
| +16    | `right` | Pointer to right child                       |
| +24    | `value` | Literal value, token ID, or string pointer   |
| +32    | `line`  | Source line number for error reporting       |

The pool holds 2048 nodes (80 KB) in `.bss`. `alloc_node(type, line)` is a single counter increment — no `malloc`, no syscalls, no fragmentation. Exit code 99 on exhaustion.

#### `strpool.asm`

64 KB static string pool. `intern_str(src)` copies a null-terminated lexeme into the pool and returns a stable pointer. The lexer reuses its `lexeme[]` buffer on every call; the string pool gives AST nodes a persistent copy of each identifier or literal. Exit code 98 on exhaustion.

#### `parser.asm`

Recursive descent parser. Token state is maintained in three module-level variables updated by `advance()`:

- `cur_token` — current token type ID
- `cur_lexeme` — pointer to interned string of current lexeme
- `cur_line` — current source line number

`expect(type)` verifies `cur_token` without advancing; the caller manages all `advance()` calls explicitly. On any mismatch, `syntax_error` prints the line number to stderr and exits with code 1.

### Formal grammar (BNF)

```
program        ::= statement* TK_EOF
statement      ::= assignment TK_NEWLINE
                 | let_binding TK_NEWLINE
assignment     ::= TK_ID TK_IS expr
let_binding    ::= TK_LET TK_ID TK_BE expr

expr           ::= aggregate_expr
                 | range_expr
                 | arith_expr filter_clause?

aggregate_expr ::= agg_op TK_OF access_expr filter_clause?
agg_op         ::= TK_SUM | TK_MIN | TK_MAX

range_expr     ::= 'path' TK_FROM TK_ID TK_TO TK_ID filter_clause?

filter_clause  ::= TK_WHERE condition
condition      ::= cond_term (TK_OR cond_term)*
cond_term      ::= cond_factor (TK_AND cond_factor)*
cond_factor    ::= TK_NOT cond_factor
                 | TK_EVERY TK_ID TK_LESS_EQ TK_ID
                 | arith_expr TK_IN list_literal
                 | arith_expr TK_IS agg_op
                 | comparison

comparison     ::= arith_expr relop arith_expr
relop          ::= TK_EQUAL | TK_NOT_EQUAL | TK_LESS | TK_GREATER
                 | TK_LESS_EQ | TK_GREATER_EQ

arith_expr     ::= term ((TK_PLUS | TK_MINUS) term)*
term           ::= factor ((TK_MULTIPLY | TK_DIVIDE | TK_MODULO) factor)*
factor         ::= TK_LPAREN arith_expr TK_RPAREN
                 | TK_MINUS factor
                 | TK_LIT_INT | TK_LIT_FLOAT | TK_LIT_STRING
                 | TK_TRUE | TK_FALSE
                 | access_expr

access_expr    ::= TK_ID (TK_DOT TK_ID)*
list_literal   ::= TK_LBRACKET factor (TK_COMMA factor)* TK_RBRACKET
```

### Node types

| Constant         | Meaning                                          |
|------------------|--------------------------------------------------|
| `NODE_PROGRAM`   | Root — linked list of statements                |
| `NODE_STMT_LIST` | Statement list node — left=stmt, right=next     |
| `NODE_ASSIGN`    | `id IS expr` — left=id, right=expr              |
| `NODE_LET`       | `LET id BE expr` — left=id, right=expr          |
| `NODE_FILTER`    | `expr WHERE cond` — left=expr, right=cond       |
| `NODE_AGGR`      | Aggregate — value=op token, left=src, right=filter |
| `NODE_RANGE`     | Path — left=from_id, right=to_id, value=filter  |
| `NODE_COND_OR`   | Logical OR — left, right                        |
| `NODE_COND_AND`  | Logical AND — left, right                       |
| `NODE_COND_NOT`  | Logical NOT — left                              |
| `NODE_COND_EVERY`| `every element <= next`                         |
| `NODE_CMP`       | Comparison — left=lhs, right=rhs, value=relop   |
| `NODE_IN_TEST`   | `expr IN list` — left=expr, right=list          |
| `NODE_IS_EXTREME`| `expr IS min/max` — left=expr, value=token      |
| `NODE_BINOP`     | Arithmetic binop — left, right, value=op token  |
| `NODE_UNOP`      | Unary minus — left=operand                      |
| `NODE_LIST`      | List literal — left=item, right=next            |
| `NODE_ACCESS`    | Dotted access — left=first, right=next          |
| `NODE_ID`        | Identifier — value=pointer to name              |
| `NODE_LIT_INT`   | Integer literal — value=integer                 |
| `NODE_LIT_FLOAT` | Float literal — value=pointer to string         |
| `NODE_LIT_STR`   | String literal — value=pointer to string        |
| `NODE_LIT_BOOL`  | Boolean literal — value=1 (true) or 0 (false)  |

### Build and run

```bash
cd parser/
make run < test.src
# → syntax OK
```

On a syntax error:

```
parse error: unexpected token on line 3
```

---

## Stage 3 — Semantic Analyzer

**Status: not started.**

---

## Stage 4 — Intermediate Code Generator

**Status: not started.**

---

## Stage 5 — Code Optimizer

**Status: not started.**

---

## Stage 6 — Code Generator

**Status: not started.**

---

## Requirements

- Linux x86-64 (Debian, Ubuntu, Arch, etc.)
- `nasm` — `sudo apt install nasm`
- `ld` — included in `binutils`, installed by default

---

## License

University project — all rights reserved.
