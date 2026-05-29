lexer grammar LexPred;

// KEYWORD and WORD match the identical input ([a-z]+); the predicate
// `{keyword}?` on KEYWORD decides which rule wins. When it holds, KEYWORD
// (the earlier rule) is taken; when it fails, KEYWORD is pruned and WORD
// matches. This makes a lexer predicate's effect observable as the emitted
// token type.
KEYWORD : {keyword}? [a-z]+ ;
WORD    : [a-z]+ ;
WS      : [ \t\r\n]+ -> skip ;
