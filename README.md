# compiLATOR

A compiler built from scratch in x86-64 assembly (NASM) for a custom declarative language, developed as a university project.

---

## Language

The language is a **declarative, query-oriented** language designed to express data transformations, filters, and aggregations in a readable, natural-language-like syntax. Statements are terminated by newlines (`\n`), and line comments use `--`.

### Philosophy

Instead of telling the machine *how* to compute something step by step, you describe *what* you want. The compiler figures out the rest.

### Data types

| Type    | Example              |
|---------|----------------------|
| Integer | `42`, `0`, `100`     |
| Float   | `3.14`, `0.5`        |
| Boolean | `true`, `false`      |
| String  | `"hello world"`      |

### Reserved words
is where and or not every in of let be from to min max sum true false


### Operators

| Category   | Symbols              |
|------------|----------------------|
| Arithmetic | `+` `-` `*` `/` `%` |
| Relational | `==` `!=` `<` `>` `<=` `>=` |
| Logical    | `and` `or` `not` (keywords) |
| Assignment | `=`                  |

### Delimiters

`(` `)` `[` `]` `.` `,`

### Comments

Line comments, discarded by the lexer:

-- this is a comment


### Statement terminator

Newline (`\n`) — no semicolons needed.

### Example program

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


---

## Architecture

The compiler is written entirely in **NASM x86-64 assembly** targeting Linux. It is organized as independent modules that are assembled separately and linked into a single binary.

compiLATOR/
├── lexer/
│ ├── symbol_table.asm ← token data, keyword strings, name table
│ ├── lexer.asm ← DFA logic, tokenizer
│ ├── main.asm ← entry point, output loop
│ ├── Makefile ← build system
│ └── test.src ← sample source file
└── README.md


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

Implements the DFA. It exports `get_token`, `lexeme`, and `lexeme_len`. It imports keyword strings from `symbol_table.asm` via `extern`.

`get_token` works as follows:

1. **S0** — Skip whitespace (space, tab, `\r`); emit `TK_NEWLINE` on `\n`
2. Inspect the first character to decide which DFA path to follow
3. Follow the appropriate state sequence to consume the full token
4. Return the token ID in `rax` and the token text in `lexeme[]`

Key implementation details:

- **Buffered I/O** — reads up to 4096 bytes at a time from `stdin` via `SYS_READ`
- **1-character putback** — lets the DFA "un-read" one character when it has consumed one too many
- **Tail-call for comments** — when a `-- ...` line comment is consumed, the function jumps back to `get_token`
- **Keyword lookup** — identifiers are fully read first, then compared against the reserved word list; if no match, classified as `TK_ID`
- **Two-character operators** — `==`, `!=`, `<=`, `>=` are handled by reading a second character and pushing it back if it does not complete the operator

#### `main.asm`

Entry point (`_start`). Calls `get_token` in a loop, prints each token's name and lexeme, and exits on `TK_EOF`.

### Token table (42 tokens)

| ID | Token          | Description                |
|----|----------------|----------------------------|
| 1  | `TK_IS`        | keyword `is`               |
| 2  | `TK_WHERE`     | keyword `where`            |
| 3  | `TK_AND`       | keyword `and`              |
| 4  | `TK_OR`        | keyword `or`               |
| 5  | `TK_NOT`       | keyword `not`              |
| 6  | `TK_EVERY`     | keyword `every`            |
| 7  | `TK_IN`        | keyword `in`               |
| 8  | `TK_OF`        | keyword `of`               |
| 9  | `TK_LET`       | keyword `let`              |
| 10 | `TK_BE`        | keyword `be`               |
| 11 | `TK_FROM`      | keyword `from`             |
| 12 | `TK_TO`        | keyword `to`               |
| 13 | `TK_MIN`       | keyword `min`              |
| 14 | `TK_MAX`       | keyword `max`              |
| 15 | `TK_SUM`       | keyword `sum`              |
| 16 | `TK_TRUE`      | keyword `true`             |
| 17 | `TK_FALSE`     | keyword `false`            |
| 18 | `TK_LIT_INT`   | integer literal: `42`      |
| 19 | `TK_LIT_FLOAT` | float literal: `3.14`      |
| 20 | `TK_LIT_STRING`| string literal: `"hello"`  |
| 21 | `TK_ID`        | identifier: `x`, `result`  |
| 22 | `TK_ASSIGN`    | `=`                        |
| 23 | `TK_PLUS`      | `+`                        |
| 24 | `TK_MINUS`     | `-`                        |
| 25 | `TK_STAR`      | `*`                        |
| 26 | `TK_SLASH`     | `/`                        |
| 27 | `TK_MOD`       | `%`                        |
| 28 | `TK_EQUAL`     | `==`                       |
| 29 | `TK_NEQ`       | `!=`                       |
| 30 | `TK_LESS`      | `<`                        |
| 31 | `TK_GREATER`   | `>`                        |
| 32 | `TK_LESS_EQ`   | `<=`                       |
| 33 | `TK_GREATER_EQ`| `>=`                       |
| 34 | `TK_LPAREN`    | `(`                        |
| 35 | `TK_RPAREN`    | `)`                        |
| 36 | `TK_LBRACKET`  | `[`                        |
| 37 | `TK_RBRACKET`  | `]`                        |
| 38 | `TK_DOT`       | `.`                        |
| 39 | `TK_COMMA`     | `,`                        |
| 40 | `TK_NEWLINE`   | `\n` (statement terminator)|
| 41 | `TK_EOF`       | end of input               |
| 42 | `TK_ERROR`     | unrecognized character     |

### Build and run

```bash
# Requirements
sudo apt install nasm

# Build
cd lexer/
make

# Run
./lexer < test.src
''' 

### Build and run

```bash
# Requirements
sudo apt install nasm

# Build
cd lexer/
make

# Run
./lexer < test.src

# Build and run in one step
make run
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

**Status: not started.**

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


