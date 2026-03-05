# compiLATOR

A compiler built from scratch in x86-64 assembly (NASM) for a custom procedural language, developed as a university project.

---

## Language

The language is a statically-typed, imperative/procedural language currently unnamed. It supports four primitive data types, standard control flow constructs, block comments, and semicolon-terminated statements.

### Data types

| Type     | Keyword  | Example          |
|----------|----------|------------------|
| Integer  | `int`    | `42`, `0`, `100` |
| Float    | `float`  | `3.14`, `0.5`    |
| Boolean  | `bool`   | `true`, `false`  |
| String   | `string` | `"hello world"`  |

### Reserved words

```
int  float  bool  string  if  else  while  for  return  true  false
```

### Operators

| Category   | Symbols              |
|------------|----------------------|
| Arithmetic | `+`  `-`  `*`  `/`  |
| Relational | `==`  `!=`  `<`  `>`  `<=`  `>=` |
| Logical    | `&&`  `\|\|`  `!`  |
| Assignment | `=`                  |

### Delimiters

`(` `)` `{` `}` `;` `,`

### Comments

Block comments only, discarded by the lexer:
```
/* this is a comment */
```

### Example program

```
int x;
float y;
bool active;

x = 42;
y = 3.14;
active = true;

/* check value */
if (x == 42) {
    y = y + 1.0;
}

while (x > 0) {
    x = x - 1;
}

if (active != false && x >= 0) {
    x = x + 1;
}
```

---

## Architecture

The compiler is written entirely in **NASM x86-64 assembly** targeting Linux (Debian). It is organized as independent modules that are assembled separately and linked into a single binary.

```
compiLATOR/
├── lexer/
│   ├── symbol_table.asm   ← token data, keyword strings, name table
│   ├── lexer.asm          ← DFA logic, tokenizer
│   ├── main.asm           ← entry point, output loop
│   ├── Makefile           ← build system
│   ├── test.src           ← sample source file
│   └── README.md          ← lexer-specific notes

```

---

## Stage 1 — Lexical Analyzer 

**Status: complete and working.**

The lexical analyzer reads source code from `stdin` character by character and emits a stream of tokens, each identified by a type ID and its lexeme text.

### How it works

The tokenizer is implemented as a **Deterministic Finite Automaton (DFA)** with 27 states. The three modules divide responsibilities cleanly:

#### `symbol_table.asm`
Contains all static data for the compiler. It exports:
- Token ID constants (`TK_INT = 1`, `TK_FLOAT = 2`, ... `TK_ERROR = 37`)
- Keyword strings (`kw_int`, `kw_while`, etc.) used for reserved word lookup
- Token name strings (`"TK_INT         "`, padded for aligned output)
- A pointer table (`tk_name_table`) indexed by token ID, used to print token names

This module has no code — only `.data` section. Any future compiler stage that needs token data imports from here.

#### `lexer.asm`
Implements the DFA. It exports `get_token`, `lexeme`, and `lexeme_len`. It imports keyword strings from `symbol_table.asm` via `extern`.

`get_token` works as follows:
1. **S0** — Skip whitespace (space, tab, `\n`, `\r`)
2. Inspect the first character to decide which DFA path to follow
3. Follow the appropriate state sequence to consume the full token
4. Return the token ID in `rax` and the token text in `lexeme[]`

Key implementation details:
- **Buffered I/O** — reads up to 4096 bytes at a time from `stdin` via `SYS_READ`, avoiding one syscall per character
- **1-character putback** — a single `putback` register lets the DFA "un-read" one character when it has consumed one too many (used by integer/float disambiguation and all two-character operators)
- **Tail-call for comments** — when a `/* */` comment is consumed, the function jumps directly back to `get_token` instead of returning, avoiding unnecessary stack frames
- **Keyword lookup** — identifiers are fully read first, then compared against the reserved word list using `compare_str`; if no match, classified as `TK_ID`
- **Two-character operators** — `==`, `!=`, `<=`, `>=`, `&&`, `||` are handled by reading a second character and pushing it back if it does not complete the operator

#### `main.asm`
Entry point (`_start`). Calls `get_token` in a loop, prints each token's name (via `tk_name_table`) and lexeme, and exits on `TK_EOF`.

### Token table (38 tokens)

| ID | Token          | Description                    |
|----|----------------|--------------------------------|
| 1  | `TK_INT`       | keyword `int`                  |
| 2  | `TK_FLOAT`     | keyword `float`                |
| 3  | `TK_BOOL`      | keyword `bool`                 |
| 4  | `TK_STRING`    | keyword `string`               |
| 5  | `TK_IF`        | keyword `if`                   |
| 6  | `TK_ELSE`      | keyword `else`                 |
| 7  | `TK_WHILE`     | keyword `while`                |
| 8  | `TK_FOR`       | keyword `for`                  |
| 9  | `TK_RETURN`    | keyword `return`               |
| 10 | `TK_TRUE`      | keyword `true`                 |
| 11 | `TK_FALSE`     | keyword `false`                |
| 12 | `TK_LIT_INT`   | integer literal: `42`          |
| 13 | `TK_LIT_FLOAT` | float literal: `3.14`          |
| 14 | `TK_LIT_STRING`| string literal: `"hello"`      |
| 15 | `TK_ID`        | identifier: `x`, `result`      |
| 16 | `TK_ASSIGN`    | `=`                            |
| 17 | `TK_PLUS`      | `+`                            |
| 18 | `TK_MINUS`     | `-`                            |
| 19 | `TK_STAR`      | `*`                            |
| 20 | `TK_SLASH`     | `/`                            |
| 21 | `TK_EQ`        | `==`                           |
| 22 | `TK_NEQ`       | `!=`                           |
| 23 | `TK_LT`        | `<`                            |
| 24 | `TK_GT`        | `>`                            |
| 25 | `TK_LTE`       | `<=`                           |
| 26 | `TK_GTE`       | `>=`                           |
| 27 | `TK_AND`       | `&&`                           |
| 28 | `TK_OR`        | `\|\|`                         |
| 29 | `TK_NOT`       | `!`                            |
| 30 | `TK_LPAREN`    | `(`                            |
| 31 | `TK_RPAREN`    | `)`                            |
| 32 | `TK_LBRACE`    | `{`                            |
| 33 | `TK_RBRACE`    | `}`                            |
| 34 | `TK_SEMICOLON` | `;`                            |
| 35 | `TK_COMMA`     | `,`                            |
| 36 | `TK_EOF`       | end of input                   |
| 37 | `TK_ERROR`     | unrecognized character         |

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
=== LEXICAL ANALYZER ===
TOKEN            LEXEME
─────────────────────────────
TK_INT           --> [int]
TK_ID            --> [x]
TK_SEMICOLON     --> [;]
TK_LIT_INT       --> [42]
TK_EQ            --> [==]
TK_LIT_FLOAT     --> [3.14]
...
TK_EOF           --> []
```

---

## Stage 2 — Syntax Analyzer 

**Status: not started.**

The parser consumes the token stream produced by the lexer and verifies that it conforms to the language grammar. It will be implemented as a **recursive descent parser** in x86-64 NASM as a new module `parser.asm`, importing `get_token` from `lexer.asm`.

Output: a **parse tree / AST** (Abstract Syntax Tree) represented as a node structure in memory.

The grammar will cover:
- Variable declarations: `int x;`
- Assignment statements: `x = expr;`
- Arithmetic and logical expressions with correct operator precedence
- `if / else` blocks
- `while` and `for` loops
- Function declarations and `return`

For the expression `posicion = inicial + velocidad * 60`, the parser produces:
```
        =
       / \
  posicion  +
           / \
       inicial  *
               / \
          velocidad 60
```

---

## Stage 3 — Semantic Analyzer 

**Status: not started.**

Walks the AST produced by the parser and enforces language rules that cannot be checked by grammar alone. Operates alongside the **symbol table**, which maps every identifier to its declared type, scope level, and memory location.

Key checks:
- Variables declared before use
- Type compatibility in assignments and expressions (`int` + `float` requires implicit cast)
- Implicit type conversions — e.g. `inttofloat(60)` when an integer is used in a float context
- Correct return types for functions
- No duplicate declarations in the same scope

The symbol table at this stage looks like:

| # | Name      | Type  | Scope | ... |
|---|-----------|-------|-------|-----|
| 1 | posicion  | float | 0     | ... |
| 2 | inicial   | float | 0     | ... |
| 3 | velocidad | float | 0     | ... |

---

## Stage 4 — Intermediate Code Generator 

**Status: not started.**

Translates the semantically verified AST into **three-address code** (TAC), an architecture-independent intermediate representation. Each instruction has at most one operator and three operands (two sources, one destination).

For `posicion = inicial + velocidad * 60`:
```
t1 = inttofloat(60)
t2 = velocidad * t1
t3 = inicial + t2
posicion = t3
```

This representation is easy to optimize and easy to translate to any target architecture. It will be stored as a flat list of instruction structs in memory.

---

## Stage 5 — Code Optimizer 

**Status: not started.**

Transforms the intermediate code to produce a semantically equivalent but more efficient version. Operates entirely on the TAC representation, before final code generation.

For the example above, the optimizer detects that `inttofloat(60)` is a compile-time constant and folds it, reducing four instructions to two:
```
t1 = velocidad * 60.0
posicion = inicial + t1
```

Planned optimizations:
- **Constant folding** — evaluate constant expressions at compile time
- **Dead code elimination** — remove instructions whose results are never used
- **Redundant assignment elimination** — collapse unnecessary temporary variables

---

## Stage 6 — Code Generator 

**Status: not started.**

Translates the optimized intermediate code into real **x86-64 assembly**, which is then assembled with NASM and linked with `ld` into an executable binary.

For the optimized TAC above:
```asm
LDF  R2, velocidad
MULF R2, R2, #60.0
LDF  R1, inicial
ADDF R1, R1, R2
STF  posicion, R1
```

Responsibilities:
- Register allocation — decide which values live in registers vs. memory
- Instruction selection — map TAC operations to real x86-64 instructions
- Stack frame management — function call setup and teardown (`push rbp`, `sub rsp`, etc.)
- Emit a valid `.asm` file that NASM can assemble directly

---

## Requirements

- Debian Linux (or any x86-64 Linux)
- `nasm` — `sudo apt install nasm`
- `ld` — included in `binutils`, installed by default

---

## License

University project — all rights reserved.
