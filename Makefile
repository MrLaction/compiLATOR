# compiLATOR — root build
# Layout: src/*.asm -> build/*.o -> bin/{compi,lexer}

ASM    = nasm
AFLAGS = -f elf64 -i src/
LD     = ld

BUILD = build
BIN   = bin

COMPI_OBJS = $(BUILD)/symbol_table.o $(BUILD)/lexer.o $(BUILD)/strpool.o \
             $(BUILD)/parser.o $(BUILD)/symtable.o $(BUILD)/semantic.o \
             $(BUILD)/compi_main.o

LEXER_OBJS = $(BUILD)/symbol_table.o $(BUILD)/lexer.o $(BUILD)/lexer_main.o

.PHONY: all test run clean

all: $(BIN)/compi $(BIN)/lexer

$(BUILD) $(BIN):
	mkdir -p $@

# parser.asm %includes ast.asm; -i src/ resolves it
$(BUILD)/%.o: src/%.asm | $(BUILD)
	$(ASM) $(AFLAGS) $< -o $@

$(BUILD)/parser.o: src/parser.asm src/ast.asm | $(BUILD)
	$(ASM) $(AFLAGS) $< -o $@

$(BIN)/compi: $(COMPI_OBJS) | $(BIN)
	$(LD) $^ -o $@

$(BIN)/lexer: $(LEXER_OBJS) | $(BIN)
	$(LD) $^ -o $@

test: all
	bash tests/run_tests.sh

run: all
	./$(BIN)/compi tests/positive/basics.lator

clean:
	rm -rf $(BUILD) $(BIN)
