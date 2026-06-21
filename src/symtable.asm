;symtable.asm — stage 3 symbol table for LATOR bindings
;
;Open-addressing hash table (djb2, linear probing, 256 entries) mapping
;binding names to (type, line). sym_insert reports redeclaration;
;sym_lookup resolves identifiers during the semantic walk.
;
;Exports: sym_insert, sym_lookup, sym_hash, SYM_* type constants.

default abs

global SYM_UNKNOWN, SYM_INT, SYM_FLOAT, SYM_BOOL, SYM_STRING, SYM_COLLECTION

%include "symbols.inc"

section .bss
    sym_table resb SYM_CAPACITY * SYM_ENTRY_SIZE

section .text

global sym_insert
global sym_lookup
global sym_hash

;
;sym_hash(rdi = name_ptr) -> rax = index [0, 255]
;djb2: hash = ((hash * 33) ^ byte) mod 256
;
sym_hash:
    mov  rax, 5381          ;djb2 seed
    xor  rcx, rcx
.loop:
    movzx rcx, byte [rdi]
    test rcx, rcx
    jz   .done
    imul rax, rax, 33
    xor  rax, rcx
    inc  rdi
    jmp  .loop
.done:
    and  rax, 0xFF          ;mod 256
    ret

;
;sym_lookup(rdi = name_ptr) -> rax = entry pointer, or 0 if not found
;
sym_lookup:
    push rbx
    push r12
    push r13
    push r14

    mov  r12, rdi           ;r12 = name_ptr
    call sym_hash           ;rax = starting bucket index
    mov  rbx, rax           ;rbx = current index
    xor  r14, r14           ;probe counter (full-table guard)

.probe:
    ;compute entry pointer
    imul rax, rbx, SYM_ENTRY_SIZE
    lea  r13, [rel sym_table]
    add  r13, rax           ;r13 = entry pointer

    ;empty slot: name not in table
    cmp  qword [r13 + SYM_NAME], 0
    je   .not_found

    ;compare names
    mov  rdi, [r13 + SYM_NAME]
    mov  rsi, r12
    call str_eq
    jc   .found             ;CF=1: match

    ;linear probe: advance to next bucket
    inc  rbx
    and  rbx, 0xFF          ;wrap at 256
    inc  r14
    cmp  r14, SYM_CAPACITY  ;looped the whole table, key absent: stop
    jae  .not_found
    jmp  .probe

.found:
    mov  rax, r13
    jmp  .ret
.not_found:
    xor  rax, rax
.ret:
    pop  r14
    pop  r13
    pop  r12
    pop  rbx
    ret

;
;sym_insert(rdi = name_ptr, rsi = type, rdx = line)
;-> rax: 0 = inserted OK, 1 = already declared (redeclaration)
;
sym_insert:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov  r12, rdi           ;r12 = name_ptr
    mov  r13, rsi           ;r13 = type
    mov  r14, rdx           ;r14 = line

    ;check for existing entry
    mov  rdi, r12
    call sym_lookup
    test rax, rax
    jnz  .redecl            ;already exists

    ;find empty slot via linear probe
    mov  rdi, r12
    call sym_hash
    mov  rbx, rax
    xor  rcx, rcx           ;probe counter (full-table guard)

.find_empty:
    imul rax, rbx, SYM_ENTRY_SIZE
    lea  r15, [rel sym_table]
    add  r15, rax           ;r15 = candidate entry

    cmp  qword [r15 + SYM_NAME], 0
    je   .insert            ;empty slot found

    inc  rbx
    and  rbx, 0xFF
    inc  rcx
    cmp  rcx, SYM_CAPACITY  ;table full: no slot to insert into
    jae  .table_full
    jmp  .find_empty

.insert:
    mov  qword [r15 + SYM_NAME], r12
    mov  qword [r15 + SYM_TYPE], r13
    mov  qword [r15 + SYM_LINE], r14
    xor  rax, rax           ;return 0 = OK
    jmp  .ret

.redecl:
    mov  rax, 1             ;return 1 = redeclaration
    jmp  .ret

.table_full:
    mov  rax, 60            ;SYS_EXIT
    mov  rdi, 96            ;exit 96 = symbol table full
    syscall

.ret:
    pop  r15
    pop  r14
    pop  r13
    pop  r12
    pop  rbx
    ret

;
;str_eq(rdi = a, rsi = b) -> CF=1 if equal, CF=0 if not
;Uses scratch dl, not bl: sym_lookup keeps its probe index in rbx across
;the call, and writing bl would corrupt it into an infinite probe loop.
str_eq:
    push rcx
    xor  rcx, rcx
.loop:
    mov  al, [rdi + rcx]
    mov  dl, [rsi + rcx]
    cmp  al, dl
    jne  .no
    test al, al
    jz   .yes
    inc  rcx
    jmp  .loop
.yes:
    stc
    pop  rcx
    ret
.no:
    clc
    pop  rcx
    ret