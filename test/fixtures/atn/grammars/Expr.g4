grammar Expr;
prog : stat+ EOF ;
stat : ID '=' expr ';' ;
expr : expr ('*' | '/') expr
     | expr ('+' | '-') expr
     | INT
     | ID
     | '(' expr ')'
     ;
ID  : [a-zA-Z_] [a-zA-Z_0-9]* ;
INT : [0-9]+ ;
WS  : [ \t\r\n]+ -> skip ;
