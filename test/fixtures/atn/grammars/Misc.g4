parser grammar Misc;

options { tokenVocab = MiscLexer; }

// The NOTE token (custom COMMENTS channel) must not reach the parser.

prog : tok* EOF ;
tok  : WORD | NUM | STRING ;
