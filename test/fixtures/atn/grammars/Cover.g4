grammar Cover;
start : {true}? A . ~B EOF ;
A : 'a' ;
B : 'b' ;
C : 'c' ;
RANGE_T : '0'..'9' ;
ANY : . ;
