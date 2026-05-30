parser grammar Modes;

options { tokenVocab = ModesLexer; }

// A tiny tag language over ModesLexer: text interleaved with
// `<name attr="v" ...>` tags. The hidden COMMENT token must not reach the
// parser.

prog : item* EOF ;
item : TEXT | tag ;
tag  : LT NAME attr* GT ;
attr : NAME EQ STR ;
