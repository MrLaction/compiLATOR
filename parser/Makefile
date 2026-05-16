ASM     = nasm
AFLAGS  = -f elf64
LD      = ld

LEXER_DIR = ../lexer

SRCS_LEXER  = $(LEXER_DIR)/symbol_table.asm \
              $(LEXER_DIR)/lexer.asm

SRCS_PARSER = strpool.asm \
              parser.asm \
              main.asm

OBJS_LEXER  = symbol_table.o lexer.o
OBJS_PARSER = strpool.o parser.o main.o

TARGET = parser

.PHONY: all run clean

all: $(TARGET)

# Assemble lexer modules (copy to local dir first to avoid path issues)
symbol_table.o: $(LEXER_DIR)/symbol_table.asm
	$(ASM) $(AFLAGS) $< -o $@

lexer.o: $(LEXER_DIR)/lexer.asm
	$(ASM) $(AFLAGS) $< -o $@

# Assemble parser modules
strpool.o: strpool.asm
	$(ASM) $(AFLAGS) $< -o $@

# parser.asm uses %include "ast.asm" — ast.asm must be in the same directory
parser.o: parser.asm ast.asm
	$(ASM) $(AFLAGS) $< -o $@

main.o: main.asm
	$(ASM) $(AFLAGS) $< -o $@

$(TARGET): $(OBJS_LEXER) $(OBJS_PARSER)
	$(LD) $^ -o $@

run: all
	./$(TARGET) < test.src

clean:
	rm -f *.o $(TARGET)
