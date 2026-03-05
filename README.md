# Lexical Analyzer — BASE Language v0.1

## Project structure

```
project/
├── docs/
│   ├── symbol_table.md     ← Full token table
│   └── afd.html            ← Interactive DFA diagram (open in browser)
└── lexer/
    ├── lexer.asm           ← Lexical analyzer — NASM x86-64
    ├── test.src            ← Sample source file
    └── README.md           ← This file
```

---

## Requirements (Debian)

```bash
sudo apt install nasm
```

---

## Build and run

```bash
# 1. Assemble
nasm -f elf64 lexer.asm -o lexer.o

# 2. Link
ld lexer.o -o lexer

# 3. Run with the test file
./lexer < test.src
```

---

## Expected output

```
=== LEXICAL ANALYZER ===
TOKEN            LEXEME
─────────────────────────────
TK_INT           --> [int]
TK_ID            --> [x]
TK_SEMICOLON     --> [;]
TK_FLOAT         --> [float]
TK_ID            --> [y]
...
TK_EOF           --> []
```

---

## Recognized tokens (38 total)

| Category        | Tokens                                          |
|-----------------|-------------------------------------------------|
| Data types      | int, float, bool, string                        |
| Control flow    | if, else, while, for, return                    |
| Bool literals   | true, false                                     |
| Literals        | TK_LIT_INT, TK_LIT_FLOAT, TK_LIT_STRING        |
| Identifiers     | TK_ID                                           |
| Operators       | = == != < > <= >= + - * / && \|\| !            |
| Delimiters      | ( ) { } ; ,                                     |
| Comments        | /* */ (discarded, no token emitted)             |
| Special         | TK_EOF, TK_ERROR                                |

---

## DFA overview

The automaton has **27 states**:

- **S0** — Initial state. Skips whitespace, classifies first character.
- **S1** — Reads `[a-zA-Z_][a-zA-Z0-9_]*`, then runs keyword lookup.
- **S2/S3/S4** — Reads `[0-9]+`; switches to float path on `.`.
- **S5/S6** — Reads string literals `"..."`.
- **S7–S17** — Handles two-char operators: `==` `!=` `<=` `>=`.
- **S18/S19** — Recognizes `&&`.
- **S20/S21** — Recognizes `||`.
- **S22/S23/S24** — Consumes and discards `/* */` block comments.
- **S25** — Single-character symbols.
- **S26** — Lexical error state.

---

## Next steps

1. **Syntax analyzer** — Recursive descent parser in x86-64 asm
2. **Semantic analyzer** — Symbol table with type checking
3. **Code generation** — Emit x86-64 directly