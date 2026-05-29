ASM    = nasm
AFLAGS = -f elf64
LD     = ld

LEXER_DIR = ../lexer

OBJS_LEXER   = symbol_table.o lexer.o
OBJS_PARSER  = strpool.o parser.o symtable.o semantic.o main.o

TARGET = compi

.PHONY: all run clean install

all: $(TARGET)

symbol_table.o: $(LEXER_DIR)/symbol_table.asm
	$(ASM) $(AFLAGS) $< -o $@

lexer.o: $(LEXER_DIR)/lexer.asm
	$(ASM) $(AFLAGS) $< -o $@

strpool.o: strpool.asm
	$(ASM) $(AFLAGS) $< -o $@

parser.o: parser.asm ast.asm
	$(ASM) $(AFLAGS) $< -o $@

symtable.o: symtable.asm
	$(ASM) $(AFLAGS) $< -o $@

semantic.o: semantic.asm
	$(ASM) $(AFLAGS) $< -o $@

main.o: main.asm
	$(ASM) $(AFLAGS) $< -o $@

$(TARGET): $(OBJS_LEXER) $(OBJS_PARSER)
	$(LD) $^ -o $@

run: all
	./$(TARGET) test.lator

install: all
	cp $(TARGET) /usr/local/bin/compi

clean:
	rm -f *.o $(TARGET)