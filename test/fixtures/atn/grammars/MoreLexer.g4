lexer grammar MoreLexer;

// Builds a STRING token across several lexer rules with `more` (accumulate
// the matched text and keep lexing) and finalizes it with `type()` — the
// canonical more/type pattern, none of which the other fixtures exercise.

tokens { STRING }

ID  : [a-zA-Z]+ ;
NUM : [0-9]+ ;
WS  : [ \t\r\n]+ -> skip ;
OPEN_STR : '"' -> more, mode(STR) ;

mode STR;
STR_BODY  : ~'"'+ -> more ;
CLOSE_STR : '"' -> type(STRING), mode(DEFAULT_MODE) ;
