parser grammar More;

options { tokenVocab = MoreLexer; }

// Each STRING is one token even though the lexer built it across rules.

prog : item* EOF ;
item : ID | NUM | STRING ;
