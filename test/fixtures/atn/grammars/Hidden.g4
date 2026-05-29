grammar Hidden;

// COMMENT is routed to the hidden channel rather than skipped, so it stays
// in the token stream (for tooling) but must not reach the parser. The
// parser rule only mentions ID, so a correct stream skips the comment.
prog : ID+ EOF ;

ID      : [a-z]+ ;
COMMENT : '#' ~[\r\n]* -> channel(HIDDEN) ;
WS      : [ \t\r\n]+ -> skip ;
