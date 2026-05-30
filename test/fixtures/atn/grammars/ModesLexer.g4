lexer grammar ModesLexer;

// Lexer features the toy fixtures barely touch: pushMode / popMode across
// two modes, a hidden channel, a non-greedy rule, and skip inside a mode.

LT   : '<' -> pushMode(TAG) ;
TEXT : ~'<'+ ;

mode TAG;
GT      : '>' -> popMode ;
EQ      : '=' ;
STR     : '"' ~'"'* '"' ;
NAME    : [a-zA-Z_] [a-zA-Z_0-9]* ;
COMMENT : '/*' .*? '*/' -> channel(HIDDEN) ;
TWS     : [ \t\r\n]+ -> skip ;
