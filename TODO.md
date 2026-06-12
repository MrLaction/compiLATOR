# compiLATOR — Master plan to v1.0

All design decisions are frozen (2026-06-11). This document is the single
source of truth for finishing the project. Work strictly top to bottom.
Estimated total: 9–11 weeks at full dedication.

---

## Frozen decisions

| ID | Decision |
|----|----------|
| D1 | Types: int64, float64 (IEEE 754), bool, string. Collections = typed record tables. |
| D2 | Data source: external CSV. Convention `users` → `./data/users.csv`. Header row = field names. Column types inferred from the first data row (all digits → int; digits + one dot → float; `true`/`false` → bool; else string). Schema is resolved at COMPILE time (compiler reads header + first row of every referenced CSV), so all expressions are statically typed; the binary embeds the schema and revalidates at load (mismatch = exit 3). SPEC §3.1. |
| D3 | Output: every top-level binding prints to stdout. Scalar: `name = value`. Collection: header line + one row per record, fields pipe-separated. Deterministic → golden-file testable. |
| D4 | `path from A to B`: CUT from v1.0. Grammar still parses it; semantic stage emits `error: 'path' expressions are not supported in v1.0` (exit 2). `from`/`to` remain reserved. |
| D5 | `every element <= next`: sortedness predicate over a single-column numeric collection (the filter source). Non-numeric or multi-column source = semantic error. |
| D6 | Numeric promotion int→float in mixed arithmetic and comparisons (static and runtime). Everything else strict: `string + int` = error; bool only in logical context; strings compare with `==`/`!=` only. Int `/` truncates toward zero; `%` ints only; runtime division by zero = runtime error (exit 3). |
| D7 | Codegen target: emit NASM source, then fork/exec `nasm` + `ld` from `compi` → standalone native executable linked against `runtime.o`. |
| D8 | Diagnostics: multi-error per run; panic-mode recovery synchronizes at `TK_NEWLINE`; messages name found and expected tokens. |
| D9 | Optimizer scope: constant folding (int+float), algebraic identities, boolean simplification, dead-binding elimination. Docs: markdown source in `docs/`, exported PDF per stage. |

Final CLI: `compi file.lator [-s] [-v] [-i] [-O] [-o prog]`
Exit codes: 0 OK · 1 syntax · 2 semantic · 3 runtime (compiled program) · 97 IR pool · 98 strpool · 99 AST pool.

---

## Phase 0 — SPEC.md (2–3 days)

- [x] Write `SPEC.md`: grammar (with the new parenthesized-condition production), type system + promotion table per D6, CSV format + inference rules per D2, output format per D3 with exact examples, aggregate semantics (`sum` over int col → int, float col → float; `min`/`max` preserve column type; `of coll.field` selects column), `in` list homogeneity rule, `every` semantics per D5, exit codes, fixed capacities (see Phase 4 arenas).
- [x] Update README examples and `test.lator`: the `path` example moves to a "reserved for v1.1" note (D4 invalidates it as a working example).
- **Done when:** every construct in the README has defined static and runtime semantics traceable to SPEC.md.

## Phase 1 — Consolidate Stages 1–3 (1.5–2 weeks)

Defects below were reproduced against the current build. Write the failing test first, then fix.

- [x] **T1 — Test harness.** Three tiers: `tests/positive` + `tests/negative` (regression floor, must stay green), `tests/xfail` (SPEC-mandated, currently failing; one test per B-item; an XPASS means a fix landed and the test must be promoted). Sidecars: `.exit` (required), `.out` (exact stdout), `.err` (stderr substrings). Custom `.sh` cases for CLI checks; lexer output golden. `make test` at repo root. CSV fixtures in `tests/data/` (forward-compatible with Phase 2 schema resolution). Status: 16 pass / 10 xfail / 0 fail.
- [x] **B1 — DONE. Line tracking lives in the lexer.** `nl_count` net of putbacks; per-token `tok_line` (NEWLINE = line it terminates, EOF = cursor line); parser's `cur_line` deleted, all sites read `tok_line`. Incident: first version clobbered AL with the stamp and broke all tokenization — 12 suite failures; fixed with push/pop rax. Test promoted to `negative/b1_line_number`; line numbers pinned across the negative tier.
- [ ] **B2 — Unified expression grammar.** Replace the split condition/arith grammar with one precedence ladder (or < and < not < rel < add < mul < unary < primary, SPEC §2): `(` always opens `expr`; ill-typed forms like `(a > b) + 1` are rejected by B3's type checker, not the grammar. Comparison is non-associative. Net effect: parenthesized conditions work and parser.asm shrinks. Rewrite grammar.md to match SPEC; delete the obsolete cond_* productions.
- [ ] **B3 — BINOP type checking.** Recursive operand inference; result type = promoted type (int⊕float → float); illegal combinations (string/bool in arithmetic) = semantic error. Replaces the current "type of left operand" logic.
- [ ] **B4 — Undeclared identifiers.** Per SPEC: a bare identifier in scalar arithmetic context must be declared; a filter/aggregate *source* identifier may be external (collection). Wire up the existing dead `err_not_defined`. Delete the false claim in semantic.asm header if any case remains unchecked.
- [ ] **B5 — Enforce `every element <= next`** lexemes (`element`, `next`) via the already-declared `kw_element`/`kw_next` strings; arbitrary IDs = syntax error.
- [ ] **B6 — String pool.** Intern only `TK_ID` / `TK_LIT_*` lexemes (operators and newlines never). Optional: dedup identifiers reusing the djb2 hash.
- [ ] **B7 — Implement `-v` AST dump.** Indented tree printer with node-type names, line numbers, values. This is the Phase 2 debugging instrument — non-negotiable before IR work.
- [ ] **B8 — Multi-error diagnostics (D8).** `syntax_error` prints found token name (reuse `tk_name_table`) + expected set, then skips to `TK_NEWLINE` and resumes; error counter; exit 1 if count > 0 after parse. Semantic stage: report-and-continue where safe (redeclaration, mismatch), exit 2 at end.
- [ ] **B9 — Lexical errors.** Distinct message with offending character and line; decide `1.` (trailing dot) per SPEC — recommended: reject, require digit after dot.
- [ ] **B10 — `path` reserved error (D4).** Semantic stage rejects NODE_RANGE with `error: 'path' expressions are not supported in v1.0` (exit 2); negative test in `tests/`.
- [ ] **R1 — Repo hygiene.** Untrack `*.o` and binaries; delete stale `parser/parser`; extend `.gitignore`; extract triplicated `TK_*`/`NODE_*` constants into `tokens.inc` / `nodes.inc` (single source, `%include` everywhere).
- [x] **R2 — Restructure (done out of order, absorbed).** Files moved to `src/` with renamed mains (`lexer_main.asm`, `compi_main.asm`), `docs/`, `data/`; `default abs` added per file to silence NASM's implicit-ABS deprecation. Completed during T1: root Makefile (`build/` objs, `bin/` binaries, `-i src/` for `%include`), rewritten `.gitignore`, three `lea` in symtable.asm made explicitly RIP-relative.
- **Done when:** `make test` green; each B-item has a test that failed before the fix; README claims match observed behavior.

## Phase 2 — Stage 4: Intermediate Representation (2 weeks)

- [ ] **IR design (`docs/stage4-ir.md`).** Linear, typed, three-address over virtual temps. Instruction set:
      `LOADC t,name` · `FILTER t2,t1,Lpred` (predicate block, per-row eval) · `FIELD v,t,col` ·
      `AGG s,{SUM|MIN|MAX},t[,col]` · `SORTCHK s,t` · `INLIST s,v,[consts]` ·
      `CONSTI/CONSTF/CONSTS/CONSTB` · `ADD/SUB/MUL/DIV/MOD` (typed) · `CVTIF` (promotion) ·
      `CMP{EQ,NE,LT,GT,LE,GE}` · `AND/OR/NOT` · `BIND name,v|t` (binds + prints per D3).
- [ ] **csv_schema.asm** — compile-time schema resolver per SPEC §3.1/§4.2: open `./data/<name>.csv`, parse header + first data row, classify column types, expose `schema_resolve(name) → desc` to the semantic stage (which gains column-aware type checking: unknown column, ambiguous aggregate, predicate name resolution per SPEC §3.5). Written to be link-shared with the Phase 4 runtime loader.
- [ ] **ir.asm** — fixed instruction arena (ast.asm pattern), exit 97 on exhaustion.
- [ ] **irgen.asm** — AST→IR walker (mirror `sem_walk` dispatch). Insert `CVTIF` wherever D6 promotion applies, so the optimizer and codegen never re-derive types.
- [ ] **irdump.asm** — textual printer; `compi -i` dumps IR after generation.
- [ ] Golden IR dumps in `tests/ir/` for every construct.
- [ ] **Doc:** `docs/stage4-ir.md` → exported `Stage4-IR.pdf` (D9 pipeline).
- **Done when:** every legal program dumps stable, typed IR; goldens green.

## Phase 3 — Stage 5: Optimizer (1–1.5 weeks)

Pass order, each idempotent, each evidenced by before/after `-i -O` dumps:

- [ ] P1 constant folding: int and float arithmetic, comparisons of constants, `CVTIF` of constants.
- [ ] P2 algebraic identities: `x*1`, `1*x`, `x+0`, `x-0`, `x*0`, `x/1`.
- [ ] P3 boolean simplification: `true AND p → p`, `false AND p → false`, `true OR p → true`, `false OR p → p`, `NOT NOT p → p`, constant `CMP` inside predicates → fold the `FILTER` to copy-all or empty.
- [ ] P4 dead-binding elimination — valid only because D3 defines observability: a `BIND` is live (it prints). Therefore P4 targets *temps* unused after folding, not bindings. Rename task: dead-temp elimination.
- [ ] `-O` flag; tests asserting exact optimized IR.
- [ ] **Doc:** `docs/stage5-optimizer.md` → PDF.
- **Done when:** each pass has at least 2 tests proving the transformation and 1 proving it does not misfire.

## Phase 4 — Stage 6: Runtime + Codegen (4–5 weeks — the iceberg)

Write the runtime FIRST against this frozen ABI; codegen emits calls into it.

**Runtime (`src/runtime.asm` → `runtime.o`):**
- [ ] Memory model: row-major cell storage, 8 bytes/cell uniformly (int64 / double / 0|1 / ptr to interned string). Shared static arenas: 16 collections max, 16 cols max, 4 MB row arena, 256 KB runtime string pool. Address = base + (row*ncols + col)*8. Collection descriptor: {name, ncols, nrows, col_names[], col_types[], base}.
- [ ] CSV loader `rt_load(name) → desc`: open `./data/<name>.csv`, parse header, infer types from first data row (D2), parse all rows, validate every cell against inferred type (mismatch = exit 3 with row/col in message).
- [ ] **Named icebergs — string↔number in pure asm:**
  - [ ] `rt_atoi`, `rt_atof` (string→int64/double; atof via integer mantissa + scale by power of 10, `cvtsi2sd` + `divsd`).
  - [ ] `rt_itoa`, `rt_ftoa` (double→string: fixed 6 decimals via scale-and-round to int, trim trailing zeros). Full Grisu/Ryu is explicitly out of scope.
- [ ] Printers per D3: `rt_print_bind_int/float/bool/str`, `rt_print_table(desc)`.
- [ ] `rt_strcmp`, `rt_die(code, msg)` (used for div-by-zero, missing CSV, type mismatch).
- [ ] Float path is SSE2 (`movsd/addsd/mulsd/divsd/comisd`) — first floating-point code in the project; everything existing is GPR-only.

**Codegen (`src/codegen.asm`):**
- [ ] Convention doc `docs/codegen-abi.md`: every IR temp → stack slot `[rbp-8k]`; values 8 bytes uniform; floats touch xmm0/xmm1 only at op sites; rbx = row index, r12 = source desc, r13 = dest desc inside FILTER loops. Naive and correct beats clever.
- [ ] Lowering: `FILTER` → row loop + inline predicate + materialize selected rows into a result arena; `AGG` → accumulate loop (int add / `addsd`; min/max via `cmp`+`cmov` / `comisd`+branch); `SORTCHK` → pairwise loop; `INLIST` → unrolled compares; scalar ops direct.
- [ ] Emitter produces complete NASM text: `_start`, `rt_*` externs, data section with string constants.
- [ ] **Driver:** `compi prog.lator -o prog` → write `prog.s`, fork/exec `nasm -f elf64`, fork/exec `ld prog.o runtime.o -o prog`, propagate failures.
- [ ] **End-to-end tests:** `tests/data/*.csv` fixtures; compile and run every README example (minus `path`); diff stdout vs goldens; runtime-error tests (bad CSV, div by zero).
- [ ] **Doc:** `docs/stage6-codegen.md` → PDF.
- **Done when:** all e2e green; a fresh clone with only `nasm`+`ld` goes from `.lator` + CSVs to a working native binary.

## Phase 5 — Release (3–4 days)

- [ ] README rewrite: 6-stage pipeline diagram, SPEC.md linked, honest "Limitations" section (`path` reserved, fixed capacities, float printing precision).
- [ ] Export final PDF set (stages 4–6) into the existing collection.
- [ ] CI: GitHub Actions — ubuntu-latest, `apt-get install nasm`, `make`, `make test` (unit + e2e).
- [ ] Tag `v1.0.0`.

---

## Schedule (full dedication)

| Weeks | Work |
|-------|------|
| 1 | Phase 0 + T1 + B1–B5 |
| 2 | B6–B9, R1–R2 — Phase 1 closed |
| 3–4 | Phase 2 (IR + dump + goldens + doc) |
| 5 | Phase 3 (optimizer) + buffer |
| 6 | Runtime: arenas, CSV loader, printers |
| 7 | Runtime: atoi/atof/itoa/ftoa + SSE2 float path |
| 8 | Codegen: scalars, BIND, FILTER loops |
| 9 | Codegen: AGG/SORTCHK/INLIST, driver, e2e suite |
| 10 | Phase 5 + slack |

## Definition of done — v1.0

`make test` green including e2e · every README example (minus `path`) compiles to a native executable whose output matches goldens · SPEC.md complete · stages 4–6 documented in md+PDF · repo free of tracked artifacts · CI green · tag `v1.0.0`.
