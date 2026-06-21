;symbols.inc — symbol-table type tags and entry layout, shared by the
;semantic stage and the symbol table. Include-guarded for safe double inclusion.

%ifndef SYMBOLS_INC
%define SYMBOLS_INC

SYM_UNKNOWN    equ 0
SYM_INT        equ 1
SYM_FLOAT      equ 2
SYM_BOOL       equ 3
SYM_STRING     equ 4
SYM_COLLECTION equ 5

SYM_NAME       equ 0
SYM_TYPE       equ 8
SYM_LINE       equ 16
SYM_ENTRY_SIZE equ 32
SYM_CAPACITY   equ 256

%endif ; SYMBOLS_INC
