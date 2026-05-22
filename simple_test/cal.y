/* 简单的计算器 fb1-5.y */
%{
#include <stdio.h>

int yylex (void);
void yyerror (char const *);
%}

/* declare tokens */
%token NUMBER
%token ADD SUB MUL DIV ABS
%token EOL

%%

calclist:
    | calclist exp EOL { printf("= %d\n", $2); }
    ;

exp: factor { $$ = $1; }
    | exp ADD factor { $$ = $1 + $3; }
    | exp SUB factor { $$ = $1 - $3; }
    ;

factor: term { $$ = $1; }
    | factor MUL term { $$ = $1 * $3; }
    | factor DIV term { $$ = $1 / $3; }
    ;

term: NUMBER { $$ = $1; }
    | ABS term { $$ = $2 >= 0? $2 : -$2; }
    ;

%%
void main(int argc, char **argv)
{
    yyparse();
}
void yyerror (char const *s)
{
    fprintf (stderr, "%s\n", s);
}