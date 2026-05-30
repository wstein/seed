lexer grammar MiscLexer;

// Stresses Unicode code points in a set, string escapes (a not-set with an
// escape alternative), and a *custom named* channel (not HIDDEN).

channels { COMMENTS }

WORD   : LETTER+ ;
NUM    : [0-9]+ ;
STRING : '"' (~["\\] | '\\' .)* '"' ;
NOTE   : '#' ~[\r\n]* -> channel(COMMENTS) ;
WS     : [ \t\r\n]+ -> skip ;

fragment LETTER : [a-zA-ZΑ-ω] ;
