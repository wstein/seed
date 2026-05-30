grammar Calc;

// Exercises precedence-climbing with a *right-associative* operator
// (`<assoc=right>` on `^`), unary minus, and several precedence levels —
// none of which the left-associative Expr fixture covers.

prog : expr EOF ;

expr : <assoc=right> expr '^' expr   # Pow
     | ('-' | '+') expr              # Unary
     | expr ('*' | '/') expr         # MulDiv
     | expr ('+' | '-') expr         # AddSub
     | '(' expr ')'                  # Paren
     | NUM                           # Num
     ;

NUM : [0-9]+ ('.' [0-9]+)? ;
WS  : [ \t\r\n]+ -> skip ;
