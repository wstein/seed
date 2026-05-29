grammar G4;

// A deliberately small grammar for a useful *subset* of ANTLR grammar files
// — enough to parse Seed's own fixtures (Hello, Expr, …) with the runtime.
// It is the ADR-007 "Phase 0" bootstrap: the tool's front end will parse .g4
// with Seed itself rather than a hand-written parser. The full ANTLR grammar
// needs a host-language lexer adaptor for mode switches, which is out of
// scope for a spike. Punctuation has explicit token rules (ordered before
// RULE_REF/TOKEN_REF) so keyword lexing is deterministic.

grammarSpec : GRAMMAR id SEMI ruleSpec+ EOF ;

ruleSpec : FRAGMENT? id COLON ruleBlock SEMI ;

ruleBlock : alternative (PIPE alternative)* ;

alternative : element* (ARROW command)? ;

element : atom ebnfSuffix? ;

ebnfSuffix : (STAR | PLUS | QUESTION) QUESTION? ;

atom
    : id
    | STRING_LITERAL
    | CHAR_SET
    | DOT
    | TILDE atom
    | LPAREN ruleBlock RPAREN
    ;

command : id (LPAREN id RPAREN)? ;

id : RULE_REF | TOKEN_REF ;

GRAMMAR  : 'grammar' ;
FRAGMENT : 'fragment' ;

COLON    : ':' ;
SEMI     : ';' ;
PIPE     : '|' ;
STAR     : '*' ;
PLUS     : '+' ;
QUESTION : '?' ;
ARROW    : '->' ;
LPAREN   : '(' ;
RPAREN   : ')' ;
DOT      : '.' ;
TILDE    : '~' ;

RULE_REF  : [a-z] [a-zA-Z0-9_]* ;
TOKEN_REF : [A-Z] [a-zA-Z0-9_]* ;

STRING_LITERAL : '\'' (~['\r\n\\] | '\\' .)* '\'' ;
CHAR_SET       : '[' (~[\]\\] | '\\' .)* ']' ;

LINE_COMMENT  : '//' ~[\r\n]* -> skip ;
BLOCK_COMMENT : '/*' .*? '*/' -> skip ;
WS            : [ \t\r\n]+ -> skip ;
