# ============================================================
#  Makefile — BASE Language Lexical Analyzer
#
#  Modules:
#    symbol_table.asm  — token data and keyword strings
#    lexer.asm         — DFA logic
#    main.asm          — entry point and output
#
#  Usage:
#    make          → build the lexer binary
#    make run      → build and run with test.src
#    make clean    → remove build artifacts
# ============================================================

ASM    = nasm
AFLAGS = -f elf64
LD     = ld
TARGET = lexer
SRC    = test.src

OBJECTS = symbol_table.o lexer.o main.o

# ── Default target ──────────────────────────────────────────
all: $(TARGET)

# ── Link all object files ───────────────────────────────────
$(TARGET): $(OBJECTS)
	$(LD) $(OBJECTS) -o $(TARGET)

# ── Assemble each module ────────────────────────────────────
symbol_table.o: symbol_table.asm
	$(ASM) $(AFLAGS) symbol_table.asm -o symbol_table.o

lexer.o: lexer.asm
	$(ASM) $(AFLAGS) lexer.asm -o lexer.o

main.o: main.asm
	$(ASM) $(AFLAGS) main.asm -o main.o

# ── Run with the test file ──────────────────────────────────
run: all
	./$(TARGET) < $(SRC)

# ── Remove build artifacts ──────────────────────────────────
clean:
	rm -f $(OBJECTS) $(TARGET)

.PHONY: all run clean
