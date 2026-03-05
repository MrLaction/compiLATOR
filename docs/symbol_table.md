# Symbol Table — BASE Language v0.1

## Token Categories

| ID | Token          | Category         | Lexeme(s)                        |
|----|----------------|------------------|----------------------------------|
| 1  | TK_INT         | Data type        | `int`                            |
| 2  | TK_FLOAT       | Data type        | `float`                          |
| 3  | TK_BOOL        | Data type        | `bool`                           |
| 4  | TK_STRING      | Data type        | `string`                         |
| 5  | TK_IF          | Control          | `if`                             |
| 6  | TK_ELSE        | Control          | `else`                           |
| 7  | TK_WHILE       | Control          | `while`                          |
| 8  | TK_FOR         | Control          | `for`                            |
| 9  | TK_RETURN      | Control          | `return`                         |
| 10 | TK_TRUE        | Bool literal     | `true`                           |
| 11 | TK_FALSE       | Bool literal     | `false`                          |
| 12 | TK_LIT_INT     | Integer literal  | `[0-9]+`                         |
| 13 | TK_LIT_FLOAT   | Float literal    | `[0-9]+.[0-9]+`                  |
| 14 | TK_LIT_STRING  | String literal   | `"..."` (double quotes)          |
| 15 | TK_ID          | Identifier       | `[a-zA-Z_][a-zA-Z0-9_]*`        |
| 16 | TK_ASSIGN      | Operator         | `=`                              |
| 17 | TK_PLUS        | Operator         | `+`                              |
| 18 | TK_MINUS       | Operator         | `-`                              |
| 19 | TK_STAR        | Operator         | `*`                              |
| 20 | TK_SLASH       | Operator         | `/`                              |
| 21 | TK_EQ          | Relational op.   | `==`                             |
| 22 | TK_NEQ         | Relational op.   | `!=`                             |
| 23 | TK_LT          | Relational op.   | `<`                              |
| 24 | TK_GT          | Relational op.   | `>`                              |
| 25 | TK_LTE         | Relational op.   | `<=`                             |
| 26 | TK_GTE         | Relational op.   | `>=`                             |
| 27 | TK_AND         | Logical op.      | `&&`                             |
| 28 | TK_OR          | Logical op.      | `\|\|`                           |
| 29 | TK_NOT         | Logical op.      | `!`                              |
| 30 | TK_LPAREN      | Delimiter        | `(`                              |
| 31 | TK_RPAREN      | Delimiter        | `)`                              |
| 32 | TK_LBRACE      | Delimiter        | `{`                              |
| 33 | TK_RBRACE      | Delimiter        | `}`                              |
| 34 | TK_SEMICOLON   | Delimiter        | `;`                              |
| 35 | TK_COMMA       | Delimiter        | `,`                              |
| 36 | TK_COMMENT     | Comment          | `/* ... */`                      |
| 37 | TK_EOF         | End of file      | EOF                              |
| 38 | TK_ERROR       | Lexical error    | any unrecognized character       |

---

## Reserved Words
(Identifiers reclassified by the lexer after reading them)

```
int  float  bool  string  if  else  while  for  return  true  false
```

---

## Priority Rules

1. Float before integer: `1.5` → TK_LIT_FLOAT, not TK_LIT_INT + dot
2. Double operators before single: `==` before `=`, `<=` before `<`
3. Reserved words before identifiers
4. Comments are discarded (no token emitted)
5. Whitespace, tabs and newlines are ignored

---

## Valid program example

```
int x;
float y;
x = 5;
y = 3.14;

/* this is a comment */

if (x == 5) {
    y = y + 1.0;
}

while (x > 0) {
    x = x - 1;
}
```