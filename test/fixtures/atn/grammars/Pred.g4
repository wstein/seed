grammar Pred;

// `item` has two alternatives that match the identical input ("ID ;") but
// build different subtrees (foo vs bar). Syntactic lookahead cannot choose
// between them, so the alternatives are genuinely ambiguous and only the
// semantic predicate `{tagged}?` on the first alternative decides: when it
// holds, `foo` is taken; otherwise `bar`. This makes a predicate's effect
// observable in the parse tree even with Seed's generic rule contexts.
prog : item EOF ;

item : {tagged}? foo
     | bar
     ;

foo : ID ';' ;
bar : ID ';' ;

WS : [ \t\r\n]+ -> skip ;
ID : [a-zA-Z]+ ;
