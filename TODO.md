# compiLATOR — Master plan to v1.0

Design decisions frozen 2026-06-11 (see "Frozen decisions"). This document is
the single source of truth for finishing the project. It supersedes the prior
TODO, which had drifted out of sync with the repo (it still listed B2–B5 as
pending after they had shipped). Work strictly top to bottom within each phase;
the phase order itself is by unblock priority, not by bug number.

Realistic remaining estimate: 8–10 weeks at full dedication. The Phase 4
runtime+codegen iceberg is the bulk and is irreducible — no reordering shrinks
it.

---

## Current state (verified 2026-06-20, commit 55f3408)

Build is green: `make test` → 41 passed / 0 failed / 1 xfail / 0 xpass.
The single remaining xfail is `b8_multi_error` (deferred — see Phase 1).

| Stage | Status |
|-------|--------|
| Phase 0 — SPEC.md | DONE |
| Phase 1 — Consolidate stages 1–3 | T1, B1, B2, B3, B4, B5, B9, B10, R2 done · B6, B7, R1 pending · B8 deferred |
| Phase 2 — IR | not started |
| Phase 3 — Optimizer | not started |
| Phase 4 — Runtime + Codegen | not started |
| Phase 5 — Release | not started |

---

## Frozen decisions

| ID | Decision |
|----|----------|
| D1 | Types: int64, float64 (IEEE 754), bool, string. Collections = typed record tables. |
| D2 | Data source: external CSV. Convention `users` -> `./data/users.csv`. Header row = field names. Column types inferred from the first data row (all digits -> int; digits + one dot -> float; `true`/`false` -> bool; else string). Schema resolved at COMPILE time; binary embeds the schema and revalidates at load (mismatch = exit 3). SPEC 3.1. |
| D3 | Output: every top-level binding prints to stdout. Scalar: `name = value`. Collection: header line + one row per record, fields pipe-separated. Deterministic -> golden-file testable. |
| D4 | `path from A to B`: CUT from v1.0. Grammar still parses it; semantic stage emits `'path' is not supported in v1.0` (exit 2). `from`/`to` remain reserved. DONE (B10). |
| D5 | `every element <= next`: sortedness predicate over a single-column numeric collection. Non-numeric or multi-column source = semantic error. |
| D6 | Numeric promotion int->float in mixed arithmetic and comparisons (static and runtime). Else strict: `string + int` = error; bool only in logical context; strings compare with `==`/`!=` only. Int `/` truncates toward zero; `%` ints only; runtime div-by-zero = exit 3. |
| D7 | Codegen target: emit NASM source, then fork/exec `nasm` + `ld` from `compi` -> standalone native executable linked against `runtime.o`. |
| D8 | Diagnostics: multi-error per run; panic-mode recovery synchronizes at `TK_NEWLINE`; messages name found and expected tokens. (Implementation deferred — see Phase 1 / B8.) |
| D9 | Optimizer scope: constant folding (int+float), algebraic identities, boolean simplification, dead-temp elimination. Docs: markdown source in `docs/`, exported PDF per stage. |

Final CLI: `compi file.lator [-s] [-v] [-i] [-O] [-o prog]`
Exit codes: 0 OK · 1 syntax · 2 semantic · 3 runtime (compiled program) · 97 IR pool · 98 strpool · 99 AST pool.

---

## Phase 1 — Consolidate stages 1–3  (remaining: ~1 week)

Ordered by unblock value, not bug number. Write the failing test first, then fix.
Each fix: `make test` before and after; an XPASS means a fix landed and the
test must be promoted from `xfail/` to `negative/` or `positive/`.

- [x] **T1 — Test harness.** Three tiers (`positive`, `negative`, `xfail`), sidecars `.exit`/`.out`/`.err`, CLI `.sh` cases, lexer golden, CSV fixtures in `tests/data/`. `make test` at repo root.
- [x] **B1 — Line tracking in the lexer.** Per-token `tok_line`; parser `cur_line` deleted.
- [x] **B2 — Unified expression grammar.** Single precedence ladder (or < and < not < rel < add < mul < unary < primary). `(` always opens `expr`; comparison non-associative. parser.asm shrank; grammar.md rewritten.
- [x] **B3 — BINOP type checking.** Recursive operand inference, int->float promotion, illegal combinations rejected. (Also fixed a latent parser bug: bool-literal branch clobbered the node pointer across `advance`.)
- [x] **B4 — Undeclared identifiers.** Second pass over scalar operands only; forward references allowed; predicate identifiers deferred to Phase 2 schema. Dead `err_not_defined` activated.
- [x] **B5 — Enforce `every element <= next` lexemes** via `str_eq` against `kw_element`/`kw_next`.
- [x] **B9 — Lexical errors.** Reject trailing-dot float (`1.`); parser emits a distinct lexical diagnostic naming the offending character.
- [x] **B10 — `path` reserved error (D4).** Semantic stage rejects `NODE_RANGE` with exit 2 and `'path' is not supported in v1.0`; test promoted to `negative/`. **DONE 2026-06-20.**
- [ ] **B6 — String pool.** *Capacity bug, real.* `advance` currently interns EVERY token (operators and newlines included) into a fixed 64 KB pool with no dedup, so programs of ~1.5–2k lines die with exit 98. Fix: intern only `TK_ID` / `TK_LIT_*` lexemes; operators and newlines never. Optional: dedup identifiers via the existing djb2 hash. Touches the `intern_str` call site in `advance` (parser.asm) and possibly `intern_str` (strpool.asm). Add a test that interning is skipped for operator-heavy input (compile a large generated program; assert exit != 98).
- [ ] **B7 — Implement `-v` AST dump.** Indented tree printer: node-type names, line numbers, values. *Non-negotiable before any IR work* — it is the instrument used to validate the Phase 2 AST->IR walker. Activate the `-v` flag that is currently documented but inert in compi_main.asm. New file `src/astdump.asm` (or a section appended to parser.asm), dispatch mirroring `sem_walk`. Golden dumps in `tests/ast/` for a representative program.
- [ ] **R1 — Repo hygiene + constant extraction.** Extract the triplicated `TK_*` / `NODE_*` / `SYM_*` constants into `src/tokens.inc` / `src/nodes.inc` and `%include` them everywhere (parser.asm, semantic.asm, symbol_table.asm currently each carry their own copy — a desync here is a silent-bug source, exactly the class that cost an hour in B3). Confirm `.gitignore` covers `build/`, `bin/`, `*.o`. *Do this before Phase 2* — the IR needs the same constants and a fourth hand-maintained copy is not acceptable.
- [~] **B8 — Multi-error diagnostics (D8). DEFERRED to post-v1.0.** This is the only Phase 1 item that unblocks nothing downstream (it is diagnostic quality, not capability) and is by far the most expensive. A prior session spent itself entirely on it without closing. Reporting one error per run is shippable for v1.0. When resumed: use error-flag propagation (NOT non-local jump — the stack-corruption failure mode is the worst to debug in asm). The known trap is that ~8 `syntax_error` call sites assume the routine never returns; once it returns they fall through into adjacent code (infinite loops). Each site needs an explicit early return with a null-node convention. Test `xfail/b8_multi_error` stays as the marker until then.
- [x] **R2 — Restructure to `src/` layout.** Done out of order; absorbed.
- **Phase 1 done when:** `make test` green; B6, B7, R1 closed; README claims match observed behavior. (B8 explicitly excluded by the deferral above.)

## Phase 2 — Stage 4: Intermediate Representation  (2 weeks)

- [ ] **IR design (`docs/stage4-ir.md`).** Linear, typed, three-address over virtual temps. Instruction set: `LOADC t,name` · `FILTER t2,t1,Lpred` · `FIELD v,t,col` · `AGG s,{SUM|MIN|MAX},t[,col]` · `SORTCHK s,t` · `INLIST s,v,[consts]` · `CONSTI/CONSTF/CONSTS/CONSTB` · `ADD/SUB/MUL/DIV/MOD` (typed) · `CVTIF` (promotion) · `CMP{EQ,NE,LT,GT,LE,GE}` · `AND/OR/NOT` · `BIND name,v|t` (binds + prints per D3).
- [ ] **csv_schema.asm** — compile-time schema resolver per SPEC 3.1/4.2: open `./data/<name>.csv`, parse header + first data row, classify column types, expose `schema_resolve(name) -> desc` to the semantic stage (which gains column-aware checking: unknown column, ambiguous aggregate, predicate name resolution per SPEC 3.5). Written to be link-shared with the Phase 4 runtime loader.
- [ ] **ir.asm** — fixed instruction arena (ast.asm pattern), exit 97 on exhaustion.
- [ ] **irgen.asm** — AST->IR walker (mirror `sem_walk` dispatch). Insert `CVTIF` wherever D6 promotion applies, so the optimizer and codegen never re-derive types.
- [ ] **irdump.asm** — textual printer; `compi -i` dumps IR after generation.
- [ ] Golden IR dumps in `tests/ir/` for every construct.
- [ ] **Doc:** `docs/stage4-ir.md` -> exported `Stage4-IR.pdf` (D9 pipeline).
- **Done when:** every legal program dumps stable, typed IR; goldens green.

## Phase 3 — Stage 5: Optimizer  (1–1.5 weeks)

Pass order, each idempotent, each evidenced by before/after `-i -O` dumps.

- [ ] P1 constant folding: int and float arithmetic, comparisons of constants, `CVTIF` of constants.
- [ ] P2 algebraic identities: `x*1`, `1*x`, `x+0`, `x-0`, `x*0`, `x/1`.
- [ ] P3 boolean simplification: `true AND p -> p`, `false AND p -> false`, `true OR p -> true`, `false OR p -> p`, `NOT NOT p -> p`, constant `CMP` inside a predicate -> fold the `FILTER` to copy-all or empty.
- [ ] P4 dead-temp elimination — a `BIND` is always live (it prints, per D3); this pass targets temps unused after folding.
- [ ] `-O` flag; tests asserting exact optimized IR.
- [ ] **Doc:** `docs/stage5-optimizer.md` -> PDF.
- **Done when:** each pass has >=2 tests proving the transform and 1 proving it does not misfire.

## Phase 4 — Stage 6: Runtime + Codegen  (4–5 weeks — the iceberg)

Write the runtime FIRST against the frozen ABI; codegen emits calls into it.

**Runtime (`src/runtime.asm` -> `runtime.o`):**
- [ ] Memory model: row-major cells, 8 bytes/cell uniform (int64 / double / 0|1 / ptr to interned string). Static arenas: 16 collections, 16 cols, 4 MB row arena, 256 KB runtime string pool. Address = base + (row*ncols + col)*8. Descriptor: {name, ncols, nrows, col_names[], col_types[], base}.
- [ ] CSV loader `rt_load(name) -> desc`: open `./data/<name>.csv`, parse header, infer types from first data row (D2), parse all rows, validate every cell (mismatch = exit 3 with row/col).
- [ ] **Iceberg — string<->number in pure asm:** `rt_atoi`, `rt_atof` (atof via integer mantissa + scale by power of 10, `cvtsi2sd` + `divsd`); `rt_itoa`, `rt_ftoa` (double->string, fixed 6 decimals, trim trailing zeros; full Grisu/Ryu out of scope).
- [ ] Printers per D3: `rt_print_bind_int/float/bool/str`, `rt_print_table(desc)`.
- [ ] `rt_strcmp`, `rt_die(code, msg)`.
- [ ] Float path is SSE2 (`movsd/addsd/mulsd/divsd/comisd`) — first floating-point code in the project; everything existing is GPR-only.

**Codegen (`src/codegen.asm`):**
- [ ] Convention doc `docs/codegen-abi.md`: every IR temp -> stack slot `[rbp-8k]`; values 8 bytes uniform; floats touch xmm0/xmm1 only at op sites; rbx = row index, r12 = source desc, r13 = dest desc inside FILTER loops.
- [ ] Lowering: `FILTER` -> row loop + inline predicate + materialize into result arena; `AGG` -> accumulate loop; `SORTCHK` -> pairwise loop; `INLIST` -> unrolled compares; scalar ops direct.
- [ ] Emitter produces complete NASM text: `_start`, `rt_*` externs, data section with string constants.
- [ ] **Driver:** `compi prog.lator -o prog` -> write `prog.s`, fork/exec `nasm -f elf64`, fork/exec `ld prog.o runtime.o -o prog`, propagate failures.
- [ ] **End-to-end tests:** compile and run every README example (minus `path`); diff stdout vs goldens; runtime-error tests (bad CSV, div by zero).
- [ ] **Doc:** `docs/stage6-codegen.md` -> PDF.
- **Done when:** all e2e green; a fresh clone with only `nasm`+`ld` goes from `.lator` + CSVs to a working native binary.

## Phase 5 — Release  (3–4 days)

- [ ] README rewrite: 6-stage pipeline diagram, SPEC.md linked, honest "Limitations" (`path` reserved, fixed capacities, float precision, single-error diagnostics if B8 still deferred).
- [ ] Export final PDF set (stages 4–6) into the existing collection.
- [ ] CI: GitHub Actions — ubuntu-latest, `apt-get install nasm`, `make`, `make test`.
- [ ] Tag `v1.0.0`.
- [ ] (Optional, post-tag) Normalize residual Spanish comments in parser.asm to English, and resume B8. Each in its own commit.

---

## Schedule (full dedication, from current state)

| Week | Work |
|------|------|
| 1 | B6, B7, R1 — Phase 1 closed |
| 2–3 | Phase 2 (IR + schema resolver + dump + goldens + doc) |
| 4 | Phase 3 (optimizer) + buffer |
| 5 | Runtime: arenas, CSV loader, printers |
| 6 | Runtime: atoi/atof/itoa/ftoa + SSE2 float path |
| 7 | Codegen: scalars, BIND, FILTER loops |
| 8 | Codegen: AGG/SORTCHK/INLIST, driver, e2e suite |
| 9 | Phase 5 + slack |

## Definition of done — v1.0

`make test` green including e2e · every README example (minus `path`) compiles to
a native executable whose output matches goldens · SPEC.md complete · stages 4–6
documented in md+PDF · repo free of tracked artifacts · CI green · tag `v1.0.0`.